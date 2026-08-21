#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:-$HOME/chezmoi-command.log}
mkdir -p -- "$(dirname -- "$command_log")"
printf 'chezmoi %s\n' "$*" >>"$command_log"
