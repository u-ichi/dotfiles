#!/usr/bin/env bash
# 現在 pane が属する tmux window scope の agmsg team 名を出力する。
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
      echo "Usage: agmsg-tmux-team.sh [--target <tmux-target>]"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

agmsg_tmux_require
agmsg_tmux_team_for_target "$target"
