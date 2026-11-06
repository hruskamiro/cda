#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
CDA_SH="${ROOT_DIR}/cda.sh"
CDA_CONFIG_DIR="${CDA_CONFIG_DIR:-${XDG_CONFIG_HOME:-${HOME}/.config}/cda}"
ALIASES_FILE="${CDA_ALIASES_FILE:-${CDA_CONFIG_DIR}/aliases}"
BASHRC="${CDA_BASHRC:-${HOME}/.bashrc}"
SOURCE_LINE="source ${CDA_SH}"
CDA_BLOCK_BEGIN="# >>> cda directory aliases >>>"
CDA_BLOCK_END="# <<< cda directory aliases <<<"
LEGACY_COMMENT="# cda directory aliases"
CHECK_ONLY=0
UNINSTALL=0

usage() {
  cat <<USAGE
Usage: ./install.sh [options]

Options:
  --check, check, doctor    Check dependencies and shell integration only.
  uninstall, --uninstall    Remove the cda source line from the Bash startup file.
  -h, --help                Show this help.

Environment:
  CDA_BASHRC                Bash startup file to update. Defaults to ~/.bashrc.
  CDA_CONFIG_DIR            Config directory. Defaults to ~/.config/cda.
  CDA_ALIASES_FILE          Alias file. Defaults to \$CDA_CONFIG_DIR/aliases.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check|check|doctor)
      CHECK_ONLY=1
      shift
      ;;
    uninstall|--uninstall)
      UNINSTALL=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

REQUIRED_MISSING=0
WARNINGS=0

report_ok() {
  printf '  [ok]   %s\n' "$1"
}

report_warn() {
  printf '  [warn] %s\n' "$1"
  WARNINGS=$((WARNINGS + 1))
}

report_fail() {
  printf '  [miss] %s\n' "$1"
  REQUIRED_MISSING=$((REQUIRED_MISSING + 1))
}

command_status() {
  local command_name="$1"
  local label="$2"

  if command -v "${command_name}" >/dev/null 2>&1; then
    report_ok "${label}: $(command -v "${command_name}")"
  else
    report_fail "${label}: ${command_name} not found"
  fi
}

check_files() {
  echo "Project files"

  if [[ -f "${CDA_SH}" ]]; then
    report_ok "cda.sh exists"
  else
    report_fail "cda.sh is missing at ${CDA_SH}"
  fi

}

check_config() {
  echo "Config"

  if [[ -d "$(dirname -- "${ALIASES_FILE}")" ]]; then
    report_ok "config directory exists: $(dirname -- "${ALIASES_FILE}")"
  else
    report_warn "config directory does not exist yet: $(dirname -- "${ALIASES_FILE}")"
  fi

  if [[ -f "${ALIASES_FILE}" ]]; then
    report_ok "aliases file exists: ${ALIASES_FILE}"
  else
    report_warn "aliases file does not exist yet: ${ALIASES_FILE}"
  fi

  if [[ -r "${ALIASES_FILE}" && -w "${ALIASES_FILE}" ]]; then
    report_ok "aliases file is readable and writable"
  elif [[ -e "${ALIASES_FILE}" ]]; then
    report_fail "aliases file must be readable and writable"
  fi
}

check_repo_data() {
  echo "Repo data"

  if [[ -e "${ROOT_DIR}/data/aliases.ini" ]]; then
    report_warn "old repo-local aliases file still exists: data/aliases.ini"
  elif [[ -e "${ROOT_DIR}/data/aliases" ]]; then
    report_warn "repo-local aliases file still exists: data/aliases"
  else
    report_ok "no repo-local aliases file"
  fi
}

check_commands() {
  echo "Commands"
  command_status bash "Bash"
  command_status awk "awk"
  if command -v flock >/dev/null 2>&1; then
    report_ok "flock (recent directory tracking): $(command -v flock)"
  else
    report_warn "flock not found: recent tracking is unavailable; named aliases still work"
  fi
}

check_shell_integration() {
  echo "Shell integration"

  if [[ -f "${BASHRC}" ]]; then
    report_ok "startup file exists: ${BASHRC}"
    if grep -F -- "${SOURCE_LINE}" "${BASHRC}" >/dev/null 2>&1; then
      report_ok "cda is sourced from ${BASHRC}"
    else
      report_warn "cda is not sourced from ${BASHRC}"
    fi
  else
    report_warn "startup file does not exist yet: ${BASHRC}"
  fi
}

