#!/usr/bin/env bash
# agent 内部 primitive: 現在 pane の agmsg identity から同一 tmux window scope の peer へ送信する。
# ユーザー向け手順ではなく、controller workflow が structured request / reply を送るために使う。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

target=""
agent_type=""
to_spec=""
message=""
skill_dir="${AGMSG_SKILL_DIR:-$HOME/.agents/skills/agmsg}"

usage() {
  cat <<'EOF'
Usage: agmsg-tmux-send.sh --to <identity|window:pane|pane|left|right|up|down> <message...> [--type codex|claude-code] [--target <tmux-target>]

Internal primitive for controller/worker workflows. Send an agmsg message from
the current tmux pane identity to a peer in the same tmux window scope.
Do not present this command as a user-facing workflow step.
EOF
}

identity_for_pane() {
  local pane="$1"
  local type identity

  identity="$(agmsg_tmux_format "$pane" '#{@agmsg_active_identity}' 2>/dev/null || true)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  type="$(agmsg_tmux_detect_type "$pane" "")"
  agmsg_tmux_agent_name "$type" "$pane"
}

source_pane_for_target() {
  local source_target="$1"
  local pane

  pane="$(agmsg_tmux_source_pane_for_target "$source_target")" || return 1

  if [ -z "$pane" ]; then
    echo "ERROR: source pane could not be resolved from environment" >&2
    return 1
  fi
  printf '%s\n' "$pane"
}

pane_for_visible_location() {
  local source_target="$1"
  local wanted_window="$2"
  local wanted_pane="$3"
  local source_window source_window_index

  source_window="$(agmsg_tmux_format "$source_target" '#{window_id}' 2>/dev/null)"
  source_window_index="$(agmsg_tmux_format "$source_target" '#{window_index}' 2>/dev/null)"
  if [ -n "$wanted_window" ] && [ "$wanted_window" != "$source_window_index" ]; then
    return 1
  fi

  agmsg_tmux_cmd list-panes -t "$source_window" \
    -F '#{pane_index}	#{@ai_display_index}	#{pane_id}	#{@ai_sidebar}' 2>/dev/null |
    awk -F '\t' -v wanted_pane="$wanted_pane" '
      $4 != "1" {
        visible = ($2 != "" ? $2 : $1)
        if (visible == wanted_pane) {
          print $3
          exit
        }
      }
    '
}

pane_for_identity() {
  local source_target="$1"
  local identity="$2"
  local source_window

  source_window="$(agmsg_tmux_format "$source_target" '#{window_id}' 2>/dev/null)"
  agmsg_tmux_cmd list-panes -t "$source_window" \
    -F '#{pane_id}	#{@ai_sidebar}	#{@ai_app}	#{pane_current_command}	#{pane_title}	#{@agmsg_active_identity}' 2>/dev/null |
    awk -F '\t' -v identity="$identity" '$2 != "1" && $6 == identity { print $1; exit }'
}

