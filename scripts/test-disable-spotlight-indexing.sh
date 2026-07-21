#!/bin/bash
# disable-spotlight-indexing.sh の回帰テスト（live mdutil / process は触らない）

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/disable-spotlight-indexing.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-disable-spotlight.XXXXXX")"
MOCK_BIN="$TEST_ROOT/mock-bin"
STATE="$TEST_ROOT/state"
PASS=0
FAIL=0

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
  return 1
}

pass() {
  echo "PASS: $*"
  PASS=$((PASS + 1))
}

[[ -x "$SCRIPT" ]] || { echo "script missing or not executable: $SCRIPT" >&2; exit 1; }

mkdir -p "$MOCK_BIN" "$STATE"

# mock uname
cat > "$MOCK_BIN/uname" <<'EOF'
#!/bin/bash
if [[ -f "$SPOTLIGHT_TEST_STATE/uname-non-darwin" ]]; then
  echo "Linux"
  exit 0
fi
echo "Darwin"
EOF

# mock mdutil: 呼び出し記録 + 設定可能な状態
cat > "$MOCK_BIN/mdutil" <<'EOF'
#!/bin/bash
set -euo pipefail
STATE="${SPOTLIGHT_TEST_STATE:?}"
LOG="$STATE/mdutil.log"
printf '%s\n' "$*" >> "$LOG"

# 状態ファイル: volume ごとの enabled/disabled
# キーは volume path を tr / _ したもの
status_file_for() {
  local vol="$1"
  local key
  key="$(printf '%s' "$vol" | tr '/' '_')"
  if [[ -z "$key" || "$key" == "_" ]]; then
    key="_root"
  fi
  echo "$STATE/status$key"
}

get_status() {
  local vol="$1" f
  f="$(status_file_for "$vol")"
  if [[ -f "$f" ]]; then
    cat "$f"
  else
    echo "enabled"
  fi
}

if [[ "${1:-}" == "-s" ]]; then
  vol="${2:-}"
  st="$(get_status "$vol")"
  echo "$vol:"
  if [[ "$st" == "disabled" ]]; then
    echo "Indexing disabled."
  elif [[ "$st" == "and-searching-disabled" ]]; then
    # /usr/bin/mdutil 一次証拠の正規成功文言
    echo "Indexing and searching disabled."
  elif [[ "$st" == "never-index-file-disabled" ]]; then
    # marker 適用後の正規成功文言（mdutil バイナリ strings）
    echo "Indexing and searching disabled because of .metadata_never_index file at root of volume."
  elif [[ "$st" == "server-disabled" ]]; then
    # 偽陽性: 索引フラグ成功とみなさない
    echo "Spotlight server is disabled."
  elif [[ "$st" == "enabled" ]]; then
    echo "Indexing enabled."
  elif [[ "$st" == "garbled" ]]; then
    echo "unknown status string"
  else
    echo "Indexing enabled."
  fi
  exit 0
fi

if [[ "${1:-}" == "-i" && "${2:-}" == "off" ]]; then
  vol="${3:-}"
  if [[ -f "$STATE/fail-off-root" && "$vol" == "/" ]]; then
    echo "Error: could not disable indexing on /" >&2
    exit 1
  fi
  if [[ -f "$STATE/fail-off-data" && "$vol" == "/System/Volumes/Data" ]]; then
    echo "Error: could not disable indexing on Data" >&2
    exit 1
  fi
  if [[ -f "$STATE/apply-no-effect" ]]; then
    # -i off は成功するが状態は enabled のまま
    printf 'enabled\n' > "$(status_file_for "$vol")"
    exit 0
  fi
  if [[ -f "$STATE/apply-partial-only-root" ]]; then
    if [[ "$vol" == "/" ]]; then
      printf 'disabled\n' > "$(status_file_for "$vol")"
    else
      printf 'enabled\n' > "$(status_file_for "$vol")"
    fi
    exit 0
  fi
  if [[ -f "$STATE/apply-server-disabled-phrase" ]]; then
    # live と同じ read-back 文言で成功状態を表現する
    printf 'server-disabled\n' > "$(status_file_for "$vol")"
    exit 0
  fi
  printf 'disabled\n' > "$(status_file_for "$vol")"
  exit 0
fi

