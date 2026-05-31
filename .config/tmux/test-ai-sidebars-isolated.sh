#!/usr/bin/env bash
# tmux AI sidebar を専用 socket の disposable server だけで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
SOCKET_DIR="$(mktemp -d "$TMP_BASE/tmux-ai-sidebar-test.XXXXXX")"
SOCKET="$SOCKET_DIR/socket"
TEST_HOME="$SOCKET_DIR/home"
TEST_PIDS=()

cleanup() {
  for pid in "${TEST_PIDS[@]}"; do
    kill "$pid" >/dev/null 2>&1 || true
  done
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

wait_for_pane_option() {
  local pane="$1"
  local option="$2"
  local expected="$3"
  local actual

  for _ in {1..30}; do
    actual="$(tmux_i show-option -pqv -t "$pane" "$option" 2>/dev/null || true)"
    if [ "$actual" = "$expected" ]; then
      return 0
    fi
    sleep 0.1
  done

  echo "ERROR: pane option $option was not '$expected' (actual: '$actual')" >&2
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
ln -s "$SCRIPT_DIR/../fish/functions/__ai_pane_title_sync.fish" "$TEST_HOME/.config/fish/functions/__ai_pane_title_sync.fish"
export HOME="$TEST_HOME"
export TERM=xterm-256color

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

pane_exited_hook="$(tmux_i show-hooks -g pane-exited)"
if ! printf '%s\n' "$pane_exited_hook" | grep -q 'cleanup-ai-sidebars.sh'; then
  echo "ERROR: pane-exited hook does not clean up orphan sidebars (shell exit path)" >&2
  printf '%s\n' "$pane_exited_hook" >&2
  exit 1
fi

TMUX="$SOCKET,0,0" "$SCRIPT_DIR/ensure-ai-sidebars.sh"
wait_for_sidebar 'ai-sidebar-test:1'
expected_sidebar_version="$(/usr/bin/awk '/^[[:space:]]*set -l state_version[[:space:]]+[0-9]+/ {print $4; exit}' "$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish")"
if [ "$(sidebar_version 'ai-sidebar-test:1')" != "$expected_sidebar_version" ]; then
  echo "ERROR: sidebar version was not recorded (expected: $expected_sidebar_version)" >&2
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

if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; test (__ai_notify_title codex) = 'Codex CLI'; and test (__ai_notify_title claude) = 'Claude Code'; and test (__ai_notify_title other) = 'AI Console'"; then
  echo "ERROR: AI notification title mapping is invalid" >&2
  exit 1
fi

if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; test (__ai_notify_detail waiting codex repo 'Would you like to run the following command?' 'Yes, proceed (y)') = 'コマンド実行の承認待ち · repo'; and test (__ai_notify_detail idle codex repo '• Worked for 1m 42s' '› 対処して') = '処理完了 (Worked for 1m 42s) · repo'; and test (__ai_notify_detail waiting claude repo 'Do you want to proceed?' '❯ 1. Yes') = 'Do you want to proceed? · repo'"; then
  echo "ERROR: AI notification detail extraction is invalid" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  codex_sessions_dir="$TEST_HOME/.codex/sessions/2026/05/30"
  codex_session_a="$codex_sessions_dir/rollout-2026-05-30T12-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
  codex_session_b="$codex_sessions_dir/rollout-2026-05-30T12-09-31-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl"
  mkdir -p "$codex_sessions_dir"
  printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\",\"cwd\":\"$TEST_HOME\"}}" > "$codex_session_a"
  printf '%s\n' "{\"type\":\"session_meta\",\"payload\":{\"id\":\"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb\",\"cwd\":\"$TEST_HOME\"}}" > "$codex_session_b"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set a_start (__ai_codex_session_start_epoch '$codex_session_a'); set title_id (__ai_codex_session_id_from_title 'agent | bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb | Context 1% used'); set by_id (__ai_codex_session_file_by_id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb); set by_time (__ai_codex_find_session_file '$TEST_HOME' \$a_start); test \"\$title_id\" = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; and test (basename \"\$by_id\") = 'rollout-2026-05-30T12-09-31-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl'; and test (basename \"\$by_time\") = 'rollout-2026-05-30T12-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl'; and not __ai_codex_session_matches_started_at '$codex_session_b' \$a_start"; then
    echo "ERROR: Codex sidebar session file resolution allows cross-pane collision" >&2
    exit 1
  fi
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/__ai_pane_title_sync.fish'; set a_start (__ai_pane_title_sync_codex_session_start_epoch '$codex_session_a'); set by_id (__ai_pane_title_sync_codex_session_file_by_id bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb); set by_time (__ai_pane_title_sync_codex_find_session_file '$TEST_HOME' \$a_start); test (__ai_pane_title_sync_codex_session_id_from_title 'agent | bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb | Context 1% used') = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; and test (basename \"\$by_id\") = 'rollout-2026-05-30T12-09-31-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb.jsonl'; and test (basename \"\$by_time\") = 'rollout-2026-05-30T12-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl'"; then
    echo "ERROR: Codex pane title session file resolution allows cross-pane collision" >&2
    exit 1
  fi
  if command -v sqlite3 >/dev/null 2>&1; then
    goal_home="$SOCKET_DIR/goal-title-home"
    mkdir -p "$goal_home/.codex"
    sqlite3 "$goal_home/.codex/goals_1.sqlite" "create table thread_goals (thread_id text primary key not null, goal_id text not null, objective text not null, status text not null, token_budget integer, tokens_used integer not null default 0, time_used_seconds integer not null default 0, created_at_ms integer not null, updated_at_ms integer not null);"
    sqlite3 "$goal_home/.codex/goals_1.sqlite" "insert into thread_goals (thread_id, goal_id, objective, status, created_at_ms, updated_at_ms) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'goal-title-1', 'goal title smoke', 'active', 0, 0);"
    if ! HOME="$goal_home" fish -c "source '$SCRIPT_DIR/../fish/functions/__ai_pane_title_sync.fish'; test (__ai_pane_title_sync_codex_goal_title '$codex_session_a') = 'goal title smoke'"; then
      echo "ERROR: Codex pane title sync does not prefer native goal objective" >&2
      exit 1
    fi

    sqlite3 "$TEST_HOME/.codex/state_5.sqlite" "create table threads (id text primary key not null, title text, rollout_path text, updated_at integer);"
    sqlite3 "$TEST_HOME/.codex/state_5.sqlite" "insert into threads (id, title, rollout_path, updated_at) values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'thread title smoke', '$codex_session_a', 1);"
  fi
fi

new_project_dir="$TEST_HOME/new-project"
mkdir -p "$new_project_dir"
normal_pane="$(tmux_i list-panes -t 'ai-sidebar-test:1' -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 != "1" { print $1; exit }')"
tmux_i set-option -p -t "$normal_pane" @fixed_title "old-session-title"
tmux_i set-option -p -t "$normal_pane" @ai_base_title "old-base-title"
TMUX="$SOCKET,0,0" TMUX_PANE="$normal_pane" fish -c "source '$SCRIPT_DIR/../fish/functions/codex.fish'; __codex_set_pane_base_title -C '$new_project_dir'"
fixed_title="$(tmux_i show-option -pqv -t "$normal_pane" @fixed_title)"
base_title="$(tmux_i show-option -pqv -t "$normal_pane" @ai_base_title)"
if [ -n "$fixed_title" ] || [ "$base_title" != "new-project" ]; then
  echo "ERROR: Codex pane title startup cleanup is invalid (fixed='$fixed_title', base='$base_title')" >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1 && command -v sqlite3 >/dev/null 2>&1; then
  tmux_i select-pane -t "$normal_pane" -T 'dotfiles | aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa | Context 1% used'
  tmux_i set-option -p -t "$normal_pane" @ai_codex_session_file "$codex_session_a"
  tmux_i set-option -p -t "$normal_pane" @ai_base_title ""
  TMUX="$SOCKET,0,0" HOME="$TEST_HOME" fish -c "source '$SCRIPT_DIR/../fish/functions/__ai_pane_title_sync.fish'; __ai_pane_title_sync codex-watch '$normal_pane' '$TEST_HOME' 0 fallback" &
  watcher_pid="$!"
  TEST_PIDS+=("$watcher_pid")
  wait_for_pane_option "$normal_pane" @ai_base_title "thread title smoke"
  tmux_i set-option -p -t "$normal_pane" @ai_base_title ""
  wait_for_pane_option "$normal_pane" @ai_base_title "thread title smoke"
  kill "$watcher_pid" >/dev/null 2>&1 || true
  wait "$watcher_pid" >/dev/null 2>&1 || true
fi

if command -v jq >/dev/null 2>&1; then
  plan_file="$SOCKET_DIR/codex-plan.jsonl"
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: tmux sidebar に Goal を表示する\",\"plan\":[{\"step\":\"Task: 古い作業\",\"status\":\"completed\"},{\"step\":\"SubTask: 古い確認\",\"status\":\"completed\"},{\"step\":\"Task: plan 表示を直す\",\"status\":\"in_progress\"},{\"step\":\"SubTask: plan を読む\",\"status\":\"completed\"},{\"step\":\"SubTask: Goal 行を出す\",\"status\":\"in_progress\"},{\"step\":\"SubTask: live 表示を確認する\",\"status\":\"pending\"}]}"}}' > "$plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set yellow (set_color yellow); set lines (__ai_codex_plan_lines '$plan_file' 80 20); string match -q \"\$yellow*tmux sidebar に Goal を表示する*\" -- \"\$lines[1]\"; and test \"\$lines[2]\" = '✓ 1/1 古い作業'; and test \"\$lines[3]\" = '> 1/3 plan 表示を直す'; and test \"\$lines[4]\" = '  ✓ plan を読む'; and test \"\$lines[5]\" = '  > Goal 行を出す'; and test \"\$lines[6]\" = '  - live 表示を確認する'"; then
    echo "ERROR: Codex plan goal lines are invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$plan_file' 80 20" >&2 || true
    exit 1
  fi
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set cyan (set_color --bold cyan); set normal (set_color normal); test (__ai_sidebar_plain_text \"\$cyan\"'goal title smoke'\"\$normal\") = 'goal title smoke'"; then
    echo "ERROR: sidebar plain text normalization is invalid" >&2
    exit 1
  fi
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set cyan (set_color --bold cyan); set normal (set_color normal); set lines (__ai_sidebar_detail_lines 'goal title smoke' 80 \"\$cyan\"'goal title smoke'\"\$normal\" '> task line'); test (count \$lines) -eq 2; and test \"\$lines[1]\" = \"\$cyan\"'goal title smoke'\"\$normal\"; and test \"\$lines[2]\" = ' > task line'"; then
    echo "ERROR: sidebar detail lines should suppress duplicate goal title" >&2
    exit 1
  fi
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: tmux sidebar に Goal を表示する\",\"plan\":[{\"step\":\"Task: plan 表示を直す\",\"status\":\"completed\"},{\"step\":\"SubTask: plan を読む\",\"status\":\"completed\"},{\"step\":\"SubTask: Goal 行を出す\",\"status\":\"completed\"},{\"step\":\"SubTask: live 表示を確認する\",\"status\":\"completed\"}]}"}}' >> "$plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$plan_file' 80 20); test \"\$lines[2]\" = '✓ 3/3 plan 表示を直す'; and test \"\$lines[3]\" = '  ✓ plan を読む'; and test \"\$lines[4]\" = '  ✓ Goal 行を出す'; and test \"\$lines[5]\" = '  ✓ live 表示を確認する'"; then
    echo "ERROR: Codex completed plan line is invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$plan_file' 80 20" >&2 || true
    exit 1
  fi
  response_item_plan_file="$SOCKET_DIR/codex-plan-response-item.jsonl"
  printf '%s\n' '{"type":"response_item","payload":{"type":"function_call_output","output":"{\"name\":\"update_plan\",\"payload\":{\"arguments\":\"stale\"}}"}}' '{"type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{\"explanation\":\"Goal: response_item schema を読む\",\"plan\":[{\"step\":\"Task: schema 対応を確認する\",\"status\":\"in_progress\"},{\"step\":\"SubTask: 実 event を読む\",\"status\":\"in_progress\"}]}"}}' > "$response_item_plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$response_item_plan_file' 80 20); string match -q '*response_item schema を読む*' -- \"\$lines[1]\"; and test \"\$lines[2]\" = '> 0/1 schema 対応を確認する'; and test \"\$lines[3]\" = '  > 実 event を読む'"; then
    echo "ERROR: Codex response_item plan extraction is invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$response_item_plan_file' 80 20" >&2 || true
    exit 1
  fi
  no_prefix_plan_file="$SOCKET_DIR/codex-plan-no-prefix.jsonl"
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: task 重複を防ぐ\",\"plan\":[{\"step\":\"MCP 状態誤判定修正を commit する\",\"status\":\"in_progress\"},{\"step\":\"commit skill と差分を確認する\",\"status\":\"completed\"},{\"step\":\"対象ファイルを stage する\",\"status\":\"pending\"}]}"}}' > "$no_prefix_plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$no_prefix_plan_file' 80 20); test \"\$lines[2]\" = '> 1/2 MCP 状態誤判定修正を commit する'; and test \"\$lines[3]\" = '  ✓ commit skill と差分を確認する'; and test \"\$lines[4]\" = '  - 対象ファイルを stage する'"; then
    echo "ERROR: Codex unprefixed task lines are duplicated or invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$no_prefix_plan_file' 80 20" >&2 || true
    exit 1
  fi
  many_tasks_plan_file="$SOCKET_DIR/codex-plan-many-tasks.jsonl"
  printf '%s\n' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: task tree 全体を表示する\",\"plan\":[{\"step\":\"Task: 入力を確認する\",\"status\":\"completed\"},{\"step\":\"SubTask: スクリーンショットを見る\",\"status\":\"completed\"},{\"step\":\"Task: 表示ロジックを直す\",\"status\":\"in_progress\"},{\"step\":\"SubTask: Task 一覧を作る\",\"status\":\"completed\"},{\"step\":\"SubTask: active SubTask を出す\",\"status\":\"in_progress\"},{\"step\":\"Task: 検証する\",\"status\":\"pending\"},{\"step\":\"SubTask: isolated test を走らせる\",\"status\":\"pending\"}]}"}}' > "$many_tasks_plan_file"
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_codex_plan_lines '$many_tasks_plan_file' 80 20); test \"\$lines[2]\" = '✓ 1/1 入力を確認する'; and test \"\$lines[3]\" = '> 1/2 表示ロジックを直す'; and test \"\$lines[4]\" = '  ✓ Task 一覧を作る'; and test \"\$lines[5]\" = '  > active SubTask を出す'; and test \"\$lines[6]\" = '- 0/1 検証する'"; then
    echo "ERROR: Codex multiple task tree lines are invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$many_tasks_plan_file' 80 20" >&2 || true
    exit 1
  fi

  if command -v sqlite3 >/dev/null 2>&1; then
    native_goal_file="$SOCKET_DIR/rollout-2026-05-30T12-00-00-11111111-2222-3333-4444-555555555555.jsonl"
    mkdir -p "$TEST_HOME/.codex"
    sqlite3 "$TEST_HOME/.codex/goals_1.sqlite" "create table thread_goals (thread_id text primary key not null, goal_id text not null, objective text not null, status text not null, token_budget integer, tokens_used integer not null default 0, time_used_seconds integer not null default 0, created_at_ms integer not null, updated_at_ms integer not null);"
    sqlite3 "$TEST_HOME/.codex/goals_1.sqlite" "insert into thread_goals (thread_id, goal_id, objective, status, created_at_ms, updated_at_ms) values ('11111111-2222-3333-4444-555555555555', 'goal-1', 'native goal smoke', 'active', 0, 0);"
    printf '%s\n' '{"type":"session_meta","payload":{"id":"11111111-2222-3333-4444-555555555555"}}' '{"name":"update_plan","payload":{"arguments":"{\"explanation\":\"Goal: native goal 色分け\",\"plan\":[{\"step\":\"Task: 表示を確認する\",\"status\":\"in_progress\"}]}"}}' > "$native_goal_file"
    if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set native (set_color --bold cyan); set lines (__ai_codex_plan_lines '$native_goal_file' 80 20); string match -q \"\$native*native goal 色分け*\" -- \"\$lines[1]\"; and test \"\$lines[2]\" = '> 表示を確認する'"; then
      echo "ERROR: Codex native goal color is invalid" >&2
      fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$native_goal_file' 80 20" >&2 || true
      exit 1
    fi

    native_goal_fallback_file="$SOCKET_DIR/rollout-2026-05-30T12-01-00-22222222-3333-4444-5555-666666666666.jsonl"
    sqlite3 "$TEST_HOME/.codex/goals_1.sqlite" "insert into thread_goals (thread_id, goal_id, objective, status, created_at_ms, updated_at_ms) values ('22222222-3333-4444-5555-666666666666', 'goal-2', 'native goal objective fallback', 'active', 0, 0);"
    printf '%s\n' '{"type":"session_meta","payload":{"id":"22222222-3333-4444-5555-666666666666"}}' '{"name":"update_plan","payload":{"arguments":"{\"plan\":[{\"step\":\"Task: native goal を表示する\",\"status\":\"in_progress\"}]}"}}' > "$native_goal_fallback_file"
    if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set native (set_color --bold cyan); set lines (__ai_codex_plan_lines '$native_goal_fallback_file' 80 20); string match -q \"\$native*native goal objective fallback*\" -- \"\$lines[1]\"; and test \"\$lines[2]\" = '> native goal を表示する'"; then
      echo "ERROR: Codex native goal fallback line is invalid" >&2
      fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_codex_plan_lines '$native_goal_fallback_file' 80 20" >&2 || true
      exit 1
    fi
  fi

  # Claude TaskList tree: TaskCreate + TaskUpdate event stream を逐次再生して最新 state を出す。
  claude_task_file="$SOCKET_DIR/claude-tasks.jsonl"
  cat > "$claude_task_file" <<'CLAUDE_JSONL'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a1","name":"TaskCreate","input":{"subject":"親タスクで原因調査","description":"","metadata":{"goal":"sidebar 復旧"}}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a1","type":"tool_result","content":"Task #1 created"}]},"toolUseResult":{"task":{"id":"1","subject":"親タスクで原因調査"}}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a2","name":"TaskUpdate","input":{"taskId":"1","status":"in_progress","subject":"#1 親タスクで原因調査"}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a2","type":"tool_result","content":"Updated"}]},"toolUseResult":{"success":true,"taskId":"1","updatedFields":["status","subject"]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a3","name":"TaskCreate","input":{"subject":"[#1系] 子タスクで実装","description":"","metadata":{"parentTaskId":"1"}}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a3","type":"tool_result","content":"Task #2 created"}]},"toolUseResult":{"task":{"id":"2","subject":"[#1系] 子タスクで実装"}}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a4","name":"TaskUpdate","input":{"taskId":"2","status":"completed"}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a4","type":"tool_result","content":"Updated"}]},"toolUseResult":{"success":true,"taskId":"2","updatedFields":["status"]}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a5","name":"TaskCreate","input":{"subject":"[#1系] 子タスク2 で検証","description":"","metadata":{"parentTaskId":"1"}}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a5","type":"tool_result","content":"Task #3 created"}]},"toolUseResult":{"task":{"id":"3","subject":"[#1系] 子タスク2 で検証"}}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a6","name":"TaskUpdate","input":{"taskId":"3","status":"in_progress"}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a6","type":"tool_result","content":"Updated"}]},"toolUseResult":{"success":true,"taskId":"3","updatedFields":["status"]}}
