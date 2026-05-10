#!/usr/bin/env bash
# tmux AI sidebar を専用 socket の disposable server だけで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
SOCKET_DIR="$(mktemp -d "$TMP_BASE/tmux-ai-sidebar-test.XXXXXX")"
SOCKET="$SOCKET_DIR/socket"
TEST_HOME="$SOCKET_DIR/home"

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

sidebar_version() {
  tmux_i list-panes -t "$1" -F '#{@ai_sidebar}	#{@ai_sidebar_version}' \
    | awk -F '\t' '$1 == "1" { print $2; exit }'
}

window_exists() {
  local target="$1"

  tmux_i list-windows -F '#{window_id}' | grep -Fxq "$target"
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

wait_for_window_absent() {
  local target="$1"

  for _ in {1..30}; do
    if ! window_exists "$target"; then
      return 0
    fi
    sleep 0.1
  done

  echo "ERROR: $target still exists after orphan sidebar cleanup" >&2
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

mkdir -p "$TEST_HOME/.config/fish/functions"
ln -s "$SCRIPT_DIR" "$TEST_HOME/.config/tmux"
ln -s "$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish" "$TEST_HOME/.config/fish/functions/ai-panes-sidebar.fish"
export HOME="$TEST_HOME"

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

kill_pane_hook="$(tmux_i show-hooks -g after-kill-pane)"
if ! printf '%s\n' "$kill_pane_hook" | grep -q 'cleanup-ai-sidebars.sh'; then
  echo "ERROR: after-kill-pane hook does not clean up orphan sidebars" >&2
  printf '%s\n' "$kill_pane_hook" >&2
  exit 1
fi

TMUX="$SOCKET,0,0" "$SCRIPT_DIR/ensure-ai-sidebars.sh"
wait_for_sidebar 'ai-sidebar-test:1'
if [ "$(sidebar_version 'ai-sidebar-test:1')" != "16" ]; then
  echo "ERROR: sidebar version was not recorded" >&2
  exit 1
fi

if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; test (__ai_sidebar_max_line_chars 4) -eq 3; and test (__ai_sidebar_max_line_chars 1) -eq 1; and test (__ai_sidebar_max_line_chars invalid) -eq 25"; then
  echo "ERROR: sidebar line width calculation is invalid" >&2
  exit 1
fi

if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; test (printf '%s\n' 'Conversation interrupted - tell the model what to do differently' '• Working (10s • esc to interrupt)' | __ai_codex_visible_state) = working; and test (printf '%s\n' '• Working (10s • esc to interrupt)' '› 対処して' | __ai_codex_visible_state) = working; and test (printf '%s\n' '• Booting MCP server: codex_apps (5m 12s • esc to interrupt)' | __ai_codex_visible_state) = working; and test (printf '%s\n' '• Working (10s • esc to interrupt)' '• Worked for 1m 42s' '› 対処して' | __ai_codex_visible_state) = idle; and test (printf '%s\n' 'Would you like to run the following command?' 'Yes, proceed (y)' | __ai_codex_visible_state) = waiting"; then
  echo "ERROR: Codex visible state detection is invalid" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  plan_file="$SOCKET_DIR/codex-plan.jsonl"
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: tmux sidebar に Goal を表示する\",\"plan\":[{\"step\":\"Task: 古い作業\",\"status\":\"completed\"},{\"step\":\"SubTask: 古い確認\",\"status\":\"completed\"},{\"step\":\"Task: plan 表示を直す\",\"status\":\"in_progress\"},{\"step\":\"SubTask: plan を読む\",\"status\":\"completed\"},{\"step\":\"SubTask: Goal 行を出す\",\"status\":\"in_progress\"},{\"step\":\"SubTask: live 表示を確認する\",\"status\":\"pending\"}]}"}}' > "$plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$plan_file' 80); test \"\$lines[1]\" = 'Goal: tmux sidebar に Goal を表示する'; and test \"\$lines[2]\" = '1/3 plan 表示を直す'; and test \"\$lines[3]\" = '  ✓ plan を読む'; and test \"\$lines[4]\" = '  > Goal 行を出す'; and test \"\$lines[5]\" = '  - live 表示を確認する'"; then
    echo "ERROR: Codex plan goal lines are invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$plan_file' 80" >&2 || true
    exit 1
  fi
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: tmux sidebar に Goal を表示する\",\"plan\":[{\"step\":\"Task: plan 表示を直す\",\"status\":\"completed\"},{\"step\":\"SubTask: plan を読む\",\"status\":\"completed\"},{\"step\":\"SubTask: Goal 行を出す\",\"status\":\"completed\"},{\"step\":\"SubTask: live 表示を確認する\",\"status\":\"completed\"}]}"}}' >> "$plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$plan_file' 80); test \"\$lines[2]\" = '3/3 plan 表示を直す'"; then
    echo "ERROR: Codex completed plan line is invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$plan_file' 80" >&2 || true
    exit 1
  fi
  no_prefix_plan_file="$SOCKET_DIR/codex-plan-no-prefix.jsonl"
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: task 重複を防ぐ\",\"plan\":[{\"step\":\"MCP 状態誤判定修正を commit する\",\"status\":\"in_progress\"},{\"step\":\"commit skill と差分を確認する\",\"status\":\"completed\"},{\"step\":\"対象ファイルを stage する\",\"status\":\"pending\"}]}"}}' > "$no_prefix_plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$no_prefix_plan_file' 80); test \"\$lines[2]\" = '1/2 MCP 状態誤判定修正を commit する'; and test \"\$lines[3]\" = '  ✓ commit skill と差分を確認する'; and test \"\$lines[4]\" = '  - 対象ファイルを stage する'"; then
    echo "ERROR: Codex unprefixed task lines are duplicated or invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$no_prefix_plan_file' 80" >&2 || true
    exit 1
  fi
fi

sidebar_pane="$(tmux_i list-panes -t 'ai-sidebar-test:1' -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 == "1" { print $1; exit }')"
tmux_i resize-pane -t "$sidebar_pane" -x 4
TMUX="$SOCKET,0,0" "$SCRIPT_DIR/ensure-ai-sidebars.sh"
sidebar_width="$(tmux_i display-message -p -t "$sidebar_pane" '#{pane_width}')"
if [ "$sidebar_width" -ne 26 ]; then
  echo "ERROR: existing sidebar width was not restored: $sidebar_width" >&2
  exit 1
fi

tmux_i new-window -d -n second 'sleep 60'
wait_for_sidebar 'ai-sidebar-test:2'
second_window_id="$(tmux_i display-message -p -t 'ai-sidebar-test:2' '#{window_id}')"
second_normal_pane="$(tmux_i list-panes -t 'ai-sidebar-test:2' -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 != "1" { print $1; exit }')"
tmux_i kill-pane -t "$second_normal_pane"
wait_for_window_absent "$second_window_id"

echo "tmux AI sidebar isolated test passed"
