#!/usr/bin/env bash
# shellcheck disable=SC2034
set -eo pipefail

declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117/api/v2.0/indexers
declare -r -x RPC_URL=http://localhost:6800
declare -r -x DL_DIR=/tmp/jackett
declare -r -x FILE=/tmp/jackett_cli.$$.json
declare -r FZF_PORT=$((RANDOM % (63000 - 20000) + 20000))
declare -r FZF_DEFAULT_OPTS="--multi --exact --no-separator --cycle --no-hscroll --no-scrollbar --color=dark --no-border --no-sort --tac --listen ${FZF_PORT}"
declare -x filter=all

help() {
    cat << EOF
Usage: ${0##*/} [option] <query>

-h --help               Show this message and exit
-l --list               List indexers
-f --filter  FILTER     Indexer used for your search (Default: all)
                        Supported filters
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

list_indexers() {
    if [ -r /var/lib/jackett/Indexers ];then
        for i in /var/lib/jackett/Indexers/*.json;do
            i=${i##*/} i=${i%.*}
            echo "$i"
        done
    else
        curl -s "${API_URL}/all/results?apikey=${API_KEY}" | jq -r '.Indexers[].ID'
    fi
}

fzf_cmd() {
    curl -s -XPOST "127.0.0.1:${FZF_PORT}" -d "$1" >/dev/null 2>&1 || true
}

addUri() {
    data=$(printf '{
        "jsonrcp": "2.0",
        "id": "jackett",
        "method": "aria2.addUri",
        "params": [ ["%s"], {"dir": "%s", "bt-save-metadata": true}, 0 ]
    }' "$1" "$DL_DIR" | jq -Mc)
    curl -s "${RPC_URL}/jsonrpc" -d "$data" \
        -H "Content-Type: application/json" -H "Accept: application/json" >/dev/null 2>&1
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

main() {
    exec 2>&1
    curr=${FILE}.curr
    case "$1" in
        Link|BlackholeLink)
            k=$1; shift
            for i in "$@";do
                link=$(jq -Mcr --arg i "${i%%:*}" --arg k "$k" '.Results[$i][$k]' "$FILE")
                addUri "$link"
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
            jq -Mcr --arg k "$k" --arg v "$v" \
                '.Results | to_entries[] | select(.value[$k] == $v) | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            ;;
        *)
            query=${2:-$1}
            [ -z "$query" ] && return
            fzf_cmd "change-prompt(Searching... )"
            curl -s "${API_URL}/${filter:-all}/results?apikey=${API_KEY}&Query=${query// /+}" -o "$FILE" >/dev/null 2>&1
            jq -Mcr '.Results | to_entries[] | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            fzf_cmd 'change-prompt(Search: )'
            ;;
    esac
}

export -f main list_indexers fzf_cmd addUri preview

while (( $# )) ;do
    case "$1" in
        -f|--filter) shift; filter="$1" ;;
        -l|--list) list_indexers; exit 0 ;;
        -h|--help) help ;;
        *) query="${query}+$1" ;;
    esac
    shift
done

if [ "$filter" != all ];then
    if curl -s "${API_URL}/${filter:-all}/results?apikey=${API_KEY}" | jq -er .error
    then
        exit 1
    fi
fi

trap 'rm $FILE ${FILE}.curr 2>/dev/null; exit 0' EXIT
main "${query:1}" | fzf --prompt 'Search: ' \
    --delimiter ':' --with-nth 2.. \
    --preview 'preview {1}' \
    --preview-window 'right,30%' \
    --bind 'ctrl-l:last' \
    --bind 'ctrl-f:first' \
    --bind 'enter:reload(main {} {q})+clear-query' \
    --bind 'esc:reload(main menu)+clear-query' \
    --bind 'ctrl-d:execute(main Link {+})' \
    --bind 'ctrl-b:execute(main BlackholeLink {+})'