CLAUDE_JSONL
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set green (set_color green); set normal (set_color normal); set lines (__ai_claude_task_lines '$claude_task_file' 80 20); test \"\$lines[1]\" = 'sidebar 復旧'; and test \"\$lines[2]\" = \"\$green▶ 1/2 親タスクで原因調査\$normal\"; and test \"\$lines[3]\" = '  ✓ 子タスクで実装'; and test \"\$lines[4]\" = \"\$green  ▶ 子タスク2 で検証\$normal\""; then
    echo "ERROR: Claude task tree lines are invalid" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_claude_task_lines '$claude_task_file' 80 20" >&2 || true
    exit 1
  fi

  # 削除済みタスクは sidebar に出ない
  cat >> "$claude_task_file" <<'CLAUDE_JSONL2'
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a7","name":"TaskCreate","input":{"subject":"消すタスク","description":""}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a7","type":"tool_result","content":"Task #4 created"}]},"toolUseResult":{"task":{"id":"4","subject":"消すタスク"}}}
{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_a8","name":"TaskUpdate","input":{"taskId":"4","status":"deleted"}}]}}
{"type":"user","message":{"content":[{"tool_use_id":"toolu_a8","type":"tool_result","content":"Updated"}]},"toolUseResult":{"success":true,"taskId":"4","updatedFields":["status"]}}
CLAUDE_JSONL2
  if ! fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; set lines (__ai_claude_task_lines '$claude_task_file' 80 20); test (count \$lines) -eq 4"; then
    echo "ERROR: Claude deleted tasks should not appear" >&2
    fish -c "source '$SCRIPT_DIR/../fish/functions/ai-panes-sidebar.fish'; __ai_claude_task_lines '$claude_task_file' 80 20" >&2 || true
    exit 1
  fi
fi

sidebar_pane="$(tmux_i list-panes -t 'ai-sidebar-test:1' -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 == "1" { print $1; exit }')"
tmux_i resize-pane -t "$sidebar_pane" -x 4
TMUX="$SOCKET,0,0" "$SCRIPT_DIR/ensure-ai-sidebars.sh"
sidebar_width="$(tmux_i display-message -p -t "$sidebar_pane" '#{pane_width}')"
if [ "$sidebar_width" -ne 32 ]; then
  echo "ERROR: existing sidebar width was not restored: $sidebar_width" >&2
  exit 1
fi

tmux_i new-window -d -n second 'sleep 60'
wait_for_sidebar 'ai-sidebar-test:2'
second_window_id="$(tmux_i display-message -p -t 'ai-sidebar-test:2' '#{window_id}')"
second_normal_pane="$(tmux_i list-panes -t 'ai-sidebar-test:2' -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 != "1" { print $1; exit }')"
tmux_i kill-pane -t "$second_normal_pane"
wait_for_window_absent "$second_window_id"

# shell の正常 exit (Ctrl+D 相当) でも orphan sidebar を掃除し window が閉じること。
# after-kill-pane は kill-pane コマンドでしか発火しないため、exit 経路は pane-exited
# hook で拾う。window index は renumber-windows で変わるため window_id で追跡する。
third_window_id="$(tmux_i new-window -d -n third -P -F '#{window_id}' 'bash')"
wait_for_sidebar "$third_window_id"
third_normal_pane="$(tmux_i list-panes -t "$third_window_id" -F '#{pane_id}	#{@ai_sidebar}' | awk -F '\t' '$2 != "1" { print $1; exit }')"
tmux_i send-keys -t "$third_normal_pane" 'exit' Enter
wait_for_window_absent "$third_window_id"

echo "tmux AI sidebar isolated test passed"
