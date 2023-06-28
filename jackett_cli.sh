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

trap 'rm $FILE 2>/dev/null || true' EXIT

help() {
    cat << EOF
Usage: ${0##*/} [option] <query>

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

change_prompt() {
    curl -s -XPOST localhost:1337 -d "change-prompt($1 )" || true
}

main() {
    [ -z "$1" ] && return
    case "$1" in
        download)
            shift
            for i in "$@";do
                link=$(jq -Mcr --argjson i "${i%%:*}" '.Results[$i].Link' "$FILE")
                data=$(printf '{"jsonrcp":"2.0", "id":"1", "method":"aria2.addUri", "params":[["%s"], {"dir":"%s"}]}' "$link" "$DL_DIR")
                curl -s "${RPC_HOST}:${RPC_PORT}/jsonrpc" \
                    -H "Content-Type: application/json" -H "Accept: application/json" \
                    -d "$data" 
            done
            ;;
        sort_by) 
            change_prompt "(Sorted by ${2}) Search:"
            jq -Mcr --arg k "$2" '.Results as $r | $r | [to_entries[] | {k: .key, v: .value[$k]}] | sort_by(.v)[] | "\(.k):\($r[.k].Title)"' "$FILE"
            ;;
        *)
            change_prompt 'Searching...'
            curl -s "${API_URL}/${filter:-all}/results?apikey=${API_KEY}&Query=${1// /+}" -o "$FILE"
            jq -Mcr '.Results | to_entries[] | "\(.key):\(.value.Title)"' "$FILE"
            change_prompt "Search:"
            ;;
    esac
}

preview() {
    # jq -C --argjson i "$1" '.Results[$i] | keys[]' "$FILE" | bat
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
Peers: \(.Peers)"' "$FILE"

}

init() {
    # TODO
    if ! [ -d "$CACHE_DIR" ];then
        printf 'Downloading Definitions...\n'
        curl -s 'https://github.com/Jackett/Jackett/tree/487cacf96716317299fdf4b11287a96fa4918552/src/Jackett.Common/Definitions' |
            grep -oP '(?<=href=")[^"]+\.yml' | sed 's/\/blob//; s/^/https:\/\/raw.githubusercontent.com/' |
            aria2c -j 2 --summary-interval=0 --allow-overwrite=false --auto-file-renaming=false --dir="$CACHE_DIR" --input-file=- 
    fi
} # && init

export -f preview main change_prompt
n=$'\n'
main "${query:1}" | fzf --prompt 'Search: ' \
    --header "Sort: C-s Seeders C-g Grabs C-p Peers A-s Size${n}Download: C-d" \
    --delimiter ':' --nth 2.. --with-nth 2.. \
    --preview 'preview {1}' \
    --bind 'enter:reload(main {q})+clear-query' \
    --bind 'ctrl-l:last' --bind 'ctrl-f:first' \
    --bind 'ctrl-s:reload(main sort_by Seeders)' \
    --bind 'ctrl-g:reload(main sort_by Grabs)' \
    --bind 'ctrl-p:reload(main sort_by Peers)' \
    --bind 'alt-s:reload(main sort_by Size)' \
    --bind 'ctrl-d:execute(main download {1})'
