#!/usr/bin/env bash
# 現在 pane の agmsg active identity を切り替える。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

target=""
agent_type=""
project_path=""
skill_dir="${AGMSG_SKILL_DIR:-$HOME/.agents/skills/agmsg}"

usage() {
  cat <<'EOF'
Usage: agmsg-tmux-actas.sh <identity> [--type codex|claude-code] [--project-path <path>] [--target <tmux-target>]

Register the identity in the current tmux window agmsg team and set it as the
active identity displayed by tmux. Use namespace + number names such as
controller1, worker1, worker2, or reviewer1.
EOF
}

identity=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --type)
      agent_type="${2:?--type requires codex or claude-code}"
      shift 2
      ;;
    --project-path)
      project_path="${2:?--project-path requires a path}"
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
    -*)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [ -n "$identity" ]; then
        echo "ERROR: identity is already specified: $identity" >&2
        usage >&2
        exit 1
      fi
      identity="$1"
      shift
      ;;
  esac
done

if [ -z "$identity" ]; then
  echo "ERROR: identity is required" >&2
  usage >&2
  exit 1
fi
case "$identity" in
  controller[0-9]*|worker[0-9]*|reviewer[0-9]*) ;;
  *)
    echo "ERROR: identity must be controllerN, workerN, or reviewerN: $identity" >&2
    exit 1
    ;;
esac

agmsg_tmux_require

if [ ! -x "$skill_dir/scripts/join.sh" ]; then
  echo "ERROR: agmsg join.sh is not installed at $skill_dir" >&2
  exit 1
fi

resolved_type="$(agmsg_tmux_detect_type "$target" "$agent_type")"
case "$resolved_type" in
  codex|claude-code) ;;
  *) echo "ERROR: unsupported agent type: $resolved_type" >&2; exit 1 ;;
esac

team="$(agmsg_tmux_team_for_target "$target")"
if [ -z "$project_path" ]; then
  project_path="$(agmsg_tmux_format "$target" '#{pane_current_path}' 2>/dev/null || pwd)"
fi

"$skill_dir/scripts/join.sh" "$team" "$identity" "$resolved_type" "$project_path"
agmsg_tmux_set_active_identity "$target" "$identity"
agmsg_tmux_set_display_identity "$target" "$identity"
agmsg_tmux_set_identity_source "$target" "manual"

printf 'agmsg tmux actas: team=%s identity=%s type=%s project=%s\n' \
  "$team" "$identity" "$resolved_type" "$project_path"
