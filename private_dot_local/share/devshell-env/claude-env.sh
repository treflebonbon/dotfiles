# shellcheck shell=bash
# Sourced by Claude's Bash tool (bash or zsh). Baselines stay in unexported
# shell variables; inherited values are never written to an environment file.
__devshell_begin() {
  [ "${__devshell_generation-}" != "$1" ] || return 1
  local __devshell_local_names=${__devshell_names-} __devshell_local_name
  local __devshell_local_current __devshell_local_after __devshell_local_present
  while [ -n "$__devshell_local_names" ]; do
    __devshell_local_name=${__devshell_local_names%% *}
    __devshell_local_names=${__devshell_local_names#* }
    eval "__devshell_local_current=\${$__devshell_local_name-}"
    eval "__devshell_local_present=\${$__devshell_local_name+x}"
    eval "__devshell_local_after=\${__devshell_after_$__devshell_local_name}"
    if [ "$__devshell_local_present" = x ] && [ "$__devshell_local_current" = "$__devshell_local_after" ]; then
      eval "__devshell_local_present=\${__devshell_present_$__devshell_local_name}"
      if [ "$__devshell_local_present" = x ]; then
        eval "$__devshell_local_name=\${__devshell_before_$__devshell_local_name}"
        export "${__devshell_local_name?}"
      else
        unset "$__devshell_local_name"
      fi
    fi
    unset "__devshell_before_$__devshell_local_name" "__devshell_after_$__devshell_local_name" "__devshell_present_$__devshell_local_name"
  done
  __devshell_local_names=${__devshell_paths-}
  while [ -n "$__devshell_local_names" ]; do
    __devshell_local_current=${__devshell_local_names%%:*}
    __devshell_local_names=${__devshell_local_names#*:}
    PATH=":$PATH:"
    PATH=${PATH//":$__devshell_local_current:"/:}
    PATH=${PATH#:}
    PATH=${PATH%:}
  done
  export PATH
  __devshell_names=
  __devshell_paths=
  __devshell_generation=$1
}

__devshell_set() {
  local __devshell_local_name=$1 __devshell_local_value=$2
  __devshell_names="$__devshell_names$__devshell_local_name "
  # Names are validated identifiers. Values expand as assignments, never as code.
  # shellcheck disable=SC2034
  eval "__devshell_present_$__devshell_local_name=\${$__devshell_local_name+x}"
  # shellcheck disable=SC2034
  eval "__devshell_before_$__devshell_local_name=\${$__devshell_local_name-}"
  eval "__devshell_after_$__devshell_local_name=\$__devshell_local_value"
  eval "$__devshell_local_name=\$__devshell_local_value"
  export "${__devshell_local_name?}"
}

__devshell_path() {
  local __devshell_local_rest=$1 __devshell_local_part __devshell_local_prefix=
  while [ -n "$__devshell_local_rest" ]; do
    __devshell_local_part=${__devshell_local_rest%%:*}
    if [ -n "$__devshell_local_part" ] && [[ :$PATH: != *":$__devshell_local_part:"* ]]; then
      __devshell_paths="$__devshell_paths$__devshell_local_part:"
      __devshell_local_prefix="$__devshell_local_prefix$__devshell_local_part:"
    fi
    [ "$__devshell_local_rest" != "$__devshell_local_part" ] || break
    __devshell_local_rest=${__devshell_local_rest#*:}
  done
  export PATH="$__devshell_local_prefix$PATH"
}
