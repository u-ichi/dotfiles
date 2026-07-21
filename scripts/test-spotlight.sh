#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-spotlight.XXXXXX")"
SOURCE_SCRIPT="$ROOT/scripts/disable-spotlight-indexing.sh"
LIVE_BIN_NAME="disable-spotlight-indexing"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# 配布元（管理元）が dotfiles にあること
[[ -f "$SOURCE_SCRIPT" ]] || fail "管理元がありません: scripts/disable-spotlight-indexing.sh"
[[ -x "$SOURCE_SCRIPT" ]] || fail "管理元が executable ではありません: scripts/disable-spotlight-indexing.sh"

# --- call site 独立検査（install.sh path を引数に取り、故障注入でも再利用） ---
# spotlight mode ブロック: MODE=spotlight 節から次の単独 fi まで
assert_spotlight_mode_call_site() {
  local install_sh="$1"
  local block
  block="$(
    awk '
      /MODE.*=.*"spotlight"/ { in_block=1 }
      in_block { print }
      in_block && /^fi$/ { exit }
    ' "$install_sh"
  )"
  [[ -n "$block" ]] || fail "spotlight mode ブロックを抽出できません: $install_sh"
  printf '%s\n' "$block" | grep -Fq 'install_disable_spotlight_indexing' ||
    fail "spotlight mode ブロック内に install_disable_spotlight_indexing がありません"
}

# all フローの Spotlight 節: "# === Spotlight 除外 ===" から次の "# ===" まで
assert_all_spotlight_section_call_site() {
  local install_sh="$1"
  local block
  block="$(
    awk '
      /^# === Spotlight 除外 ===/ { in_block=1; print; next }
      in_block && /^# === / { exit }
      in_block { print }
    ' "$install_sh"
  )"
  [[ -n "$block" ]] || fail "all フロー Spotlight 節を抽出できません: $install_sh"
  printf '%s\n' "$block" | grep -Fq 'install_disable_spotlight_indexing' ||
    fail "all フロー Spotlight 節内に install_disable_spotlight_indexing がありません"
}

assert_spotlight_mode_call_site "$ROOT/install.sh"
assert_all_spotlight_section_call_site "$ROOT/install.sh"

# 故障注入（実装は本関数のみ）:
# 片方の call site を消した install.sh コピーに対し、対象 assert が非ゼロになることを実測する。
# fail() がプロセスを終了するため、対象 assert だけ subshell で実行して exit code を取る。
fault_inject_call_site() {
  local which="$1" # mode | all
  local mutated="$WORK_ROOT/install.$which.fault.sh"
  local out="$WORK_ROOT/fault.$which.out"
  local ec

  if [[ "$which" == "mode" ]]; then
    # spotlight mode ブロック内の呼び出し行だけ削除（all 節は残す）
    awk '
      /MODE.*=.*"spotlight"/ { in_mode=1 }
      in_mode && /^fi$/ { in_mode=0 }
      in_mode && /install_disable_spotlight_indexing/ { next }
      { print }
    ' "$ROOT/install.sh" > "$mutated"
  else
    # all フロー Spotlight 節内の呼び出し行だけ削除（mode ブロックは残す）
    awk '
      /^# === Spotlight 除外 ===/ { in_all=1; print; next }
      in_all && /^# === / { in_all=0 }
      in_all && /install_disable_spotlight_indexing/ { next }
      { print }
    ' "$ROOT/install.sh" > "$mutated"
  fi

  # 故障後も「もう一方」の call site は残っていること（独立検査の意味）
  if [[ "$which" == "mode" ]]; then
    assert_all_spotlight_section_call_site "$mutated"
  else
    assert_spotlight_mode_call_site "$mutated"
  fi

  set +e
  (
    if [[ "$which" == "mode" ]]; then
      assert_spotlight_mode_call_site "$mutated"
    else
      assert_all_spotlight_section_call_site "$mutated"
    fi
  ) >"$out" 2>&1
  ec=$?
  set -e

  printf 'fault-inject %s exit_code=%s\n' "$which" "$ec" >&2
  if [[ "$ec" -eq 0 ]]; then
    cat "$out" >&2 || true
    fail "故障注入($which)で call site 欠落を検知できませんでした"
  fi
}

fault_inject_call_site mode
fault_inject_call_site all

home="$WORK_ROOT/home"
vault="$home/Library/CloudStorage/GoogleDrive-test@example.invalid/My Drive/Obsidian/u1memo"
mkdir -p "$vault/.git" "$vault/.obsidian" "$vault/Daily/attachments"
printf 'preserve\n' > "$vault/.obsidian/.metadata_never_index"

HOME="$home" "$ROOT/install.sh" spotlight > "$WORK_ROOT/first.out"

[[ -f "$vault/.git/.metadata_never_index" ]] || fail ".git の除外マーカーが作成されていません"
[[ -f "$vault/.obsidian/.metadata_never_index" ]] || fail ".obsidian の除外マーカーがありません"
[[ -f "$vault/Daily/attachments/.metadata_never_index" ]] || fail "attachments の除外マーカーが作成されていません"
[[ "$(cat "$vault/.obsidian/.metadata_never_index")" == "preserve" ]] || fail "既存マーカーが上書きされました"

# live へ管理元がコピーされ、cmp 一致かつ executable
live="$home/.local/bin/$LIVE_BIN_NAME"
[[ -f "$live" ]] || fail "live が未コピーです: \$HOME/.local/bin/$LIVE_BIN_NAME"
[[ -x "$live" ]] || fail "live が executable ではありません: $live"
cmp -s "$SOURCE_SCRIPT" "$live" || fail "live が管理元と一致しません (cmp)"
# install が apply を暗黙実行していないこと
if grep -Eiq 'mdutil -i off|Spotlight indexing disabled' "$WORK_ROOT/first.out"; then
  fail "install spotlight が apply を暗黙実行した形跡があります"
fi

HOME="$home" "$ROOT/install.sh" spotlight > "$WORK_ROOT/second.out"
# Obsidian 除外 3 + live 配布済み 1 = 済みが少なくとも 3（live 済みメッセージ含む）
[[ "$(grep -Fc '済み:' "$WORK_ROOT/second.out")" -ge 3 ]] || fail "2回目の実行が冪等ではありません"
cmp -s "$SOURCE_SCRIPT" "$live" || fail "2回目後に live が管理元と不一致"

printf 'spotlight tests passed\n'
