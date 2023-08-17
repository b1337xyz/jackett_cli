#!/usr/bin/env bash
# shellcheck disable=SC2034
set -eo pipefail

declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117
declare -r -x RPC_URL=http://localhost:6800
declare -r -x DL_DIR=~/Downloads/jackett
declare -r -x FILE=/tmp/jackett_cli.$$.json
declare -r FZF_DEFAULT_OPTS="--multi --exact --no-separator --cycle --no-hscroll --no-scrollbar --color=dark --no-border --no-sort --tac --listen 1337"
declare -x filter=all

help() {
    cat << EOF
Usage: ${0##*/} [option] <query>

-h --help               Show this message and exit
-i --indexer INDEXER    Indexer used for your search (Default: all)
-f --filter  FILTER     Supported filters
                            type:<type>
                            tag:<tag>
                            lang:<tag>
                            test:{passed|failed}
                            status:{healthy|failing|unknown}
                        Supported operators:
                            !<expr>
                            <expr1>+<expr2>[+<expr3>...]
                            <expr1>,<expr2>[,<expr3>...]

More about filters: https://github.com/Jackett/Jackett#filter-indexers

EOF

    exit 0
}

while (( $# )) ;do
    case "$1" in
        -f|--filter|-i|--indexer) shift; filter="$1" ;;
        -h|--help) help ;;
        *) query="${query}+$1" ;;
    esac
    shift
done

fzf_port=$((RANDOM % (63000 - 20000) + 20000))
fzf_cmd() { curl -s -XPOST localhost:${fzf_port} -d "$1" >/dev/null 2>&1 || true; }

main() {
    curr=${FILE}.curr
    case "$1" in
        download)
            shift
            for i in "$@";do
                link=$(jq -Mcr --argjson i "${i%%:*}" '.Results[$i].Link' "$FILE")
                blink=$(jq -Mcr --argjson i "${i%%:*}" '.Results[$i].BlackholeLink' "$FILE")
                data=$(printf '{
                    "jsonrcp": "2.0",
                    "id": "jackett",
                    "method": "aria2.addUri",
                    "params": [
                        ["%s", "%s"],
                        {"dir": "%s", "bt-save-metadata": true}
                    ]
                }' "$link" "$blink" "$DL_DIR" | jq -Mc)
                curl -s "${RPC_URL}/jsonrpc" -d "$data" \
                    -H "Content-Type: application/json" -H "Accept: application/json" >/dev/null 2>&1
            done
            ;;
        menu)
            fzf_cmd "change-prompt(Menu: )"
            for i in Title Seeders Peers Grabs Size Tracker;do echo "$i:Sort by $i" ;done
            echo 'PublishDate:Sort by Date'
            echo 'CategoryDesc:Sort by Category'
            echo 'submenu_CategoryDesc:Category'
            echo 'submenu_Tracker:Tracker'
            echo 'submenu_TrackerType:Type'
            ;;
        submenu_*)
            k=${1/submenu_} k=${k%%:*}
            jq -Mcr --arg k "$k" '.Results[][$k] | "\($k):\(.)"' "$FILE" | sort -u
            ;;
        [A-Z]*:Sort*) 
            k=${1%%:*}
            fzf_cmd "change-prompt((Sorting by ${k}) Search: )"
            grep -xFf "$curr" < <(jq -Mcr --arg k "$k" \
                '.Results as $r | $r | [to_entries[] | {k: .key, v: .value[$k]}] | sort_by(.v)[] | "\(.k):\($r[.k].Title)"' "$FILE")
            ;;
        [A-Z]*:*)
            k=${1%%:*} v=${1#*:}
            fzf_cmd "change-prompt(($v) Search: )"
            jq -Mcr --arg k "$k" --arg v "$v" '.Results | to_entries[] | select(.value[$k] == $v) | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            ;;
        *)
            query=${2:-$1}
            [ -z "$query" ] && return
            fzf_cmd "change-prompt(Searching... )"
            curl -s "${API_URL}/api/v2.0/indexers/${filter:-all}/results?apikey=${API_KEY}&Query=${query// /+}" -o "$FILE" >/dev/null 2>&1
            jq -Mcr '.Results | to_entries[] | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            fzf_cmd 'change-prompt(Search: )'
            ;;
    esac
}

preview() {
    jq -Mcr --argjson i "$1" --argjson units '["B", "K", "M", "G", "T", "P"]' '
    def psize(size;i):
        if (size < 1000) then
            "\(size * 100 | floor | ./100) \($units[i])"
        else
            psize(size / 1000;i+1)
        end;

    .Results[$i] | "Tracker: \(.Tracker)
Type: \(.TrackerType)
Category: \(.CategoryDesc)
Date: \(.PublishDate)
Size: \(psize(.Size;0))
Grabs: \(.Grabs)
Seeders: \(.Seeders)
Peers: \(.Peers)"' "$FILE" 2>/dev/null

}

export -f preview main fzf_cmd
trap 'rm $FILE ${FILE}.curr 2>/dev/null || true' EXIT
main "${query:1}" | fzf --prompt 'Search: ' \
    --delimiter ':' --with-nth 2.. \
    --preview 'preview {1}' \
    --preview-window 'right,30%' \
    --bind 'ctrl-l:last' \
    --bind 'ctrl-f:first' \
    --bind 'enter:reload(main {} {q})+clear-query' \
    --bind 'esc:reload(main menu)+clear-query' \
    --bind 'ctrl-d:execute(main download {+})'
