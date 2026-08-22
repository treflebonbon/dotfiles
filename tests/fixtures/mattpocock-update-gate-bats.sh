#!/usr/bin/env bash
set -euo pipefail

command_log=${MATTPOCOCK_GATE_COMMAND_LOG:?MATTPOCOCK_GATE_COMMAND_LOG is required}
printf 'bats %s\n' "$*" >>"$command_log"
