#!/usr/bin/env bash
# shellcheck disable=SC2034
set -eo pipefail

declare -r -x PASSWORD=
declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117/api/v2.0/indexers
declare -r -x RPC_URL=http://localhost:6800
declare -r -x DL_DIR=~/Downloads/.torrents
declare -r -x FILE=/tmp/jackett_cli.$$.json
declare -r -x HISTORY=${XDG_CACHE_HOME:-${HOME}/.cache}/jackett_cli_history
declare -r -x FZF_PORT=$((RANDOM % (63000 - 20000) + 20000))
declare -r FZF_DEFAULT_OPTS="-m --reverse --exact --cycle --no-sort --tac --listen ${FZF_PORT}"
declare -x filter=all
declare -x tracker
declare -x category
declare -x COOKIE
declare -x ID

# Jackett categories from:
# https://github.com/Jackett/Jackett/wiki/Jackett-Categories
declare -A CAT
CAT["console"]=1000
CAT["console/nds"]=1010
CAT["console/psp"]=1020
CAT["console/wii"]=1030
CAT["console/xbox"]=1040
CAT["console/xbox-360"]=1050
CAT["console/wiiware"]=1060
CAT["console/xbox-360-dlc"]=1070
CAT["console/ps3"]=1080
CAT["console/other"]=1090
CAT["console/3ds"]=1110
CAT["console/ps-vita"]=1120
CAT["console/wiiu"]=1130
CAT["console/xbox-one"]=1140
CAT["console/ps4"]=1180
CAT["movies"]=2000
CAT["movies/foreign"]=2010
CAT["movies/other"]=2020
CAT["movies/sd"]=2030
CAT["movies/hd"]=2040
CAT["movies/uhd"]=2045
CAT["movies/bluray"]=2050
CAT["movies/3d"]=2060
CAT["movies/dvd"]=2070
CAT["movies/web-dl"]=2080
CAT["audio"]=3000
CAT["audio/mp3"]=3010
CAT["audio/video"]=3020
CAT["audio/audiobook"]=3030
CAT["audio/lossless"]=3040
CAT["audio/other"]=3050
CAT["audio/foreign"]=3060
CAT["pc"]=4000
CAT["pc/0day"]=4010
CAT["pc/iso"]=4020
CAT["pc/mac"]=4030
CAT["pc/mobile-other"]=4040
CAT["pc/games"]=4050
CAT["pc/mobile-ios"]=4060
CAT["pc/mobile-android"]=4070
CAT["tv"]=5000
CAT["tv/web-dl"]=5010
CAT["tv/foreign"]=5020
CAT["tv/sd"]=5030
CAT["tv/hd"]=5040
CAT["tv/uhd"]=5045
CAT["tv/other"]=5050
CAT["tv/sport"]=5060
CAT["tv/anime"]=5070
CAT["tv/documentary"]=5080
CAT["xxx"]=6000
CAT["xxx/dvd"]=6010
CAT["xxx/wmv"]=6020
CAT["xxx/xvid"]=6030
CAT["xxx/x264"]=6040
CAT["xxx/uhd"]=6045
CAT["xxx/pack"]=6050
CAT["xxx/imageset"]=6060
CAT["xxx/other"]=6070
CAT["xxx/sd"]=6080
CAT["xxx/web-dl"]=6090
CAT["books"]=7000
CAT["books/mags"]=7010
CAT["books/ebook"]=7020
CAT["books/comics"]=7030
CAT["books/technical"]=7040
CAT["books/other"]=7050
CAT["books/foreign"]=7060
CAT["other"]=8000
CAT["other/misc"]=8010
CAT["other/hashed"]=8020