echo "mock mdutil: unexpected args: $*" >&2
exit 2
EOF
chmod +x "$MOCK_BIN"/*

# live Data は触らない。marker は TEST_ROOT 配下へ注入する
MARKER_PARENT="$TEST_ROOT/fake-data-root"
MARKER_PATH="$MARKER_PARENT/.metadata_never_index"

run_script() {
  SPOTLIGHT_MDUTIL="$MOCK_BIN/mdutil" \
  SPOTLIGHT_UNAME="$MOCK_BIN/uname" \
  SPOTLIGHT_TEST_STATE="$STATE" \
  SPOTLIGHT_EUID="${SPOTLIGHT_EUID:-0}" \
  SPOTLIGHT_MARKER="$MARKER_PATH" \
    "$SCRIPT" "$@"
}

reset_state() {
  rm -rf "$STATE" "$MARKER_PARENT"
  mkdir -p "$STATE" "$MARKER_PARENT"
  # 既定: 両方 enabled、marker 不在
  printf 'enabled\n' > "$STATE/status_root"
  printf 'enabled\n' > "$STATE/status_System_Volumes_Data"
}

place_marker() {
  mkdir -p "$MARKER_PARENT"
  : > "$MARKER_PATH"
}

# --- tests ---

# 1. 非 Darwin は失敗
reset_state
touch "$STATE/uname-non-darwin"
if run_script apply >/dev/null 2>"$TEST_ROOT/non-darwin.err"; then
  fail "non-darwin should fail"
else
  if grep -Fq "macOS 専用" "$TEST_ROOT/non-darwin.err"; then
    pass "non-darwin-rejected"
  else
    fail "non-darwin message missing"
  fi
fi
rm -f "$STATE/uname-non-darwin"

# 2. 非 root は apply を拒否し mdutil -i を呼ばない
reset_state
SPOTLIGHT_EUID=501
if SPOTLIGHT_EUID=501 run_script apply >/dev/null 2>"$TEST_ROOT/non-root.err"; then
  fail "non-root apply should fail"
else
  grep -Fq "管理者権限" "$TEST_ROOT/non-root.err" || fail "non-root message missing"
  if [[ -f "$STATE/mdutil.log" ]] && grep -q -- '-i off' "$STATE/mdutil.log"; then
    fail "non-root should not call mdutil -i off"
  else
    pass "non-root-rejected-no-partial-apply"
  fi
fi
unset SPOTLIGHT_EUID || true
SPOTLIGHT_EUID=0

# 3. dry-run は mdutil -i を呼ばず、marker 作成予定と対象を表示
reset_state
out="$(run_script --dry-run apply 2>&1)" || fail "dry-run should succeed"
printf '%s\n' "$out" | grep -Fq '/System/Volumes/Data' || fail "dry-run should list Data"
printf '%s\n' "$out" | grep -Fq 'mdutil -i off' || fail "dry-run should show mdutil -i off"
printf '%s\n' "$out" | grep -Fq '.metadata_never_index' || fail "dry-run should show marker path"
[[ ! -e "$MARKER_PATH" ]] || fail "dry-run must not create marker"
if [[ -f "$STATE/mdutil.log" ]]; then
  fail "dry-run must not invoke mock mdutil"
else
  pass "dry-run-no-side-effects"
fi

# 4. 正常 apply: marker 作成 → 両方 disabled、log に両 volume
reset_state
out="$(run_script apply 2>&1)" || fail "apply should succeed on mock"
printf '%s\n' "$out" | grep -Fq 'Indexing disabled' || fail "apply output should show disabled"
[[ -e "$MARKER_PATH" ]] || fail "apply should create marker"
grep -Fq -- '-i off /' "$STATE/mdutil.log" || fail "should call -i off /"
grep -Fq -- '-i off /System/Volumes/Data' "$STATE/mdutil.log" || fail "should call -i off Data"
# RAM ボリュームは触らない（/System/Volumes/Data は正規対象）
if grep -E 'AGENT_RUNTIME|CODEX_LOG|/Volumes/AGENT|/Volumes/CODEX' "$STATE/mdutil.log"; then
  fail "must not touch RAM volumes"
else
  pass "apply-both-volumes-disabled"
fi

# 5. verify 成功（disabled + marker）
out="$(run_script verify 2>&1)" || fail "verify should pass when both disabled and marker present"
pass "verify-when-disabled"

# 6. 片方だけ fail-off → 部分成功を成功扱いにしない
reset_state
touch "$STATE/fail-off-data"
if run_script apply >/dev/null 2>"$TEST_ROOT/partial.err"; then
  fail "partial mdutil failure should fail apply"
else
  if grep -Eiq '部分|失敗' "$TEST_ROOT/partial.err"; then
    pass "partial-failure-not-success"
  else
    pass "partial-failure-exit-nonzero"
  fi
fi

# 7. -i off は成功するが read-back が enabled のまま → 失敗
reset_state
touch "$STATE/apply-no-effect"
if run_script apply >/dev/null 2>"$TEST_ROOT/no-effect.err"; then
  fail "read-back still enabled should fail"
else
  grep -Fq 'Indexing disabled' "$TEST_ROOT/no-effect.err" || true
  pass "readback-still-enabled-fails"
fi

# 8. 片方だけ disabled（partial apply-no-effect 相当）
reset_state
touch "$STATE/apply-partial-only-root"
if run_script apply >/dev/null 2>"$TEST_ROOT/half.err"; then
  fail "one volume still enabled should fail"
else
  pass "one-volume-enabled-fails"
fi

# 9. status は権限なしでも動く（EUID 非 root）
reset_state
printf 'disabled\n' > "$STATE/status_root"
printf 'disabled\n' > "$STATE/status_System_Volumes_Data"
out="$(SPOTLIGHT_EUID=501 run_script status 2>&1)" || fail "status should work without root"
printf '%s\n' "$out" | grep -c 'Indexing disabled' | grep -qx 2 || fail "status should show both"
pass "status-without-root"

# 10. verify は enabled で失敗
reset_state
if run_script verify >/dev/null 2>"$TEST_ROOT/verify-en.err"; then
  fail "verify should fail when enabled"
else
  pass "verify-fails-when-enabled"
fi

# 11. 想定外 status 文字列
reset_state
printf 'garbled\n' > "$STATE/status_root"
printf 'disabled\n' > "$STATE/status_System_Volumes_Data"
if run_script verify >/dev/null 2>"$TEST_ROOT/garbled.err"; then
  fail "garbled status should fail verify"
else
  pass "garbled-status-fails"
fi

# 12. help
run_script help >/dev/null || fail "help should exit 0"
pass "help-ok"

# 13. 偽陽性回帰: "Spotlight server is disabled." だけでは成功にしない (verify)
# mdutil バイナリ上、Indexing disabled. とは別文言。marker があっても非ゼロ必須。
# exit code は pipe/代入で潰さずファイルへ記録する。
reset_state
place_marker
printf 'server-disabled\n' > "$STATE/status_root"
printf 'server-disabled\n' > "$STATE/status_System_Volumes_Data"
set +e
run_script verify >"$TEST_ROOT/t13.out" 2>"$TEST_ROOT/t13.err"
t13_ec=$?
set -e
# pipe/command-substitution で exit を潰さない。$? を変数へ保存してから記録・判定する
printf 'RED-record test13 verify exit_code=%s\n' "$t13_ec" >&2
printf 'RED-record test13 verify exit_code=%s\n' "$t13_ec" >>"$TEST_ROOT/red-exit-codes.log"
if [[ "$t13_ec" -eq 0 ]]; then
  echo "RED-evidence: verify succeeded on server-disabled only (false positive)" >&2
  cat "$TEST_ROOT/t13.out" "$TEST_ROOT/t13.err" >&2 || true
  fail "verify must be non-zero when only 'Spotlight server is disabled.' (not Indexing disabled.)"
else
  pass "verify-rejects-spotlight-server-is-disabled-alone"
fi

# 14. 偽陽性回帰: apply read-back が server-disabled のみなら非ゼロ
reset_state
touch "$STATE/apply-server-disabled-phrase"
set +e
run_script apply >"$TEST_ROOT/t14.out" 2>"$TEST_ROOT/t14.err"
t14_ec=$?
set -e
printf 'RED-record test14 apply exit_code=%s\n' "$t14_ec" >&2
printf 'RED-record test14 apply exit_code=%s\n' "$t14_ec" >>"$TEST_ROOT/red-exit-codes.log"
if [[ "$t14_ec" -eq 0 ]]; then
  echo "RED-evidence: apply succeeded when read-back is server-disabled only" >&2
  cat "$TEST_ROOT/t14.out" "$TEST_ROOT/t14.err" >&2 || true
  fail "apply must be non-zero when read-back is only 'Spotlight server is disabled.'"
else
  # marker は create 済みでもよいが、索引フラグ成功とみなしてはいけない
  pass "apply-rejects-spotlight-server-is-disabled-readback"
fi

# 15. RED→GREEN: disabled でも marker 不在なら verify 失敗（復帰防止の欠陥検出）
reset_state
printf 'disabled\n' > "$STATE/status_root"
printf 'disabled\n' > "$STATE/status_System_Volumes_Data"
# marker は置かない
if run_script verify >/dev/null 2>"$TEST_ROOT/no-marker.err"; then
  fail "verify must fail when marker is absent even if indexing is disabled"
else
  grep -Eiq 'marker|metadata_never_index' "$TEST_ROOT/no-marker.err" ||
    fail "verify failure should mention marker"
  pass "verify-fails-when-marker-absent"
fi

# 16. marker 作成失敗時は mdutil -i off を始めない
reset_state
# parent をファイルにして touch 失敗させる
rm -rf "$MARKER_PARENT"
: > "$MARKER_PARENT"
if run_script apply >/dev/null 2>"$TEST_ROOT/marker-fail.err"; then
  fail "apply should fail when marker cannot be created"
else
  if [[ -f "$STATE/mdutil.log" ]] && grep -q -- '-i off' "$STATE/mdutil.log"; then
    fail "mdutil -i off must not run when marker creation fails"
  else
    pass "marker-create-failure-skips-mdutil"
  fi
fi

# 17. apply が marker を正常作成する（空ファイル）
reset_state
run_script apply >/dev/null || fail "apply should succeed and create marker"
[[ -f "$MARKER_PATH" ]] || fail "marker should be a regular file"
[[ ! -s "$MARKER_PATH" ]] || true  # 空でなくてよいが存在必須
# 二重 apply でも成功（冪等）
run_script apply >/dev/null || fail "second apply should be idempotent with marker"
pass "apply-creates-marker-idempotent"

# 18. 非 root は marker も作らない
reset_state
if SPOTLIGHT_EUID=501 run_script apply >/dev/null 2>"$TEST_ROOT/non-root-marker.err"; then
  fail "non-root apply should fail"
else
  [[ ! -e "$MARKER_PATH" ]] || fail "non-root must not create marker"
  pass "non-root-no-marker-create"
fi

# 19. Red→Green: "Indexing and searching disabled." + marker は verify 成功
# mdutil バイナリ一次証拠。server-disabled は拒否したまま。
reset_state
place_marker
printf 'and-searching-disabled\n' > "$STATE/status_root"
printf 'and-searching-disabled\n' > "$STATE/status_System_Volumes_Data"
set +e
run_script verify >"$TEST_ROOT/t19.out" 2>"$TEST_ROOT/t19.err"
t19_ec=$?
set -e
printf 'RED-record test19 verify exit_code=%s\n' "$t19_ec" >&2
if [[ "$t19_ec" -ne 0 ]]; then
  echo "RED-evidence: verify rejected Indexing and searching disabled.:" >&2
  cat "$TEST_ROOT/t19.out" "$TEST_ROOT/t19.err" >&2 || true
  fail "verify must accept 'Indexing and searching disabled.' with marker"
else
  grep -Fq 'Indexing and searching disabled' "$TEST_ROOT/t19.out" ||
    fail "verify stdout should show and-searching phrase"
  pass "verify-accepts-indexing-and-searching-disabled"
fi

# 20. Red→Green: marker 起因の長文 + marker は verify 成功
reset_state
place_marker
printf 'never-index-file-disabled\n' > "$STATE/status_root"
printf 'never-index-file-disabled\n' > "$STATE/status_System_Volumes_Data"
set +e
run_script verify >"$TEST_ROOT/t20.out" 2>"$TEST_ROOT/t20.err"
t20_ec=$?
set -e
printf 'RED-record test20 verify exit_code=%s\n' "$t20_ec" >&2
if [[ "$t20_ec" -ne 0 ]]; then
  echo "RED-evidence: verify rejected never_index file phrase:" >&2
  cat "$TEST_ROOT/t20.out" "$TEST_ROOT/t20.err" >&2 || true
  fail "verify must accept '...disabled because of .metadata_never_index file at root of volume.'"
else
  grep -Fq '.metadata_never_index file at root of volume' "$TEST_ROOT/t20.out" ||
    fail "verify stdout should show never_index root phrase"
  pass "verify-accepts-disabled-because-of-metadata-never-index"
fi

# 21. 長文成功でも marker 不在なら非ゼロ（成功条件の積）
reset_state
printf 'never-index-file-disabled\n' > "$STATE/status_root"
printf 'never-index-file-disabled\n' > "$STATE/status_System_Volumes_Data"
set +e
run_script verify >"$TEST_ROOT/t21.out" 2>"$TEST_ROOT/t21.err"
t21_ec=$?
set -e
printf 'RED-record test21 verify exit_code=%s\n' "$t21_ec" >&2
if [[ "$t21_ec" -eq 0 ]]; then
  fail "never_index phrase without marker file must not succeed"
else
  pass "verify-rejects-never-index-phrase-without-marker-file"
fi

echo "----"
echo "passed=$PASS failed=$FAIL"
[[ "$FAIL" -eq 0 ]] || exit 1
