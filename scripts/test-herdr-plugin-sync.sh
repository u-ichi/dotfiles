#!/usr/bin/env bash
# Herdr plugin 同期の standalone 検証

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN="$TMP_DIR/bin"
FAKE_HERDR_STATE="$TMP_DIR/plugins.json"
FAKE_HERDR_LOG="$TMP_DIR/herdr.log"
FAKE_HERDR_INSTALL_STATE="$TMP_DIR/installed.json"
mkdir -p "$FAKE_BIN"
: > "$FAKE_HERDR_LOG"

cat > "$FAKE_BIN/herdr" <<'FAKE_HERDR'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >> "$FAKE_HERDR_LOG"

if [[ "$*" == "plugin list --plugin persiyanov.reviewr --json" ]]; then
  cat "$FAKE_HERDR_STATE"
  exit 0
fi

if [[ "$*" == plugin\ install\ * ]]; then
  printf 'CDPATH=%s\n' "${CDPATH-}" >> "$FAKE_HERDR_LOG"
  if [ "${FAKE_HERDR_INSTALL_STATUS:-0}" -ne 0 ]; then
    echo "fake install failed" >&2
    exit "$FAKE_HERDR_INSTALL_STATUS"
  fi
  cp "$FAKE_HERDR_INSTALL_STATE" "$FAKE_HERDR_STATE"
  exit 0
fi

echo "unexpected herdr command: $*" >&2
exit 2
FAKE_HERDR
chmod +x "$FAKE_BIN/herdr"

write_empty_state() {
  printf '%s\n' '{"id":"cli:plugin","result":{"plugins":[],"type":"plugin_list"}}' > "$FAKE_HERDR_STATE"
}

write_matching_state() {
  printf '%s\n' '{"id":"cli:plugin","result":{"plugins":[{"plugin_id":"persiyanov.reviewr","version":"0.19.0","source":{"kind":"github","owner":"persiyanov","repo":"herdr-reviewr","requested_ref":"659df1d8d41c0f1092c16e77e776fc6e4637677e","resolved_commit":"659df1d8d41c0f1092c16e77e776fc6e4637677e"}}],"type":"plugin_list"}}' > "$FAKE_HERDR_INSTALL_STATE"
}

write_version_mismatch_state() {
  printf '%s\n' '{"id":"cli:plugin","result":{"plugins":[{"plugin_id":"persiyanov.reviewr","version":"0.18.1","source":{"kind":"github","owner":"persiyanov","repo":"herdr-reviewr","requested_ref":"659df1d8d41c0f1092c16e77e776fc6e4637677e","resolved_commit":"659df1d8d41c0f1092c16e77e776fc6e4637677e"}}],"type":"plugin_list"}}' > "$FAKE_HERDR_STATE"
}

assert_contains() {
  local text="$1"
  local expected="$2"
  printf '%s\n' "$text" | grep -Fq -- "$expected"
}

run_capture() {
  LAST_OUTPUT=""
  if LAST_OUTPUT="$("$@" 2>&1)"; then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

if [ ! -f "$REPO_ROOT/lib/herdr.sh" ]; then
  echo "FAIL: production の lib/herdr.sh がありません" >&2
  exit 1
fi

export FAKE_HERDR_STATE FAKE_HERDR_LOG FAKE_HERDR_INSTALL_STATE
export HERDR_PLUGIN_FILE="$REPO_ROOT/Herdrfile"
export PATH="$FAKE_BIN:$PATH"
export CDPATH="$TMP_DIR/non-empty-cdpath"

# Production module を直接読み込み、テスト用の fake herdr だけを外部境界に置く。
# shellcheck source=/dev/null
source "$REPO_ROOT/lib/herdr.sh"

FRESH_HOME="$TMP_DIR/fresh-home"
mkdir -p "$FRESH_HOME/.local/bin"
cat > "$FRESH_HOME/.local/bin/herdr" <<'FRESH_HERDR'
#!/usr/bin/env bash
printf '%s\n' "herdr 0.7.4"
FRESH_HERDR
chmod +x "$FRESH_HOME/.local/bin/herdr"
fresh_path_output="$(
  HOME="$FRESH_HOME"
  PATH="/usr/bin:/bin"
  ensure_herdr
  command -v herdr
)"
assert_contains "$fresh_path_output" "$FRESH_HOME/.local/bin/herdr"
echo "PASS: 公式配置先を新規導入直後の PATH へ反映"

