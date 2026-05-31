#!/usr/bin/env bash
# agmsg unread 状態を read-only に集計し、tmux pane option へ反映する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=.config/tmux/agmsg-tmux-lib.sh
. "$SCRIPT_DIR/agmsg-tmux-lib.sh"

skill_dir="${AGMSG_SKILL_DIR:-$HOME/.agents/skills/agmsg}"
db="$skill_dir/db/messages.db"
sep=$'\037'

sql_escape() {
  printf '%s' "$1" | sed "s/'/''/g"
}

clear_pane_notice() {
  local pane="$1"
  agmsg_tmux_cmd set-option -p -t "$pane" @agmsg_unread_count "" 2>/dev/null || true
  agmsg_tmux_cmd set-option -p -t "$pane" @agmsg_unread_summary "" 2>/dev/null || true
}

agmsg_tmux_require

if [ ! -f "$db" ]; then
  while IFS="$sep" read -r pane_id is_sidebar; do
    [ -z "$pane_id" ] && continue
    [ "$is_sidebar" = "1" ] && continue
    clear_pane_notice "$pane_id"
  done < <(agmsg_tmux_cmd list-panes -a -F "#{pane_id}${sep}#{@ai_sidebar}" 2>/dev/null)
  exit 0
fi

while IFS="$sep" read -r pane_id is_sidebar ai_app command_name pane_title identity; do
  [ -z "$pane_id" ] && continue
  if [ "$is_sidebar" = "1" ] || [ -z "$identity" ]; then
    clear_pane_notice "$pane_id"
    continue
  fi

  case "$ai_app $command_name $pane_title" in
    *codex*|*claude*|*Context\ *%\ used*) ;;
    *) clear_pane_notice "$pane_id"; continue ;;
  esac

  team="$(agmsg_tmux_team_for_target "$pane_id" 2>/dev/null || true)"
  if [ -z "$team" ]; then
    clear_pane_notice "$pane_id"
    continue
  fi

  team_esc="$(sql_escape "$team")"
  identity_esc="$(sql_escape "$identity")"
  row="$(sqlite3 "$db" "
    SELECT count(*) || char(9) || COALESCE(group_concat(from_agent, ','), '')
    FROM (
      SELECT from_agent
      FROM messages
      WHERE team='$team_esc' AND to_agent='$identity_esc' AND read_at IS NULL
      ORDER BY id DESC
      LIMIT 3
    );
  " 2>/dev/null || true)"
  count="${row%%$'\t'*}"
  from_list="${row#*$'\t'}"
  case "$count" in ''|*[!0-9]*) count=0 ;; esac
  if [ "$count" -le 0 ]; then
    clear_pane_notice "$pane_id"
    continue
  fi

  [ "$from_list" = "$row" ] && from_list=""
  from_list="${from_list:-unknown}"
  summary="$identity !$count from $from_list"
  agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_unread_count "$count" 2>/dev/null || true
  agmsg_tmux_cmd set-option -p -t "$pane_id" @agmsg_unread_summary "$summary" 2>/dev/null || true
done < <(
  agmsg_tmux_cmd list-panes -a \
    -F "#{pane_id}${sep}#{@ai_sidebar}${sep}#{@ai_app}${sep}#{pane_current_command}${sep}#{pane_title}${sep}#{@agmsg_active_identity}" 2>/dev/null
)
