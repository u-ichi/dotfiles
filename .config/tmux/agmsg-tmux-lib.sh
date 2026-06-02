#!/usr/bin/env bash
# agmsg の到達範囲を tmux window に束ねるための共通関数。
set -u

agmsg_tmux_cmd() {
  if [ -n "${AGMSG_TMUX_SOCKET:-}" ]; then
    command tmux -S "$AGMSG_TMUX_SOCKET" "$@"
  else
    command tmux "$@"
  fi
}

agmsg_tmux_require() {
  if ! command -v tmux >/dev/null 2>&1; then
    echo "ERROR: tmux is not installed" >&2
    return 1
  fi
  if [ -z "${TMUX:-}" ] \
      && [ -z "${AGMSG_TMUX_SOCKET:-}" ] \
      && ! agmsg_tmux_current_pane_id >/dev/null 2>&1; then
    echo "ERROR: not running inside tmux" >&2
    return 1
  fi
}

agmsg_tmux_current_pane_id() {
  local pid ppid ancestors pane

  if [ -n "${AGMSG_TMUX_CURRENT_PANE:-}" ]; then
    printf '%s\n' "$AGMSG_TMUX_CURRENT_PANE"
    return 0
  fi

  if [ -n "${TMUX_PANE:-}" ]; then
    printf '%s\n' "$TMUX_PANE"
    return 0
  fi

  pid="$$"
  ancestors=" $pid "
  while [ -n "$pid" ] && [ "$pid" != "1" ]; do
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')"
    [ -n "$ppid" ] || break
    ancestors="${ancestors}${ppid} "
    pid="$ppid"
  done

  pane="$(
    agmsg_tmux_cmd list-panes -a -F '#{pane_id}	#{pane_pid}' 2>/dev/null |
      awk -F '\t' -v ancestors="$ancestors" 'index(ancestors, " " $2 " ") { print $1; exit }'
  )"
  if [ -n "$pane" ]; then
    printf '%s\n' "$pane"
    return 0
  fi

  return 1
}

agmsg_tmux_format() {
  local target="${1:-}"
  local format="$2"

  if [ -z "$target" ]; then
    target="$(agmsg_tmux_current_pane_id 2>/dev/null || true)"
  fi

  if [ -n "$target" ]; then
    agmsg_tmux_cmd display-message -p -t "$target" "$format"
  else
    agmsg_tmux_cmd display-message -p "$format"
  fi
}

agmsg_tmux_hash() {
  if command -v shasum >/dev/null 2>&1; then
    printf '%s' "$1" | shasum -a 256 | awk '{ print substr($1, 1, 12) }'
  elif command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{ print substr($1, 1, 12) }'
  else
    printf '%s' "$1" | cksum | awk '{ print $1 }'
  fi
}

agmsg_tmux_team_for_target() {
  local target="${1:-}"
  local socket_path session_id window_id socket_hash

  socket_path="$(agmsg_tmux_format "$target" '#{socket_path}' 2>/dev/null || true)"
  session_id="$(agmsg_tmux_format "$target" '#{session_id}' 2>/dev/null || true)"
  window_id="$(agmsg_tmux_format "$target" '#{window_id}' 2>/dev/null || true)"

  if [ -z "$socket_path" ] || [ -z "$session_id" ] || [ -z "$window_id" ]; then
    echo "ERROR: failed to resolve tmux socket/session/window" >&2
    return 1
  fi

  socket_hash="$(agmsg_tmux_hash "$socket_path")"
  printf 'tmux:%s:%s:%s\n' "$socket_hash" "$session_id" "$window_id"
}

agmsg_tmux_pane_id_for_target() {
  local target="${1:-}"
  agmsg_tmux_format "$target" '#{pane_id}' 2>/dev/null
}

agmsg_tmux_source_pane_for_target() {
  local source_target="${1:-}"
  local bound_source bound_pane requested_pane

  # AI CLI wrappers export AGMSG_TMUX_CURRENT_PANE at process start. Treat it
  # as the source-of-truth for this agent's tmux window. If the model passes a
  # stale explicit target from another window, fail closed instead of silently
  # sending in the wrong scope.
  bound_source="${AGMSG_TMUX_CURRENT_PANE:-${TMUX_PANE:-}}"
  if [ -z "$bound_source" ]; then
    bound_source="$(agmsg_tmux_current_pane_id 2>/dev/null || true)"
  fi

  if [ -n "$bound_source" ]; then
    bound_pane="$(agmsg_tmux_pane_id_for_target "$bound_source" 2>/dev/null || true)"
    if [ -z "$bound_pane" ]; then
      echo "ERROR: current tmux source pane could not be resolved: $bound_source" >&2
      return 1
    fi
    if [ -n "$source_target" ]; then
      requested_pane="$(agmsg_tmux_pane_id_for_target "$source_target" 2>/dev/null || true)"
      if [ -z "$requested_pane" ]; then
        echo "ERROR: source pane could not be resolved: $source_target" >&2
        return 1
      fi
      if [ "$requested_pane" != "$bound_pane" ]; then
        echo "ERROR: source target $source_target resolves to $requested_pane but this agent is bound to $bound_pane via AGMSG_TMUX_CURRENT_PANE" >&2
        return 1
      fi
    fi
    printf '%s\n' "$bound_pane"
    return 0
  fi

  if [ -n "$source_target" ]; then
    agmsg_tmux_pane_id_for_target "$source_target" 2>/dev/null
    return
  fi

  if [ -n "${TMUX_PANE:-}" ]; then
    agmsg_tmux_pane_id_for_target "$TMUX_PANE" 2>/dev/null
    return
  fi

  echo "ERROR: source pane is required; pass --target or set AGMSG_TMUX_CURRENT_PANE/TMUX_PANE" >&2
  return 1
}

