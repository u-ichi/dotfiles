#!/usr/bin/env bash
# pane 増減後に AI sidebar 用の表示番号だけ更新する。sidebar の作成や layout 変更はしない。
set -u

[ -z "${TMUX:-}" ] && exit 0

while IFS=$'\t' read -r win_id; do
  [ -z "$win_id" ] && continue

  display_index=1
  while IFS=$'\t' read -r pane_id is_sidebar; do
    if [ "$is_sidebar" = "1" ]; then
      tmux set-option -p -t "$pane_id" @ai_display_index "" 2>/dev/null || true
      continue
    fi

    tmux set-option -p -t "$pane_id" @ai_display_index "$display_index" 2>/dev/null || true
    display_index=$((display_index + 1))
  done < <(tmux list-panes -t "$win_id" -F '#{pane_id}	#{@ai_sidebar}' 2>/dev/null)
done < <(tmux list-windows -F '#{window_id}' 2>/dev/null)
