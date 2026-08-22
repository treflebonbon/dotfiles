#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:-$HOME/chezmoi-command.log}
mkdir -p "$(dirname "$command_log")"
printf 'chezmoi %s\n' "$*" >>"$command_log"

if [[ " $* " == *" --dry-run "* ]]; then
  if [[ -n "${MATT_GATE_MUTATE_CHEZMOI_FILE:-}" ]]; then
    printf 'changed\n' >"$HOME/.mattpocock-gate-sentinel"
  fi
  if [[ -n "${MATT_GATE_MUTATE_CHEZMOI_SYMLINK:-}" ]]; then
    ln -sfn "$HOME/.mattpocock-gate-other" "$HOME/.mattpocock-gate-link"
  fi
fi
