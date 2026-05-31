#!/usr/bin/env bash
# 同一 tmux window 内の agmsg peer 候補を表示する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

target=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --target|-t)
      target="${2:?--target requires a tmux pane/window target}"
      shift 2
      ;;
    --help|-h)
      echo "Usage: agmsg-tmux-peers.sh [--target <tmux-target>]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

agmsg_tmux_require

source_pane_for_target() {
  local source_target="$1"
  local pane

  pane="$(agmsg_tmux_source_pane_for_target "$source_target")" || return 1

  if [ -z "$pane" ]; then
    echo "ERROR: source pane could not be resolved" >&2
    return 1
  fi
  printf '%s\n' "$pane"
}

target="$(source_pane_for_target "$target")"
window_id="$(agmsg_tmux_format "$target" '#{window_id}' 2>/dev/null)"
team="$(agmsg_tmux_team_for_target "$target")"

printf 'team\tloc\tidentity\tpane\ttype\tpath\n'
agmsg_tmux_cmd list-panes -a \
  -F '#{window_id}	#{window_index}	#{pane_index}	#{@ai_display_index}	#{pane_id}	#{@ai_sidebar}	#{@ai_app}	#{pane_current_command}	#{pane_title}	#{pane_current_path}	#{@agmsg_active_identity}' 2>/dev/null \
  | awk -F '\t' -v target_window="$window_id" -v team="$team" '
      $1 == target_window && $6 != "1" {
        type = ""
        loc = $2 ":" ($4 != "" ? $4 : $3)
        if ($7 == "codex") {
          type = "codex"
        } else if ($7 == "claude" || $7 == "claude-code") {
          type = "claude-code"
        } else if (($8 " " $9) ~ /codex/) {
          type = "codex"
        } else if (($8 " " $9) ~ /claude/) {
          type = "claude-code"
        }
        if (type != "") {
          identity = $11
          if (identity == "") {
            identity = type "-" $5
          }
          printf "%s\t%s\t%s\t%s\t%s\t%s\n", team, loc, identity, $5, type, $10
        }
      }
    '
