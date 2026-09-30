#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:?MATTPOCOCK_GATE_COMMAND_LOG is required}
printf 'bats %s\n' "$*" >>"$command_log"
if [[ $# -eq 1 && "$1" == "$MATTPOCOCK_GATE_SOURCE_DIR/tests" ]]; then
  [[ "$PWD" == "$MATTPOCOCK_GATE_SOURCE_DIR" ]]
fi
