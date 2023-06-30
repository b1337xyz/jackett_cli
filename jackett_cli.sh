#!/usr/bin/env bash
# shellcheck disable=SC2034
set -eo pipefail

declare -r -x API_KEY=
declare -r -x API_URL=http://localhost:9117/api/v2.0/indexers
declare -r -x CACHE_DIR=~/.cache/jackett_cli
declare -r -x RPC_HOST=http://localhost
declare -r -x RPC_PORT=6800
declare -r -x DL_DIR=~/Downloads/jackett
declare -r -x FILE=/tmp/jackett_cli.$$.json
declare -r FZF_DEFAULT_OPTS="--multi --exact --no-separator --cycle --no-hscroll --no-scrollbar --color=dark --no-border --no-sort --tac --listen 1337"
declare -x filter=all

trap 'rm $FILE ${FILE}.curr ${FILE}.prev 2>/dev/null || true' EXIT

help() {
    cat << EOF
Usage: ${0##*/} [option] <query>

-h --help               Show this message and exit

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

-i --indexer INDEXER    Indexer used for your search (Default: all)

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

fzf_cmd() { curl -s -XPOST localhost:1337 -d "$1" >/dev/null 2>&1 || true; }

main() {
    prev=${FILE}.prev
    curr=${FILE}.curr
    case "$1" in
        download)
            shift
            for i in "$@";do
                link=$(jq -Mcr --argjson i "${i%%:*}" '.Results[$i].Link' "$FILE")
                data=$(printf '{"jsonrcp":"2.0", "id":"1", "method":"aria2.addUri", "params":[["%s"], {"dir":"%s"}]}' "$link" "$DL_DIR")
                curl -s "${RPC_HOST}:${RPC_PORT}/jsonrpc" \
                    -H "Content-Type: application/json" -H "Accept: application/json" \
                    -d "$data" >/dev/null 2>&1
            done
            ;;
        menu)
            fzf_cmd "change-prompt(Menu: )"
            for i in Title Seeders Peers Grabs Size Tracker;do echo "$i:Sort by $i" ;done
            echo 'PublishDate:Sort by Date'
            echo 'CategoryDesc:Sort by Category'
            echo 'CategoryDesc:Category'
            echo 'TrackerType:Type'
            ;;
        [A-Z]*:Sort*) 
            k=${1%%:*}
            fzf_cmd "change-prompt((Sorting by ${k}) Search: )"
            grep -xFf "$prev" < <(jq -Mcr --arg k "$k" \
                '.Results as $r | $r | [to_entries[] | {k: .key, v: .value[$k]}] | sort_by(.v)[] | "\(.k):\($r[.k].Title)"' "$FILE") | tee "$curr"
            ;;
        [A-Z]*:Category|[A-Z]*:Type)
            k=${1%%:*}
            jq -Mcr --arg k "$k" '.Results[][$k] | "\($k):\(.)"' "$FILE" | sort -u
            ;;
        [A-Z]*:*)
            k=${1%%:*} v=${1##*:}
            fzf_cmd "change-prompt(($v) Search: )"
            jq -Mcr --arg k "$k" --arg v "$v" '.Results | to_entries[] | select(.value[$k] == $v) | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            ;;
        *)
            query=${2:-$1}
            fzf_cmd "change-prompt(Searching... )"
            curl -s "${API_URL}/${filter:-all}/results?apikey=${API_KEY}&Query=${query// /+}" -o "$FILE"
            jq -Mcr '.Results | to_entries[] | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            fzf_cmd 'change-prompt(Search: )'
            ;;
    esac
    cp "$curr" "$prev"
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
Title: \(.Title)
Category: \(.CategoryDesc)
Date: \(.PublishDate)
Size: \(psize(.Size;0))
Grabs: \(.Grabs)
Seeders: \(.Seeders)
Peers: \(.Peers)"' "$FILE" 2>/dev/null

}

export -f preview main fzf_cmd
n=$'\n'
main "${query:1}" | fzf --prompt 'Search: ' \
    --delimiter ':' --with-nth 2.. \
    --preview 'preview {1}' \
    --bind 'ctrl-l:last' \
    --bind 'ctrl-f:first' \
    --bind 'enter:reload(main {} {q})+clear-query' \
    --bind 'tab:reload(main menu)' \
    --bind 'ctrl-d:execute(main download {+})'
