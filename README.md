# jackett_cli

Search torrents using Jackett's indexers and download using aria2 rpc.

### Requirements
- jackett (Default `http://localhost:9117`)
- bash 5.x.x
- fzf >= 0.36.0
- jq
- aria2c (RPC running by default on `http://localhost:6800`)

### Settings

```bash
declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117/api/v2.0/indexers
declare -r -x CACHE_DIR=~/.cache/jackett_cli
declare -r -x RPC_HOST=http://localhost
declare -r -x RPC_PORT=6800
declare -r -x DL_DIR=~/Downloads/jackett
declare -x filter=all
```

---

```
Usage: jackett_cli.sh [option] <query>

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
```


### Key bindings
```
enter       : Search
ctrl-l      : Go to last item
ctrl-f      : Go to first item last
ctrl-s      : Sort by Seeders
ctrl-g      : Sort by Grabs
ctrl-p      : Sort by Peers
alt-s       : Sort by Size
ctrl-d      : Download selected items
```
