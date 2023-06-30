# jackett_cli

Search torrents using Jackett's indexers and download using aria2 rpc.

### Requirements
- jackett (Default `http://localhost:9117`)
- bash 5.x.x
- fzf >= 0.36.0
- jq
- aria2 (RPC running by default on `http://localhost:6800`)

### Settings

```bash
declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117
declare -r -x RPC_URL=http://localhost:6800
declare -r -x DL_DIR=~/Downloads/jackett
declare -x filter=all
```


```
Usage: jackett_cli.sh [option] <query>

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
```


### Key bindings
```
enter  : Search
esc    : Menu
ctrl-l : Move to the last match
ctrl-f : Move to the first match
ctrl-d : Download selected items
```
