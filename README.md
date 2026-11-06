# cda

`cda` is a small Bash helper for jumping to named directories.

It is meant to be sourced by your shell so it can run `cd` in the current shell process:

```bash
cda <alias>
```

Aliases are stored in `~/.config/cda/aliases` as a simple tab-separated text file.

## Install

Choose a directory where you keep local tools or project checkouts, for example:

```bash
mkdir -p ~/tools
cd ~/tools
```

Then clone the repo:

```bash
git clone https://github.com/hruskamiro/cda.git
cd cda
```

Run the installer:

```bash
./install.sh
```

Open a new Bash shell, or reload your current one:

```bash
source ~/.bashrc
```

Check the install:

```bash
cda -l
cda <alias>
```

## Doctor

Run the dependency and shell integration check without changing anything:

```bash
./install.sh check
```

`check`, `doctor`, and `--check` are equivalent.

## Usage

```bash
cda --recent                # choose recent directories (default: 10)
cda <alias>                 # change to a configured directory
cda -a                      # add/update alias named after current directory
cda -a <alias> [directory]  # add/update alias, directory defaults to $PWD
cda -r                      # remove aliases pointing to $PWD
cda -r <alias>              # remove an alias
cda -R                      # remove all aliases after confirmation
cda -l                      # list configured aliases
cda -h                      # show help
```

Examples:

```bash
cda -a work ~/projects/work
cda -a
cda work
cda -r
cda -l
```

## Recent directories

Run `cda --recent` to choose from the last 10 unique locations saved across
terminal sessions. Enter a number to jump there; Enter alone cancels. Requires
`flock` for automatic tracking.

To change the limit (1–10000), add this before the cda
source line in `~/.bashrc`:

```bash
CDA_HISTORY_LIMIT=50
```

Reload `~/.bashrc` in every open terminal so they use the same limit. A smaller
limit trims shared history; increasing it cannot restore discarded entries.

## Config

Alias data lives outside the repo:

```text
~/.config/cda/aliases
```

Override the config location with `CDA_ALIASES_FILE`:

```bash
CDA_ALIASES_FILE=/path/to/aliases source ~/tools/cda/cda.sh
```

The file format is one alias per line:

```text
alias<TAB>/absolute/path
```

## Uninstall

Remove the startup entry from `~/.bashrc`:

```bash
cd ~/tools/cda
./install.sh uninstall
```

Then remove the clone if you no longer want the source:

```bash
rm -rf ~/tools/cda
```

## License

MIT. See [LICENSE](LICENSE).
