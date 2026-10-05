#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 || ($# -eq 2 && $2 != --update) ]]; then
  printf 'Usage: %s SOURCE_DIR [--update]\n' "$0" >&2
  exit 2
fi

reject() {
  printf 'REJECT: %s\n' "$*" >&2
  exit 1
}

source_dir=$(cd -- "$1" && pwd -P)
runtime=$(pwd -P)
case "$runtime" in
"$source_dir" | "$source_dir"/*) reject 'APM lockはsourceの外の隔離runtimeで生成してください' ;;
esac
[[ -f apm.yml ]] || reject '候補のapm.ymlがありません'

expected=$(APM_SOURCE_DIR="$source_dir" nix eval --impure --raw --no-write-lock-file --expr '
  let
    flake = builtins.getFlake ("git+file://" + builtins.getEnv "APM_SOURCE_DIR" + "?dir=private_dot_config/nix-devshell");
    packages = (builtins.getAttr builtins.currentSystem flake.devShells).default.nativeBuildInputs;
    apms = builtins.filter (p: (p.pname or "") == "apm") packages;
  in if builtins.length apms == 1 then (builtins.head apms).version
     else throw "APM package is missing or ambiguous"
') || reject 'Nix snapshotのAPM版を確認できません'
[[ $expected =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || reject "Nix snapshotのAPM版が不明です: $expected"

actual=$(apm --version) || reject 'APM CLIの版を確認できません'
[[ "$actual" == "Agent Package Manager (APM) CLI version $expected" ]] ||
  reject "APM CLIの版が不一致です: 期待=$expected 実際=$actual"

install_args=()
if [[ $# -eq 2 ]]; then
  install_args+=(--update)
fi
apm install "${install_args[@]}" --target claude,codex --https

lock_version=$(awk '/^apm_version:/ { sub(/^apm_version:[[:space:]]*/, ""); print }' apm.lock.yaml) ||
  reject '生成lockのAPM版を確認できません'
case "$lock_version" in
"$expected" | "'$expected'" | "\"$expected\"") ;;
*) reject "生成lockのAPM版が不一致または不明です: 期待=$expected 実際=$lock_version" ;;
esac
printf 'PASS: 候補lockのAPM版は%sと一致しました（%s）\n' "$expected" "$runtime"
