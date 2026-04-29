#!/usr/bin/env bash
# AI sidebar のクリック行から対象 pane にジャンプする。
set -u

mouse_pane="${1:-}"
mouse_line="${2:-}"
mouse_y="${3:-}"
log_file="/tmp/ai-sidebar-click-${USER:-unknown}.log"
line_no=""

[ -z "$mouse_pane" ] && exit 0

is_sidebar="$(tmux show-options -p -t "$mouse_pane" -v @ai_sidebar 2>/dev/null || true)"
[ "$is_sidebar" = "1" ] || exit 0

target="$(printf '%s\n' "$mouse_line" | sed -nE 's/^[[:space:]]*([0-9]+)\.([0-9]+).*/\1.\2/p')"
if [ -z "$target" ] && [ -n "$mouse_line" ]; then
  i=1
  while [ "$i" -le 200 ]; do
    stored_target="$(tmux show-options -p -t "$mouse_pane" -v "@ai_click_target_$i" 2>/dev/null || true)"
    [ -z "$stored_target" ] && break
    stored_line="$(tmux show-options -p -t "$mouse_pane" -v "@ai_click_line_$i" 2>/dev/null || true)"
    if [ "$stored_line" = "$mouse_line" ]; then
      target="$stored_target"
      line_no="$i"
      break
    fi
    i=$((i + 1))
  done
fi
if [ -z "$target" ]; then
  if [ -z "$mouse_y" ]; then
    mouse_y="$(tmux display-message -p '#{mouse_y}' 2>/dev/null || true)"
  fi
  [ -z "$mouse_y" ] && exit 0
  case "$mouse_y" in
    *[!0-9]*) exit 0 ;;
  esac
  line_no=$((mouse_y + 1))
  target="$(tmux display-message -p -t "$mouse_pane" "#{E:#{@ai_click_target_$line_no}}" 2>/dev/null || true)"
fi
[ -z "$target" ] && exit 0

target_pane="$target"
case "$target_pane" in
  %*) ;;
  ''|*[!0-9]*)
    session="$(tmux display-message -p -t "$mouse_pane" '#S' 2>/dev/null || true)"
    [ -z "$session" ] && exit 0
    win="${target%%.*}"
    display_index="${target#*.}"
    target_pane="$(
      tmux list-panes -t "$session:$win" -F '#{pane_id}	#{pane_index}	#{@ai_display_index}	#{@ai_sidebar}' 2>/dev/null \
        | awk -F '\t' -v idx="$display_index" '$4 != "1" && ($3 == idx || ($3 == "" && $2 == idx)) { print $1; exit }'
    )"
    ;;
  *)
    target_pane="%$target_pane"
    ;;
esac
[ -z "$target_pane" ] && exit 0
target_window="$(tmux display-message -p -t "$target_pane" '#{window_id}' 2>/dev/null || true)"
[ -z "$target_window" ] && exit 0

printf '%s mouse_pane=%s mouse_y=%s line_no=%s mouse_line=%s target=%s target_pane=%s\n' \
  "$(date '+%H:%M:%S')" "$mouse_pane" "$mouse_y" "$line_no" "$mouse_line" "$target" "$target_pane" >>"$log_file" 2>/dev/null || true

if [ "${AI_SIDEBAR_CLICK_DRY_RUN:-}" = "1" ]; then
  printf '%s\n' "$target_pane"
  exit 0
fi

tmux select-window -t "$target_window" 2>/dev/null || exit 0
tmux select-pane -t "$target_pane" 2>/dev/null || true
