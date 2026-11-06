#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf -- "$TEST_DIR"' EXIT
export CDA_CONFIG_DIR="$TEST_DIR/config"
export CDA_ALIASES_FILE="$CDA_CONFIG_DIR/aliases"
export CDA_HISTORY_FILE="$TEST_DIR/state/recent"
unset CDA_HISTORY_LIMIT
source "$ROOT/cda.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
read_history() { mapfile -d '' -t saved < "$CDA_HISTORY_FILE"; }
mkdir -p "$TEST_DIR/a" "$TEST_DIR/b with spaces" "$TEST_DIR/removed"
weird="$TEST_DIR/"$'tabs\tline\nbreak\\'
mkdir -p "$weird"
_cda_save_directory "$TEST_DIR/a"
_cda_save_directory "$TEST_DIR/b with spaces"
_cda_save_directory "$TEST_DIR/a"
read_history
[[ ${#saved[@]} == 2 && ${saved[0]} == "$TEST_DIR/a" ]] || fail deduplication
_cda_save_directory "$weird"
cda --recent <<< 1 >/dev/null
[[ $PWD == "$weird" ]] || fail 'unusual directory path'
cd -- "$ROOT"
cda --recent <<< '' >/dev/null
[[ $PWD == "$ROOT" ]] || fail cancellation
cda --recent </dev/null >/dev/null
for invalid in 0 99 abc '1+1' 99999999999999999999; do
  if cda --recent <<< "$invalid" >/dev/null 2>&1; then fail 'invalid input accepted'; fi
done
_cda_save_directory "$TEST_DIR/removed"
rmdir "$TEST_DIR/removed"
cda --recent <<< 1 >/dev/null
[[ $PWD == "$weird" ]] || fail 'missing directory was not skipped'
cd -- "$ROOT"
# A new process sees the same history and changes its own working directory.
bash --noprofile --norc -c 'source "$1/cda.sh"; cda --recent <<< 1 >/dev/null; [[ $PWD == "$2" ]]' _ "$ROOT" "$weird" || fail persistence
# A bare recent is an ordinary alias name, never a picker shortcut.
if cda recent <<< 1 >/dev/null 2>&1; then fail 'bare recent opened picker'; fi
[[ $PWD == "$ROOT" ]] || fail 'bare recent changed directory'
COMP_WORDS=(cda rec)
COMP_CWORD=1
_cda_completion || :
[[ ${#COMPREPLY[@]} == 0 ]] || fail 'bare recent offered as command'
COMP_WORDS=(cda --rec)
_cda_completion
[[ ${COMPREPLY[*]} == --recent ]] || fail 'recent flag missing from completion'
cda -a recent "$TEST_DIR/a" >/dev/null
cda recent
[[ $PWD == "$TEST_DIR/a" ]] || fail 'recent alias compatibility'
cda --recent <<< 1 >/dev/null
[[ $PWD == "$weird" ]] || fail 'explicit picker with recent alias'
cd -- "$ROOT"
# Preserve both kinds of PROMPT_COMMAND and avoid duplicate hooks.
PROMPT_COMMAND='printf old'
_cda_install_prompt_hook
_cda_install_prompt_hook
[[ $PROMPT_COMMAND == $'printf old\n_cda_record_prompt' ]] || fail 'string prompt hook'
PROMPT_COMMAND=('printf one' 'printf two')
_cda_install_prompt_hook
_cda_install_prompt_hook
[[ ${#PROMPT_COMMAND[@]} == 3 && ${PROMPT_COMMAND[0]} == 'printf one' && ${PROMPT_COMMAND[2]} == _cda_record_prompt ]] || fail 'array prompt hook'
# Reloading an earlier version moves its hook after existing prompt commands.
unset PROMPT_COMMAND
PROMPT_COMMAND='_cda_record_prompt;printf old'
_cda_install_prompt_hook
[[ $PROMPT_COMMAND == $'printf old\n_cda_record_prompt' ]] || fail 'legacy hook migration'
# Unchanged prompts must not invoke the writer.
_CDA_LAST_DIRECTORY=$PWD
(_cda_save_directory() { fail 'unchanged directory written'; }; _cda_record_prompt)
# Concurrent shells must retain every update while below the cap.
export CDA_HISTORY_FILE="$TEST_DIR/concurrent/recent"
export CDA_HISTORY_LIMIT=20
pids=()
for n in {1..12}; do
  mkdir "$TEST_DIR/d$n"
  bash --noprofile --norc -c 'source "$1/cda.sh"; _cda_save_directory "$2"' _ "$ROOT" "$TEST_DIR/d$n" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "$pid" || fail concurrency; done
read_history
[[ ${#saved[@]} == 12 ]] || fail 'concurrent updates lost'
unset CDA_HISTORY_LIMIT
for n in {13..25}; do
  mkdir "$TEST_DIR/d$n"
  _cda_save_directory "$TEST_DIR/d$n"
done
read_history
[[ ${#saved[@]} == 10 && ${saved[0]} == "$TEST_DIR/d25" ]] || fail 'history limit or ordering'
[[ $(stat -c %a "$CDA_HISTORY_FILE") == 600 ]] || fail permissions
# Noninteractive sourcing leaves PROMPT_COMMAND untouched.
bash --noprofile --norc -c 'PROMPT_COMMAND=original; source "$1/cda.sh"; [[ $PROMPT_COMMAND == original ]]' _ "$ROOT" || fail 'noninteractive hook'
# Exercise automatic registration in a real interactive shell without user rc.
bash --noprofile --norc -i -c 'source "$1/cda.sh"; source "$1/cda.sh"; [[ $PROMPT_COMMAND == _cda_record_prompt ]]' _ "$ROOT" 2>/dev/null || fail 'interactive hook'
# Real prompts persist the final location before shell exit.
CDA_TEST_SOURCE="$ROOT/cda.sh" CDA_TEST_TARGET="$TEST_DIR/b with spaces" \
  bash --noprofile --norc -i >/dev/null 2>&1 <<'SHELL'
source "$CDA_TEST_SOURCE"
cd -- "$CDA_TEST_TARGET"
exit
SHELL
read_history
[[ ${saved[0]} == "$TEST_DIR/b with spaces" ]] || fail 'automatic prompt recording'
# Failed writes preserve old history and do not mark the directory as saved.
if (_cda_save_directory() { return 1; }; unset _CDA_LAST_DIRECTORY; _cda_record_prompt; [[ -v _CDA_LAST_DIRECTORY ]]); then
  fail 'failed write cached'
fi
before=$(sha256sum "$CDA_HISTORY_FILE")
if (flock() { return 1; }; _cda_save_directory "$TEST_DIR/a") 2>/dev/null; then
  fail 'lock failure ignored'
fi
[[ $(sha256sum "$CDA_HISTORY_FILE") == "$before" ]] || fail 'failed lock changed history'
# Configured limits apply to storage and the picker, including a limit of one.
(
  export CDA_HISTORY_FILE="$TEST_DIR/configurable/recent"
  mkdir -p -- "$(dirname -- "$CDA_HISTORY_FILE")"
  printf '%s\0' "$TEST_DIR/a" "$TEST_DIR/missing" > "$CDA_HISTORY_FILE"
  cda --recent <<< 1 >/dev/null
  [[ $PWD == "$TEST_DIR/a" ]] || fail 'trailing missing directory'
  CDA_HISTORY_LIMIT=1
  _cda_save_directory "$TEST_DIR/a"
  _cda_save_directory "$TEST_DIR/b with spaces"
  read_history
  [[ ${#saved[@]} == 1 && ${saved[0]} == "$TEST_DIR/b with spaces" ]] || fail 'limit one'
  CDA_HISTORY_LIMIT=3
  _cda_save_directory "$TEST_DIR/a"
  _cda_save_directory "$weird"
  read_history
  [[ ${#saved[@]} == 3 ]] || fail 'increased limit'
  CDA_HISTORY_LIMIT=1
  if cda --recent <<< 2 >/dev/null 2>&1; then fail 'picker ignored configured limit'; fi
  _cda_save_directory "$TEST_DIR/a"
  read_history
  [[ ${#saved[@]} == 1 && ${saved[0]} == "$TEST_DIR/a" ]] || fail 'shrinking limit'
  before=$(sha256sum "$CDA_HISTORY_FILE")
  for invalid in '' 0 -1 01 abc '1+1' 10001 99999999999999999999; do
    CDA_HISTORY_LIMIT=$invalid
    if _cda_save_directory "$weird" 2>/dev/null; then fail 'invalid limit saved'; fi
    if cda --recent </dev/null >/dev/null 2>&1; then fail 'invalid picker limit accepted'; fi
  done
  [[ $(sha256sum "$CDA_HISTORY_FILE") == "$before" ]] || fail 'invalid limit changed history'
  _cda_validate_history_limit 10000 || fail 'maximum limit rejected'
  # Larger histories must allow selections above 99.
  CDA_HISTORY_LIMIT=105
  for n in {1..105}; do
    mkdir "$TEST_DIR/large$n"
    _cda_save_directory "$TEST_DIR/large$n"
  done
  read_history
  [[ ${#saved[@]} == 105 ]] || fail 'large history truncated'
  cda --recent <<< 105 >/dev/null
  [[ $PWD == "$TEST_DIR/large1" ]] || fail 'three-digit selection'
)
# Preserve real command status for prompt code and the user, without extra ERR traps.
for prompt_type in scalar array; do
  CDA_TEST_SOURCE="$ROOT/cda.sh" CDA_TEST_PROMPT_TYPE="$prompt_type" \
    CDA_TEST_STATUS="$TEST_DIR/status-$prompt_type" \
    CDA_TEST_USER_STATUS="$TEST_DIR/user-status-$prompt_type" \
    CDA_TEST_ERRORS="$TEST_DIR/errors-$prompt_type" \
    bash --noprofile --norc -i >/dev/null 2>&1 <<'SHELL'
if [[ $CDA_TEST_PROMPT_TYPE == array ]]; then
  PROMPT_COMMAND=('printf "%s\n" "$?" >> "$CDA_TEST_STATUS"' ':')
else
  PROMPT_COMMAND='printf "%s\n" "$?" >> "$CDA_TEST_STATUS" # trailing comment'
fi
source "$CDA_TEST_SOURCE"
source "$CDA_TEST_SOURCE"
trap 'printf "ERR\n" >> "$CDA_TEST_ERRORS"' ERR
(exit 37)
printf '%s\n' "$?" > "$CDA_TEST_USER_STATUS"
exit
SHELL
  statuses=()
  mapfile -t statuses < "$TEST_DIR/status-$prompt_type"
  [[ ${statuses[${#statuses[@]} - 2]} == 37 ]] || fail 'prompt command lost exit status'
  [[ $(cat "$TEST_DIR/user-status-$prompt_type") == 37 ]] || fail 'user lost exit status'
  [[ $(cat "$TEST_DIR/errors-$prompt_type") == ERR ]] || fail 'extra ERR trap'
done
# Shell noclobber must not prevent private history or lock-file updates.
(
  export CDA_HISTORY_FILE="$TEST_DIR/noclobber/recent"
  set -C
  _cda_save_directory "$TEST_DIR/a"
  _cda_save_directory "$TEST_DIR/b with spaces"
  read_history
  [[ ${#saved[@]} == 2 && ${saved[0]} == "$TEST_DIR/b with spaces" ]] || fail noclobber
)
# Invalid file types fail clearly, without moving a temporary file into a directory.
(
  export CDA_HISTORY_FILE="$TEST_DIR/not-a-file"
  mkdir "$CDA_HISTORY_FILE"
  if _cda_save_directory "$TEST_DIR/a" 2>/dev/null; then fail 'directory path accepted'; fi
  if cda --recent </dev/null >/dev/null 2>&1; then fail 'directory picker path accepted'; fi
  shopt -s nullglob dotglob
  contents=("$CDA_HISTORY_FILE"/*)
  [[ ${#contents[@]} == 0 ]] || fail 'temporary history moved into directory'
  rmdir "$CDA_HISTORY_FILE"
  mkfifo "$CDA_HISTORY_FILE"
  if _cda_save_directory "$TEST_DIR/a" 2>/dev/null; then fail 'FIFO path accepted'; fi
  if cda --recent </dev/null >/dev/null 2>&1; then fail 'FIFO picker path accepted'; fi
)
# The picker needs no writable alias configuration and must not create one.
(
  ALIASES_FILE="$TEST_DIR/unused-aliases"
  cda --recent </dev/null >/dev/null
  [[ ! -e "$ALIASES_FILE" ]] || fail 'picker created alias file'
  ALIASES_FILE=/dev/null/aliases
  cda --recent </dev/null >/dev/null || fail 'picker depends on alias configuration'
)
# Relative overrides are resolved once, so changing directories keeps one history.
(
  cd -- "$TEST_DIR"
  CDA_HISTORY_FILE=relative/recent
  source "$ROOT/cda.sh"
  [[ $CDA_HISTORY_FILE == "$TEST_DIR/relative/recent" ]] || fail 'relative history not resolved'
  _cda_save_directory "$PWD"
  cd -- "$TEST_DIR/a"
  _cda_save_directory "$PWD"
  read_history
  [[ ${#saved[@]} == 2 && ${saved[0]} == "$TEST_DIR/a" ]] || fail 'relative history split by cwd'
  [[ ! -e "$TEST_DIR/a/relative" ]] || fail 'relative history created in second cwd'
  # Changing it after sourcing must fail clearly rather than splitting history.
  CDA_HISTORY_FILE=another/recent
  if _cda_save_directory "$PWD" 2>/dev/null; then fail 'relative override accepted after source'; fi
)
# Readonly prompt configuration is preserved and does not abort shell startup.
for prompt_type in scalar array; do
  CDA_TEST_SOURCE="$ROOT/cda.sh" CDA_TEST_PROMPT_TYPE="$prompt_type" \
    bash --noprofile --norc -c '
      set -eu
      if [[ $CDA_TEST_PROMPT_TYPE == array ]]; then
        PROMPT_COMMAND=(":" "printf old")
      else
        PROMPT_COMMAND=":"
      fi
      readonly PROMPT_COMMAND
      before=$(declare -p PROMPT_COMMAND)
      source "$CDA_TEST_SOURCE"
      _cda_install_prompt_hook
      [[ $(declare -p PROMPT_COMMAND) == "$before" ]]
    ' 2>"$TEST_DIR/readonly-$prompt_type" || fail 'readonly prompt aborted startup'
  [[ $(cat "$TEST_DIR/readonly-$prompt_type") == *'PROMPT_COMMAND is readonly'* ]] || fail 'readonly prompt silently skipped'
done
# Bad lock-file types must fail before opening them (a FIFO would block forever).
(
  CDA_HISTORY_FILE="$TEST_DIR/bad-lock/recent"
  mkdir -p "$(dirname -- "$CDA_HISTORY_FILE")"
  mkfifo "${CDA_HISTORY_FILE}.lock"
  if _cda_save_directory "$TEST_DIR/a" 2>/dev/null; then fail 'FIFO lock accepted'; fi
  [[ ! -e "$CDA_HISTORY_FILE" ]] || fail 'invalid lock created history'
)
# A failed replacement leaves history unchanged and cleans up its temporary file.
(
  CDA_HISTORY_FILE="$TEST_DIR/failed-replacement/recent"
  _cda_save_directory "$TEST_DIR/a"
  before=$(sha256sum "$CDA_HISTORY_FILE")
  mv() { return 42; }
  if _cda_save_directory "$TEST_DIR/b with spaces"; then fail 'failed replacement ignored'; fi
  [[ $(sha256sum "$CDA_HISTORY_FILE") == "$before" ]] || fail 'failed replacement corrupted history'
  shopt -s nullglob
  leftovers=("${CDA_HISTORY_FILE}".??????)
  [[ ${#leftovers[@]} == 0 ]] || fail 'failed replacement leaked temporary file'
)
echo 'All recent-directory checks passed.'