cleanup_shell_integration() {
  if [[ ! -f "${BASHRC}" ]]; then
    return 1
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  awk \
    -v begin="${CDA_BLOCK_BEGIN}" \
    -v end="${CDA_BLOCK_END}" \
    -v source_line="${SOURCE_LINE}" \
    -v legacy_comment="${LEGACY_COMMENT}" '
      $0 == begin {
        changed = 1
        in_block = 1
        next
      }
      in_block && $0 == end {
        changed = 1
        in_block = 0
        next
      }
      in_block {
        changed = 1
        next
      }
      $0 == source_line {
        changed = 1
        next
      }
      $0 == legacy_comment {
        changed = 1
        next
      }
      { print }
      END {
        exit changed ? 2 : 0
      }
    ' "${BASHRC}" > "${tmp_file}" || {
      local status=$?
      if [[ "${status}" -eq 2 ]]; then
        mv "${tmp_file}" "${BASHRC}"
        return 0
      fi
      rm -f "${tmp_file}"
      return "${status}"
    }

  rm -f "${tmp_file}"
  return 1
}

shell_integration_is_current() {
  [[ -f "${BASHRC}" ]] || return 1

  awk \
    -v begin="${CDA_BLOCK_BEGIN}" \
    -v end="${CDA_BLOCK_END}" \
    -v source_line="${SOURCE_LINE}" \
    -v legacy_comment="${LEGACY_COMMENT}" '
      $0 == begin { begin_count++ }
      $0 == end { end_count++ }
      $0 == source_line { source_count++ }
      $0 == legacy_comment { legacy_count++ }
      END {
        if (begin_count == 1 && end_count == 1 && source_count == 1 && legacy_count == 0) {
          exit 0
        }
        exit 1
      }
    ' "${BASHRC}"
}

run_dependency_report() {
  REQUIRED_MISSING=0
  WARNINGS=0

  echo "cda dependency check"
  echo "Repository: ${ROOT_DIR}"
  echo "Startup file: ${BASHRC}"
  echo

  check_files
  echo
  check_config
  echo
  check_repo_data
  echo
  check_commands
  echo
  check_shell_integration
  echo

  if [[ "${REQUIRED_MISSING}" -eq 0 ]]; then
    echo "Required dependencies: ok"
  else
    echo "Required dependencies missing: ${REQUIRED_MISSING}"
  fi

  if [[ "${WARNINGS}" -gt 0 ]]; then
    echo "Warnings: ${WARNINGS}"
  fi

  return "${REQUIRED_MISSING}"
}

install_shell_integration() {
  mkdir -p "$(dirname -- "${BASHRC}")"
  touch "${BASHRC}"

  if shell_integration_is_current; then
    echo "Shell integration already present in ${BASHRC}."
  elif grep -F -- "${SOURCE_LINE}" "${BASHRC}" >/dev/null 2>&1; then
    cleanup_shell_integration || true
    printf '\n%s\n%s\n%s\n' "${CDA_BLOCK_BEGIN}" "${SOURCE_LINE}" "${CDA_BLOCK_END}" >> "${BASHRC}"
    echo "Refreshed cda shell integration in ${BASHRC}."
  else
    cleanup_shell_integration || true
    printf '\n%s\n%s\n%s\n' "${CDA_BLOCK_BEGIN}" "${SOURCE_LINE}" "${CDA_BLOCK_END}" >> "${BASHRC}"
    echo "Added cda source line to ${BASHRC}."
  fi
}

install_config_file() {
  mkdir -p "$(dirname -- "${ALIASES_FILE}")"
  touch "${ALIASES_FILE}"
  chmod 600 "${ALIASES_FILE}" 2>/dev/null || true
}

perform_uninstall() {
  if [[ ! -f "${BASHRC}" ]]; then
    echo "${BASHRC} does not exist; nothing to remove."
    return 0
  fi

  if cleanup_shell_integration; then
    echo "Removed cda shell integration from ${BASHRC}."
  else
    echo "cda shell integration was not present in ${BASHRC}; nothing to remove."
  fi
}

if [[ "${UNINSTALL}" -eq 1 ]]; then
  perform_uninstall
  exit 0
fi

if [[ "${CHECK_ONLY}" -eq 1 ]]; then
  run_dependency_report
  exit $?
fi

install_config_file
install_shell_integration

echo
if run_dependency_report; then
  echo
  echo "Install complete."
  echo "Open a new shell, or run:"
  echo "  source ${BASHRC}"
  echo "Then test:"
  echo "  cda -l"
else
  echo
  echo "Install finished, but checks still found missing requirements." >&2
  exit 1
fi
