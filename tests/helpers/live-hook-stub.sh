#!/usr/bin/env bash
# 実機検証用のダミー。gcloud / gcloud-inspect の名前で呼ばれ、引数を1語ずつ [..] で $STUB_LOG に記録するだけで何もしない。
{
  printf '%s' "${0##*/}"
  printf ' [%s]' "$@"
  printf '\n'
} >>"${STUB_LOG:?}"