pane_for_relative_direction() {
  local source_target="$1"
  local direction="$2"
  local source_pane source_window

  source_pane="$(agmsg_tmux_pane_id_for_target "$source_target")"
  source_window="$(agmsg_tmux_format "$source_target" '#{window_id}' 2>/dev/null)"
  agmsg_tmux_cmd list-panes -a \
    -F '#{window_id}	#{pane_id}	#{@ai_sidebar}	#{@ai_app}	#{pane_current_command}	#{pane_title}	#{pane_left}	#{pane_top}	#{pane_width}	#{pane_height}' 2>/dev/null |
    awk -F '\t' -v source_pane="$source_pane" -v source_window="$source_window" -v direction="$direction" '
      $1 == source_window {
        cx = $7 + ($9 / 2)
        cy = $8 + ($10 / 2)
        if ($2 == source_pane) {
          sx = cx
          sy = cy
          next
        }
        if ($3 == "1") {
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
        if (type == "") {
          next
        }
        pane[++n] = $2
        x[n] = cx
        y[n] = cy
      }
      END {
        if (sx == "" && sy == "") {
          exit
        }
        best = ""
        best_score = 999999999
        for (i = 1; i <= n; i++) {
          dx = x[i] - sx
          dy = y[i] - sy
          ok = 0
          if (direction == "right" && dx > 0) ok = 1
          if (direction == "left" && dx < 0) ok = 1
          if (direction == "down" && dy > 0) ok = 1
          if (direction == "up" && dy < 0) ok = 1
          if (!ok) next
          score = (dx * dx) + (dy * dy)
          if (score < best_score) {
            best_score = score
            best = pane[i]
          }
        }
        if (best != "") print best
      }
    '
}

resolve_to_identity() {
  local source_target="$1"
  local spec="$2"
  local pane wanted_window wanted_pane

  case "$spec" in
    left|right|up|down)
      pane="$(pane_for_relative_direction "$source_target" "$spec")"
      if [ -z "$pane" ]; then
        echo "ERROR: no AI pane found in direction: $spec" >&2
        return 1
      fi
      identity_for_pane "$pane"
      return 0
      ;;
    %*)
      if ! agmsg_tmux_format "$spec" '#{pane_id}' >/dev/null 2>&1; then
        echo "ERROR: tmux pane not found: $spec" >&2
        return 1
      fi
      if [ "$(agmsg_tmux_format "$spec" '#{window_id}' 2>/dev/null)" != "$(agmsg_tmux_format "$source_target" '#{window_id}' 2>/dev/null)" ]; then
        echo "ERROR: target pane is outside the source tmux window: $spec" >&2
        return 1
      fi
      identity_for_pane "$spec"
      return 0
      ;;
    *:*)
      wanted_window="${spec%%:*}"
      wanted_pane="${spec#*:}"
      pane="$(pane_for_visible_location "$source_target" "$wanted_window" "$wanted_pane")"
      if [ -z "$pane" ]; then
        echo "ERROR: pane location not found in current tmux server: $spec" >&2
        return 1
      fi
      identity_for_pane "$pane"
      return 0
      ;;
    *[!0-9]*)
      pane="$(pane_for_identity "$source_target" "$spec")"
      if [ -z "$pane" ]; then
        echo "ERROR: identity is not a peer in the source tmux window: $spec" >&2
        return 1
      fi
      printf '%s\n' "$spec"
      return 0
      ;;
    *)
      pane="$(pane_for_visible_location "$source_target" "" "$spec")"
      if [ -z "$pane" ]; then
        echo "ERROR: visible pane number not found in source tmux window: $spec" >&2
        return 1
      fi
      identity_for_pane "$pane"
      return 0
      ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --to)
      to_spec="${2:?--to requires an identity or pane reference}"
      shift 2
      ;;
    --type)
      agent_type="${2:?--type requires codex or claude-code}"
      shift 2
      ;;
    --target|-t)
      target="${2:?--target requires a tmux pane/window target}"
      shift 2
      ;;
    --skill-dir)
      skill_dir="${2:?--skill-dir requires a path}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      message="$*"
      break
      ;;
    -*)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      message="${message:+$message }$1"
      shift
      ;;
  esac
done

agmsg_tmux_require

if [ -z "$to_spec" ]; then
  echo "ERROR: --to is required" >&2
  usage >&2
  exit 1
fi
if [ -z "$message" ]; then
  echo "ERROR: message is required" >&2
  usage >&2
  exit 1
fi
if [ ! -x "$skill_dir/scripts/send.sh" ]; then
  echo "ERROR: agmsg send.sh is not installed at $skill_dir" >&2
  exit 1
fi

target="$(source_pane_for_target "$target")"

resolved_type="$(agmsg_tmux_detect_type "$target" "$agent_type")"
case "$resolved_type" in
  codex|claude-code) ;;
  *) echo "ERROR: unsupported agent type: $resolved_type" >&2; exit 1 ;;
esac

team="$(agmsg_tmux_team_for_target "$target")"
from_agent="$(agmsg_tmux_active_identity_for_target "$target" "$resolved_type")"
to_agent="$(resolve_to_identity "$target" "$to_spec")"

"$skill_dir/scripts/send.sh" "$team" "$from_agent" "$to_agent" "$message"
