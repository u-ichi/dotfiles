#!/usr/bin/env bash
# 現在 pane を tmux window scope の agmsg team に参加させる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

target=""
agent_type=""
mode=""
project_path=""
skip_delivery=0
skill_dir="${AGMSG_SKILL_DIR:-$HOME/.agents/skills/agmsg}"

usage() {
  cat <<'EOF'
Usage: agmsg-tmux-join.sh [--type codex|claude-code] [--mode turn|monitor|both|off] [--project-path <path>] [--skip-delivery] [--target <tmux-target>]

Join the current tmux pane to the agmsg team derived from the current tmux window.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)
      agent_type="${2:?--type requires codex or claude-code}"
      shift 2
      ;;
    --mode)
      mode="${2:?--mode requires turn, monitor, both, or off}"
      shift 2
      ;;
    --project-path)
      project_path="${2:?--project-path requires a path}"
      shift 2
      ;;
    --skip-delivery)
      skip_delivery=1
      shift
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
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

agmsg_tmux_require

if [ ! -x "$skill_dir/scripts/join.sh" ] || [ ! -x "$skill_dir/scripts/delivery.sh" ]; then
  echo "ERROR: agmsg is not installed at $skill_dir" >&2
  echo "Install agmsg first; this wrapper never installs it automatically." >&2
  exit 1
fi

resolved_type="$(agmsg_tmux_detect_type "$target" "$agent_type")"
case "$resolved_type" in
  codex|claude-code) ;;
  *) echo "ERROR: unsupported agent type: $resolved_type" >&2; exit 1 ;;
esac

case "$mode" in
  "") if [ "$resolved_type" = "codex" ]; then mode="turn"; else mode="monitor"; fi ;;
  turn|monitor|both|off) ;;
  *) echo "ERROR: unknown delivery mode: $mode" >&2; exit 1 ;;
esac

if [ "$resolved_type" = "codex" ] && { [ "$mode" = "monitor" ] || [ "$mode" = "both" ]; }; then
  echo "ERROR: Codex supports only agmsg delivery mode 'turn' or 'off'" >&2
  exit 1
fi

team="$(agmsg_tmux_team_for_target "$target")"
pane_id="$(agmsg_tmux_pane_id_for_target "$target")"
identity="$(agmsg_tmux_initial_identity_for_target "$target" "$resolved_type")"
if [ -z "$project_path" ]; then
  project_path="$(agmsg_tmux_format "$target" '#{pane_current_path}' 2>/dev/null || pwd)"
fi

"$skill_dir/scripts/join.sh" "$team" "$identity" "$resolved_type" "$project_path"
agmsg_tmux_set_active_identity "$target" "$identity"
agmsg_tmux_set_display_identity "$target" "$identity"
agmsg_tmux_set_identity_source "$target" "auto"
if [ "$skip_delivery" -ne 1 ]; then
  "$skill_dir/scripts/delivery.sh" set "$mode" "$resolved_type" "$project_path"
fi

if [ "$skip_delivery" -eq 1 ]; then
  printf 'agmsg tmux scope joined: team=%s identity=%s type=%s mode=skipped project=%s\n' \
    "$team" "$identity" "$resolved_type" "$project_path"
else
  printf 'agmsg tmux scope joined: team=%s identity=%s type=%s mode=%s project=%s\n' \
    "$team" "$identity" "$resolved_type" "$mode" "$project_path"
fi