write_matching_state

write_empty_state
: > "$FAKE_HERDR_LOG"
run_capture sync_herdr_plugins
[ "$LAST_STATUS" -eq 0 ]
assert_contains "$LAST_OUTPUT" "導入:     persiyanov.reviewr"
assert_contains "$(cat "$FAKE_HERDR_LOG")" "plugin install persiyanov/herdr-reviewr --ref 659df1d8d41c0f1092c16e77e776fc6e4637677e --yes"
if ! grep -Fqx "CDPATH=" "$FAKE_HERDR_LOG"; then
  echo "FAIL: plugin install へ非空 CDPATH が渡されました" >&2
  exit 1
fi
if [ "${CDPATH-}" != "$TMP_DIR/non-empty-cdpath" ]; then
  echo "FAIL: plugin install が親shellの CDPATH を変更しました" >&2
  exit 1
fi
echo "PASS: 未導入時だけ固定 ref で install"

write_matching_state
: > "$FAKE_HERDR_LOG"
run_capture sync_herdr_plugins
[ "$LAST_STATUS" -eq 0 ]
if grep -Fq "plugin install" "$FAKE_HERDR_LOG"; then
  echo "FAIL: 一致時に install しました" >&2
  exit 1
fi
assert_contains "$LAST_OUTPUT" "済み:     persiyanov.reviewr"
echo "PASS: 導入済みかつ版・commit一致時は変更なし"

write_version_mismatch_state
: > "$FAKE_HERDR_LOG"
run_capture sync_herdr_plugins
[ "$LAST_STATUS" -ne 0 ]
assert_contains "$LAST_OUTPUT" "差異:     persiyanov.reviewr"
assert_contains "$LAST_OUTPUT" "自動削除・再導入はしません"
if grep -Eq "plugin (install|uninstall)" "$FAKE_HERDR_LOG"; then
  echo "FAIL: 版不一致時に plugin 状態を変更しました" >&2
  exit 1
fi
echo "PASS: 版不一致は表示だけで自動変更なし"

write_empty_state
: > "$FAKE_HERDR_LOG"
FAKE_HERDR_INSTALL_STATUS=1
export FAKE_HERDR_INSTALL_STATUS
run_capture sync_herdr_plugins
unset FAKE_HERDR_INSTALL_STATUS
[ "$LAST_STATUS" -ne 0 ]
assert_contains "$LAST_OUTPUT" "インストール失敗"
if grep -Fq "plugin uninstall" "$FAKE_HERDR_LOG"; then
  echo "FAIL: install 失敗時に uninstall しました" >&2
  exit 1
fi
echo "PASS: install 失敗を失敗として返し自動削除なし"

write_version_mismatch_state
run_capture sync_herdr_plugins_for_all
[ "$LAST_STATUS" -eq 0 ]
assert_contains "$LAST_OUTPUT" "通常導入の残りは継続"
echo "PASS: 通常導入経路は同期失敗でも継続"

grep -Fq "if [ \"\$MODE\" = \"herdr\" ]" "$REPO_ROOT/install.sh"
grep -Fq 'sync_herdr_plugins_for_all' "$REPO_ROOT/install.sh"
grep -Fq 'persiyanov.reviewr|persiyanov/herdr-reviewr|0.19.0|659df1d8d41c0f1092c16e77e776fc6e4637677e' "$REPO_ROOT/Herdrfile"
echo "PASS: Herdr 専用 mode / 通常導入 call site / 固定一覧を確認"

echo "All Herdr plugin sync tests passed."
