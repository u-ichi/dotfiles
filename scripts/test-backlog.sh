#!/usr/bin/env bash
# Backlog.md managed patch 配置の standalone 回帰テスト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-backlog.XXXXXX")"
trap 'rm -rf "$WORK_ROOT"' EXIT

if [ ! -x /usr/bin/shlock ]; then
  echo "スキップ: /usr/bin/shlock がありません"
  exit 0
fi

REAL_GIT="$(command -v git)"
FAKE_BIN="$WORK_ROOT/bin"
SOURCE_DIR="$WORK_ROOT/backlog-source"
PATCH_DIR="$WORK_ROOT/managed"
HOME_DIR="$WORK_ROOT/home"
STATE_DIR="$WORK_ROOT/state"
BIN_DIR="$WORK_ROOT/live-bin"
FAKE_GIT_LOG="$WORK_ROOT/git.log"
FAKE_BUN_LOG="$WORK_ROOT/bun.log"
mkdir -p "$FAKE_BIN" "$SOURCE_DIR/src" "$PATCH_DIR" "$HOME_DIR" "$STATE_DIR" "$BIN_DIR"
: > "$FAKE_GIT_LOG"
: > "$FAKE_BUN_LOG"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

assert_contains() {
  local text="$1"
  local expected="$2"
  printf '%s\n' "$text" | grep -Fq -- "$expected" || fail "出力に '$expected' がありません"
}

write_patch() {
  local value="$1"

  cat > "$PATCH_DIR/backlog.patch" <<EOF
diff --git a/src/version.txt b/src/version.txt
--- a/src/version.txt
+++ b/src/version.txt
@@ -1 +1 @@
-base
+$value
EOF
}

cat > "$FAKE_BIN/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_GIT_LOG"
if [ "${1:-}" = "-C" ] && [ "${3:-}" = "fetch" ] && [ "${4:-}" = "origin" ] && [ "${5:-}" = "main" ]; then
  exit 0
fi
exec "$REAL_GIT" "$@"
EOF

cat > "$FAKE_BIN/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_BUN_LOG"

if [ "${1:-}" = "-e" ]; then
  if grep -Fq '"patches"' "${3:?manifest path is required}"; then
    sed -nE 's/.*"base_commit"[[:space:]]*:[[:space:]]*"([0-9a-fA-F]{40})".*/\1/p' "${3:?manifest path is required}"
    sed -nE 's/.*"patches"[[:space:]]*:[[:space:]]*\["([^"]+)"\].*/\1/p' "${3:?manifest path is required}"
    exit 0
  fi
  awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "${3:?package path is required}"
  exit 0
fi

if [ "${1:-}" = "install" ]; then
  mkdir -p node_modules/bun/bin
  printf 'installed\n' > node_modules/bun/bin/bun.exe
  exit 0
fi

if [ "${1:-}" = "run" ] && [ "${2:-}" = "build" ]; then
  if [ "${FAKE_BUN_FAIL_BUILD:-0}" -eq 1 ]; then
    echo "fake build failed" >&2
    exit 1
  fi
  mkdir -p dist
  version="$(cat src/version.txt)"
  cat > dist/backlog <<SCRIPT
#!/usr/bin/env bash
if [ "\${1:-}" = "--version" ]; then
  printf 'fake-backlog %s\\n' '$version'
fi
SCRIPT
  chmod 755 dist/backlog
  exit 0
fi

echo "unexpected fake bun command: $*" >&2
exit 2
EOF

cat > "$FAKE_BIN/npm" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "ls" ] && [ "${2:-}" = "-g" ]; then
  exit 1
fi
exit 2
EOF
chmod 755 "$FAKE_BIN/git" "$FAKE_BIN/bun" "$FAKE_BIN/npm"

export FAKE_GIT_LOG FAKE_BUN_LOG REAL_GIT

printf '{"version":"1.0.0"}\n' > "$SOURCE_DIR/package.json"
printf 'lock\n' > "$SOURCE_DIR/bun.lock"
printf 'base\n' > "$SOURCE_DIR/src/version.txt"
"$REAL_GIT" -C "$SOURCE_DIR" init -q
"$REAL_GIT" -C "$SOURCE_DIR" config user.name test
"$REAL_GIT" -C "$SOURCE_DIR" config user.email test@example.invalid
"$REAL_GIT" -C "$SOURCE_DIR" add package.json bun.lock src/version.txt
"$REAL_GIT" -C "$SOURCE_DIR" commit -qm base
BASE_COMMIT="$($REAL_GIT -C "$SOURCE_DIR" rev-parse HEAD)"
"$REAL_GIT" -C "$SOURCE_DIR" remote add origin https://github.com/MrLesk/Backlog.md
"$REAL_GIT" -C "$SOURCE_DIR" update-ref refs/remotes/origin/main "$BASE_COMMIT"
printf 'local source change\n' > "$SOURCE_DIR/local-uncommitted.txt"

