#!/usr/bin/env bash
# 各 tmux window の左端に AI pane 一覧 sidebar が無ければ作成する。
set -u

width="${1:-26}"
min_width=$((width + 40))
sidebar_version="8"
sidebar_command='sleep 0.2; exec fish -c ai-panes-sidebar'

[ -z "${TMUX:-}" ] && exit 0

while IFS=$'\t' read -r win_id win_width; do
  [ -z "$win_id" ] && continue
  [ "${win_width:-0}" -lt "$min_width" ] && continue

  sidebar_pane="$(tmux list-panes -t "$win_id" -F '#{pane_id}	#{@ai_sidebar}' 2>/dev/null \
    | awk -F '\t' '$2 == "1" { print $1; exit }')"

  target_pane="$(
    tmux list-panes -t "$win_id" -F '#{pane_id}	#{@ai_sidebar}	#{pane_active}' 2>/dev/null \
      | awk -F '\t' '$2 != "1" && $3 == "1" { print $1; found=1; exit } $2 != "1" && first == "" { first=$1 } END { if (!found && first != "") print first }'
  )"
  [ -z "$target_pane" ] && continue

  if [ -z "$sidebar_pane" ]; then
    sidebar_pane="$(tmux split-window -d -t "$target_pane" -h -b -f -l "$width" -P -F '#{pane_id}' "$sidebar_command" 2>/dev/null || true)"
    [ -z "$sidebar_pane" ] && continue
    tmux set-option -p -t "$sidebar_pane" @ai_sidebar 1 2>/dev/null || true
    tmux set-option -p -t "$sidebar_pane" @fixed_title "" 2>/dev/null || true
    tmux set-option -p -t "$sidebar_pane" @ai_sidebar_version "$sidebar_version" 2>/dev/null || true
  else
    current_version="$(tmux show-option -pqv -t "$sidebar_pane" @ai_sidebar_version 2>/dev/null || true)"
    if [ "$current_version" != "$sidebar_version" ]; then
      tmux respawn-pane -k -t "$sidebar_pane" "$sidebar_command" 2>/dev/null || true
      tmux set-option -p -t "$sidebar_pane" @ai_sidebar 1 2>/dev/null || true
      tmux set-option -p -t "$sidebar_pane" @fixed_title "" 2>/dev/null || true
      tmux set-option -p -t "$sidebar_pane" @ai_sidebar_version "$sidebar_version" 2>/dev/null || true
    fi
  fi

done < <(tmux list-windows -F '#{window_id}	#{window_width}' 2>/dev/null)

"$(dirname "$0")/update-ai-display-indexes.sh"
