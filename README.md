# jackett_cli

Search torrents using Jackett's indexers and download using aria2 rpc.

### Requirements
- bash 5.x.x
- [jackett](https://github.com/Jackett/Jackett) (Default `http://localhost:9117`)
- [fzf](https://github.com/junegunn/fzf) >= 0.36.0
- [jq](https://github.com/jqlang/jq)
- [aria2](https://aria2.github.io/) (RPC running by default on `http://localhost:6800`)

### Install
```
git clone git@github.com:b1337xyz/jackett_cli.git
cd jackett_cli
make install
```

### [Settings](https://github.com/b1337xyz/jackett_cli/blob/main/jackett_cli.sh#L5)

```bash
declare -r -x PASSWORD
declare -r -x API_KEY=YOUR_API_KEY_HERE
declare -r -x API_URL=http://localhost:9117/api/v2.0/indexers
declare -r -x RPC_URL=http://localhost:6800
declare -r -x DL_DIR=~/Downloads/jackett
```

### Key bindings
```
enter  : Search
esc    : Menu
ctrl-l : Move to the last match
ctrl-f : Move to the first match
ctrl-d : Download selected items
```

```
Usage: jackett_cli {command} [option] <query>

[i]ndexers      List indexers
[c]ategories    List categories

Options:
-h --help       Show this message and exit
-t --tracker    Tracker (comma separated)
-c --category   Jackett category id (comma separated)
-f --filter     Indexer used for your search (Default: all)
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
```