write_patch patched-v1
printf '{"base_commit":"%s","patches":["backlog.patch"]}\n' "$BASE_COMMIT" > "$PATCH_DIR/manifest.json"

# 実環境の既存 backlog binary や npm を見せず、配置先の解決だけを fixture で検査する。
export PATH="$FAKE_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
# shellcheck source=/dev/null
source "$ROOT/lib/backlog.sh"

run_backlog() {
  HOME="$HOME_DIR" \
    XDG_STATE_HOME="$STATE_DIR" \
    BACKLOG_MD_SRC_DIR="$SOURCE_DIR" \
    BACKLOG_MD_BIN_DIR="$BIN_DIR" \
    BACKLOG_MD_PATCH_DIR="$PATCH_DIR" \
    ensure_backlog_head
}

run_capture() {
  LAST_OUTPUT=""
  if LAST_OUTPUT="$(run_backlog 2>&1)"; then
    LAST_STATUS=0
  else
    LAST_STATUS=$?
  fi
}

run_capture
[ "$LAST_STATUS" -eq 0 ] || fail "managed patch build failed: $LAST_OUTPUT"
assert_contains "$LAST_OUTPUT" "更新:     Backlog.md ($BASE_COMMIT)"
[ "$("$BIN_DIR/backlog" --version)" = "fake-backlog patched-v1" ] || fail "patch v1 が binary に反映されていません"
MARKER="$STATE_DIR/dotfiles/backlog/installed-commit"
[ -f "$MARKER" ] || fail "managed marker がありません"
assert_contains "$(cat "$MARKER")" "manifest_digest="
assert_contains "$(cat "$MARKER")" "patches_digest="
if grep -Fq 'reset --hard' "$FAKE_GIT_LOG"; then
  fail "managed patch build が source clone を reset しました"
fi
[ -f "$SOURCE_DIR/local-uncommitted.txt" ] || fail "source clone の未 commit file が消えました"
[ "$("$REAL_GIT" -C "$SOURCE_DIR" remote get-url origin)" = "https://github.com/MrLesk/Backlog.md" ] || fail "source clone の origin が変更されました"
pass "managed patch は一時 build に適用され、source clone を保持"

old_marker="$(cat "$MARKER")"
write_patch patched-v2
run_capture
[ "$LAST_STATUS" -eq 0 ] || fail "patch digest change rebuild failed: $LAST_OUTPUT"
[ "$("$BIN_DIR/backlog" --version)" = "fake-backlog patched-v2" ] || fail "patch v2 が binary に反映されていません"
new_marker="$(cat "$MARKER")"
[ "$old_marker" != "$new_marker" ] || fail "patch content change で marker が更新されませんでした"
pass "manifest と patch 内容の変更で marker と binary を更新"

cp "$BIN_DIR/backlog" "$WORK_ROOT/old-backlog"
old_marker="$new_marker"
write_patch patched-v3
export FAKE_BUN_FAIL_BUILD=1
run_capture
unset FAKE_BUN_FAIL_BUILD
[ "$LAST_STATUS" -eq 0 ] || fail "既存 binary がある build failure が失敗扱いになりました"
assert_contains "$LAST_OUTPUT" "ビルドに失敗したため、既存バイナリを使用します"
cmp -s "$WORK_ROOT/old-backlog" "$BIN_DIR/backlog" || fail "build failure で既存 binary が置き換わりました"
[ "$(cat "$MARKER")" = "$old_marker" ] || fail "build failure で成功 marker が更新されました"
pass "managed build failure は既存 binary と marker を保持"

cp "$BIN_DIR/backlog" "$WORK_ROOT/old-backlog"
rm -f "$PATCH_DIR/backlog.patch"
run_capture
[ "$LAST_STATUS" -eq 0 ] || fail "patch 不在時に既存 binary を保持できませんでした"
assert_contains "$LAST_OUTPUT" "managed patch が見つかりません"
cmp -s "$WORK_ROOT/old-backlog" "$BIN_DIR/backlog" || fail "patch 不在時に公式版を配置しました"
[ "$(cat "$MARKER")" = "$old_marker" ] || fail "patch 不在時に marker が更新されました"
pass "managed patch 不在時に patch を省略せず既存 binary を保持"

echo "Backlog.md managed patch tests passed."