help() {
    cat << EOF
Usage: ${0##*/} {command} [option] <query>

[i]ndexers          List indexers
[c]ategories        List categories

Options:
-h --help           Show this message and exit
-t --tracker        Tracker (comma separated)
-c --category       Jackett category id (comma separated)
-i --interactive    Select a filter and category interactively 
-f --filter         Indexer used for your search (Default: all)
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

auth() {
    res=$(curl -L -s -o /dev/null "${API_URL%/api*}/UI/Dashboard" \
        --data-urlencode "password=$PASSWORD" -c - | tail -1)
    [ -z "$res" ] && { echo >&2 "Authentication failed"; return 1; }
    IFS=$'\t' read -r _ _ _ _ id k v _ < <(echo "$res")
    COOKIE="Cookie: ${k}=${v};"
    ID="_=$id"
}

list_indexers() {
    if [ -r /var/lib/jackett/Indexers ];then
        for i in /var/lib/jackett/Indexers/*.json;do
            i=${i##*/} i=${i%.*}
            echo "$i"
        done
    elif auth;then
        curl -s "${API_URL}?_=$ID" -H "$COOKIE" | jq -r '.[] | select(.configured) | .id'
    else
        curl -s "${API_URL}/all/results?apikey=${API_KEY}" | jq -r '.Indexers[].ID'
    fi
}

list_cat() {
    for k in "${!CAT[@]}";do
        printf '%s (%s)\n' "${CAT[$k]}" "$k"
    done | sort -n
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
    local curr=${FILE}.curr # current fzf list
    case "$1" in
        Link|BlackholeLink)
            k=$1; shift
            for i in "$@";do 
                link=$(jq -Mcr --argjson i "${i%%:*}" --arg k "$k" '.Results[$i][$k]' "$FILE")
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
        submenu_*) # from menu
            k=${1/submenu_} k=${k%%:*}
            jq -Mcr --arg k "$k" '.Results[][$k] | "\($k):\(.)"' "$FILE" | sort -u | tee "$curr"
            ;;
        [A-Z]*:Sort*) # from menu
            [ -s "$curr" ] || return 0;
            k=${1%%:*}
            fzf_cmd "change-prompt((Sorting by ${k}) Search: )"
            # stdout only the curr listing not the whole FILE
            grep -xFf "$curr" < <(jq -Mcr --arg k "$k" \
                '.Results as $r | $r |
                [to_entries[] | {k: .key, v: .value[$k]}] |
                sort_by(.v)[] | "\(.k):\($r[.k].Title)"' "$FILE")
            ;;
        [A-Z]*:*) # from submenu
            k=${1%%:*} v=${1#*:}
            fzf_cmd "change-prompt(($v) Search: )"
            jq -Mcr --arg k "$k" --arg v "$v" \
                '.Results | to_entries[] |
                select(.value[$k] == $v) | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            ;;
        *)
            if [ -n "$2" ];then
                echo "$2" >> "$HISTORY"
            elif [ -z "$1" ];then
                [ -s "$HISTORY" ] && awk '!seen[$0]++' "$HISTORY" | sed 's/^/:/'
                return
            fi

            fzf_cmd "change-prompt(Searching... )"
            query=${2:-$1}
            [ -z "$2" ] && query=${query/:}
            url="${API_URL}/${filter:-all}/results?apikey=${API_KEY}"
            [ -n "$tracker" ]  && url="${url}&Tracker%5B%5D=$tracker"
            [ -n "$category" ] && url="${url}&Category%5B%5D=$category"
            curl -s -G "$url" -o "$FILE" \
                --data-urlencode "Query=$query" >/dev/null 2>&1

            jq -Mcr '.Results | to_entries[] | "\(.key):\(.value.Title)"' "$FILE" | tee "$curr"
            fzf_cmd 'change-prompt(Search: )'
            ;;
    esac
}

export -f main fzf_cmd addUri preview

while (( $# )) ;do
    case "$1" in
        -f|--filter) shift; filter=$1
            if [ "$filter" != all ]; then
                curl -s "${API_URL}/${filter}/results?apikey=${API_KEY}" | jq -er .error && exit 1
            fi
            ;;
        -t|--tracker)   shift; tracker=$1 ;;
        -c|--category)  shift; category=$1 ;;
        -i|--interactive)
            filter=$({ echo all; list_indexers; } | fzf --prompt 'filter: ')
            category=$(list_cat | fzf -m --prompt 'category: ' | awk '{print $1}' | tr \\n ',') || true
            [ -n "$category" ] && category=${category::-1}
            ;;
        i|indexers)     list_indexers; exit 0 ;;
        c|categories)   list_cat; exit 0 ;;
        -*) help ;;
        *)  query="${query}+$1" ;;
    esac
    shift
done

# shellcheck disable=SC2154
trap 'o=$?; rm $FILE ${FILE}.curr 2>/dev/null || true; exit $o' EXIT
main "${query:1}" | fzf --prompt 'Search: ' \
    --delimiter ':' --with-nth 2.. \
    --preview 'preview {1}' \
    --preview-window 'right,30%' \
    --border=bottom --border-label-pos=bottom \
    --border-label "( filter: ${filter}, tracker: ${tracker:-?}, cat: ${category:-?} )" \
    --bind 'ctrl-l:last' --bind 'ctrl-f:first' \
    --bind 'enter:reload(main {} {q})+clear-query' \
    --bind 'esc:reload(main menu)+clear-query' \
    --bind 'ctrl-d:execute(main Link {+})+clear-selection' \
    --bind 'ctrl-h:execute(main BlackholeLink {+})+clear-selection'
