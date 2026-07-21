#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-spotlight.XXXXXX")"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

home="$WORK_ROOT/home"
vault="$home/Library/CloudStorage/GoogleDrive-test@example.invalid/My Drive/Obsidian/u1memo"
mkdir -p "$vault/.git" "$vault/.obsidian" "$vault/Daily/attachments"
printf 'preserve\n' > "$vault/.obsidian/.metadata_never_index"

HOME="$home" "$ROOT/install.sh" spotlight > "$WORK_ROOT/first.out"

[[ -f "$vault/.git/.metadata_never_index" ]] || fail ".git の除外マーカーが作成されていません"
[[ -f "$vault/.obsidian/.metadata_never_index" ]] || fail ".obsidian の除外マーカーがありません"
[[ -f "$vault/Daily/attachments/.metadata_never_index" ]] || fail "attachments の除外マーカーが作成されていません"
[[ "$(cat "$vault/.obsidian/.metadata_never_index")" == "preserve" ]] || fail "既存マーカーが上書きされました"

HOME="$home" "$ROOT/install.sh" spotlight > "$WORK_ROOT/second.out"
[[ "$(grep -Fc '済み:' "$WORK_ROOT/second.out")" == "3" ]] || fail "2回目の実行が冪等ではありません"

printf 'spotlight tests passed\n'
