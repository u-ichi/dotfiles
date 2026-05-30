#!/usr/bin/env bash
# tmux の共有 server を巻き込む危険なコマンドを検出する。
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MODE="${1:---all}"
LABEL="${2:-stdin}"
ERRORS=0
TMP_FILE=""

cleanup() {
  if [ -n "$TMP_FILE" ] && [ -e "$TMP_FILE" ]; then
    rm -f "$TMP_FILE"
  fi
}
trap cleanup EXIT

is_isolated_tmux_line() {
  local line="$1"

  [[ "$line" =~ (^|[[:space:]])-S($|[[:space:]=]) ]] && return 0
  [[ "$line" =~ (^|[[:space:]])-S[^[:space:]] ]] && return 0
  [[ "$line" =~ (^|[[:space:]])-L($|[[:space:]=]) ]] && return 0
  [[ "$line" =~ (^|[[:space:]])-L[^[:space:]] ]] && return 0
  return 1
}

scan_stream() {
  local label="$1"
  local line
  local line_no=0
  local tmux_re='(^|[^[:alnum:]_])tmux([[:space:]]|$)'
  local kill_word="kill-server"

  while IFS= read -r line || [ -n "$line" ]; do
    line_no=$((line_no + 1))
    if [[ "$line" =~ $tmux_re ]] && [[ "$line" == *"$kill_word"* ]] && ! is_isolated_tmux_line "$line"; then
      echo "ERROR: unsafe tmux server-wide kill command: $label:$line_no" >&2
      echo "  $line" >&2
      echo "  tmux server を落とす検証は -S <socket> または -L <name> で隔離してください。" >&2
      ERRORS=$((ERRORS + 1))
    fi
  done
}

scan_worktree_file() {
  local file="$1"
  local path="$ROOT/$file"

  [ -f "$path" ] || return 0
  grep -Iq . "$path" || return 0
  scan_stream "$file" < "$path"
}

scan_staged_file() {
  local file="$1"

  TMP_FILE="$(mktemp)"
  git -C "$ROOT" show ":$file" > "$TMP_FILE" 2>/dev/null || return 0
  grep -Iq . "$TMP_FILE" || return 0
  scan_stream "$file" < "$TMP_FILE"
  rm -f "$TMP_FILE"
  TMP_FILE=""
}

case "$MODE" in
  --stdin)
    scan_stream "$LABEL"
    ;;
  --staged)
    while IFS= read -r -d '' file; do
      scan_staged_file "$file"
    done < <(git -C "$ROOT" diff --cached --name-only -z --diff-filter=ACMR)
    ;;
  --all)
    while IFS= read -r -d '' file; do
      scan_worktree_file "$file"
    done < <(git -C "$ROOT" ls-files -z --cached --others --exclude-standard)
    ;;
  *)
    echo "usage: $0 [--all|--staged|--stdin <label>]" >&2
    exit 2
    ;;
esac

if [ "$ERRORS" -gt 0 ]; then
  echo "tmux safety check failed: $ERRORS 件" >&2
  exit 1
fi
