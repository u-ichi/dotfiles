#!/usr/bin/env bash
# 通常 pane が残っていない window の AI sidebar を閉じる。
set -u

[ -z "${TMUX:-}" ] && exit 0

while IFS=$'\t' read -r win_id; do
  [ -z "$win_id" ] && continue

  normal_count=0
  sidebar_panes=()

  while IFS=$'\t' read -r pane_id is_sidebar; do
    [ -z "$pane_id" ] && continue
    if [ "$is_sidebar" = "1" ]; then
      sidebar_panes+=("$pane_id")
    else
      normal_count=$((normal_count + 1))
    fi
  done < <(tmux list-panes -t "$win_id" -F '#{pane_id}	#{@ai_sidebar}' 2>/dev/null)

  [ "$normal_count" -eq 0 ] || continue

  for pane_id in "${sidebar_panes[@]}"; do
    tmux kill-pane -t "$pane_id" 2>/dev/null || true
  done
done < <(tmux list-windows -F '#{window_id}' 2>/dev/null)
