#!/usr/bin/env bash
# AI pane の active identity が空なら初期 identity を補う。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

target="${1:-}"

agmsg_tmux_require

window_filter=""
if [ -n "$target" ]; then
  window_filter="$(agmsg_tmux_format "$target" '#{window_id}' 2>/dev/null || true)"
fi

while IFS=$'\t' read -r pane_id identity; do
  [ -n "$pane_id" ] || continue
  if [ "$identity" = "__clear__" ]; then
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_active_identity "" 2>/dev/null || true
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_display_identity "" 2>/dev/null || true
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_identity_source "" 2>/dev/null || true
  else
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_active_identity "$identity" 2>/dev/null || true
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_display_identity "$identity" 2>/dev/null || true
    agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_identity_source "auto" 2>/dev/null || true
  fi
done < <(
  agmsg_tmux_cmd list-panes -a \
    -F '#{window_id}	#{pane_id}	#{@ai_sidebar}	#{@ai_app}	#{pane_current_command}	#{pane_title}	#{@agmsg_active_identity}	#{@agmsg_identity_source}' 2>/dev/null |
    awk -F '\t' -v window_filter="$window_filter" '
      window_filter == "" || $1 == window_filter {
        if ($3 == "1") {
          print $2 "\t__clear__"
          next
        }
        type = ""
        if ($4 == "codex") {
          type = "codex"
        } else if ($4 == "claude" || $4 == "claude-code") {
          type = "claude-code"
        } else if (($5 " " $6) ~ /codex/) {
          type = "codex"
        } else if (($5 " " $6) ~ /claude/) {
          type = "claude-code"
        }
        if (type != "") {
          pane_count[$1] += 1
          if (pane_count[$1] == 1) {
            identity = "controller1"
          } else if (pane_count[$1] >= 2) {
            identity = "worker" (pane_count[$1] - 1)
          } else {
            identity = type "-" $2
          }
          if ($8 == "manual") {
            next
          }
          print $2 "\t" identity
        }
      }
    '
)