agmsg_tmux_detect_type() {
  local target="${1:-}"
  local explicit="${2:-}"
  local app command title

  case "$explicit" in
    codex|claude-code) printf '%s\n' "$explicit"; return 0 ;;
    "") ;;
    *) echo "ERROR: unknown agent type: $explicit" >&2; return 1 ;;
  esac

  app="$(agmsg_tmux_format "$target" '#{@ai_app}' 2>/dev/null || true)"
  case "$app" in
    codex) printf 'codex\n'; return 0 ;;
    claude|claude-code) printf 'claude-code\n'; return 0 ;;
  esac

  command="$(agmsg_tmux_format "$target" '#{pane_current_command}' 2>/dev/null || true)"
  title="$(agmsg_tmux_format "$target" '#{pane_title}' 2>/dev/null || true)"
  case "$command $title" in
    *codex*) printf 'codex\n'; return 0 ;;
    *claude*) printf 'claude-code\n'; return 0 ;;
  esac

  echo "ERROR: failed to detect agent type; pass --type codex or --type claude-code" >&2
  return 1
}

agmsg_tmux_agent_name() {
  local type="$1"
  local pane_id="$2"
  printf '%s-%s\n' "$type" "$pane_id"
}

agmsg_tmux_set_active_identity() {
  local target="${1:-}"
  local identity="$2"
  if [ -n "$target" ]; then
    agmsg_tmux_cmd set-option -p -t "$target" @agmsg_active_identity "$identity"
  else
    agmsg_tmux_cmd set-option -p @agmsg_active_identity "$identity"
  fi
}

agmsg_tmux_set_display_identity() {
  local target="${1:-}"
  local identity="$2"
  if [ -n "$target" ]; then
    agmsg_tmux_cmd set-option -p -t "$target" @agmsg_display_identity "$identity"
  else
    agmsg_tmux_cmd set-option -p @agmsg_display_identity "$identity"
  fi
}

agmsg_tmux_set_identity_source() {
  local target="${1:-}"
  local source="$2"
  if [ -n "$target" ]; then
    agmsg_tmux_cmd set-option -p -t "$target" @agmsg_identity_source "$source"
  else
    agmsg_tmux_cmd set-option -p @agmsg_identity_source "$source"
  fi
}

agmsg_tmux_identity_namespace() {
  local identity="$1"
  case "$identity" in
    controller[0-9]*) printf 'controller\n' ;;
    worker[0-9]*) printf 'worker\n' ;;
    reviewer[0-9]*) printf 'reviewer\n' ;;
    *) printf '%s\n' "$identity" ;;
  esac
}

agmsg_tmux_window_has_controller_identity() {
  local window_id="$1"
  local target_pane="${2:-}"

  agmsg_tmux_cmd list-panes -a \
    -F '#{window_id}	#{pane_id}	#{@ai_sidebar}	#{@agmsg_active_identity}' 2>/dev/null |
    awk -F '\t' -v target_window="$window_id" -v target_pane="$target_pane" '
      $1 == target_window && $2 != target_pane && $3 != "1" && $4 ~ /^controller[0-9]+$/ {
        found = 1
      }
      END { if (found) print "1"; else print "0" }
    '
}

agmsg_tmux_next_worker_identity_for_window() {
  local window_id="$1"
  local current max_existing next

  current="$(agmsg_tmux_cmd show-option -wqv -t "$window_id" @agmsg_next_worker_seq 2>/dev/null || true)"
  case "$current" in
    ''|*[!0-9]*) current=1 ;;
  esac

  max_existing="$(
    agmsg_tmux_cmd list-panes -a \
      -F '#{window_id}	#{@ai_sidebar}	#{@agmsg_active_identity}' 2>/dev/null |
      awk -F '\t' -v target_window="$window_id" '
        $1 == target_window && $2 != "1" && $3 ~ /^worker[0-9]+$/ {
          n = substr($3, 7) + 0
          if (n > max) max = n
        }
        END { print max + 0 }
      '
  )"
  next="$current"
  if [ "$next" -le "$max_existing" ]; then
    next=$((max_existing + 1))
  fi

  agmsg_tmux_cmd set-option -w -t "$window_id" @agmsg_next_worker_seq "$((next + 1))" >/dev/null
  printf 'worker%s\n' "$next"
}

agmsg_tmux_initial_identity_for_target() {
  local target="${1:-}"
  local type="$2"
  local pane_id window_id identity has_controller

  pane_id="$(agmsg_tmux_pane_id_for_target "$target")"
  window_id="$(agmsg_tmux_format "$target" '#{window_id}' 2>/dev/null)"

  identity="$(agmsg_tmux_format "$target" '#{@agmsg_active_identity}' 2>/dev/null || true)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  has_controller="$(agmsg_tmux_window_has_controller_identity "$window_id" "$pane_id")"
  if [ "$has_controller" != "1" ]; then
    printf 'controller1\n'
  elif [ "$type" = "codex" ] || [ "$type" = "claude-code" ]; then
    agmsg_tmux_next_worker_identity_for_window "$window_id"
  else
    agmsg_tmux_agent_name "$type" "$pane_id"
  fi
}

agmsg_tmux_active_identity_for_target() {
  local target="${1:-}"
  local explicit_type="${2:-}"
  local identity type pane_id

  identity="$(agmsg_tmux_format "$target" '#{@agmsg_active_identity}' 2>/dev/null || true)"
  if [ -n "$identity" ]; then
    printf '%s\n' "$identity"
    return 0
  fi

  type="$(agmsg_tmux_detect_type "$target" "$explicit_type")"
  pane_id="$(agmsg_tmux_pane_id_for_target "$target")"
  agmsg_tmux_agent_name "$type" "$pane_id"
}
