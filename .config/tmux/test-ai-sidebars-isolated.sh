#!/usr/bin/env bash
# tmux AI sidebar を専用 socket の disposable server だけで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
SOCKET_DIR="$(mktemp -d "$TMP_BASE/tmux-ai-sidebar-test.XXXXXX")"
SOCKET="$SOCKET_DIR/socket"

cleanup() {
  command tmux -S "$SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$SOCKET_DIR"
}
trap cleanup EXIT

tmux_i() {
  command tmux -S "$SOCKET" "$@"
}

sidebar_count() {
  tmux_i list-panes -t "$1" -F '#{@ai_sidebar}' \
    | awk '$1 == "1" { count++ } END { print count + 0 }'
}

wait_for_sidebar() {
  local target="$1"
  local count

  for _ in {1..30}; do
    count="$(sidebar_count "$target")"
    if [ "$count" -eq 1 ]; then
      return 0
    fi
    sleep 0.1
  done

  echo "ERROR: sidebar was not created for $target" >&2
  tmux_i list-panes -t "$target" -F '#{pane_id} sidebar=#{@ai_sidebar} active=#{pane_active} title=#{pane_title}' >&2 || true
  return 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "SKIP: $1 is not installed" >&2
    exit 0
  fi
}

require_command tmux
require_command fish

tmux_i new-session -d -s ai-sidebar-test -n first -x 120 -y 30 'sleep 60'
tmux_i source-file "$SCRIPT_DIR/tmux.conf"

enabled="$(tmux_i show-option -gqv @ai_sidebars_enabled)"
if [ "$enabled" != "1" ]; then
  echo "ERROR: @ai_sidebars_enabled is not enabled by default" >&2
  exit 1
fi

for key in c h v '"' %; do
  binding="$(tmux_i list-keys -T prefix "$key" 2>/dev/null || true)"
  if ! printf '%s\n' "$binding" | grep -q '#{pane_current_path}'; then
    echo "ERROR: prefix+$key does not inherit pane_current_path" >&2
    printf '%s\n' "$binding" >&2
    exit 1
  fi
done

client_hook="$(tmux_i show-hooks -g client-attached)"
if ! printf '%s\n' "$client_hook" | grep -q 'ensure-ai-sidebars.sh'; then
  echo "ERROR: client-attached hook does not create sidebars" >&2
  printf '%s\n' "$client_hook" >&2
  exit 1
fi

new_window_hook="$(tmux_i show-hooks -g after-new-window)"
if ! printf '%s\n' "$new_window_hook" | grep -q 'ensure-ai-sidebars.sh'; then
  echo "ERROR: after-new-window hook does not create sidebars" >&2
  printf '%s\n' "$new_window_hook" >&2
  exit 1
fi

TMUX="$SOCKET,0,0" "$SCRIPT_DIR/ensure-ai-sidebars.sh"
wait_for_sidebar 'ai-sidebar-test:1'

tmux_i new-window -d -n second 'sleep 60'
wait_for_sidebar 'ai-sidebar-test:2'

echo "tmux AI sidebar isolated test passed"
