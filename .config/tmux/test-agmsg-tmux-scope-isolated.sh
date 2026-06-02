#!/usr/bin/env bash
# agmsg tmux window scope helper を専用 socket の disposable server だけで検証する。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_BASE="${TMPDIR:-/tmp}"
SOCKET_DIR="$(mktemp -d "$TMP_BASE/agmsg-tmux-scope-test.XXXXXX")"
SOCKET="$SOCKET_DIR/socket"
TEST_HOME="$SOCKET_DIR/home"
PROJECT_A="$SOCKET_DIR/project-a"
PROJECT_B="$SOCKET_DIR/project-b"
PROJECT_C="$SOCKET_DIR/project-c"
FAKE_SKILL="$SOCKET_DIR/agmsg"
CALL_LOG="$SOCKET_DIR/agmsg-calls.log"

cleanup() {
  command tmux -S "$SOCKET" kill-server >/dev/null 2>&1 || true
  rm -rf "$SOCKET_DIR"
}
trap cleanup EXIT

tmux_i() {
  command tmux -S "$SOCKET" "$@"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "SKIP: $1 is not installed" >&2
    exit 0
  fi
}

make_fake_agmsg() {
  mkdir -p "$FAKE_SKILL/scripts"
  cat > "$FAKE_SKILL/scripts/join.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'join\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "${AGMSG_TEST_CALL_LOG:?}"
EOF
  cat > "$FAKE_SKILL/scripts/delivery.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" != "set" ]; then
  echo "unexpected delivery action: $1" >&2
  exit 1
fi
printf 'delivery\t%s\t%s\t%s\n' "$2" "$3" "$4" >> "${AGMSG_TEST_CALL_LOG:?}"
EOF
  cat > "$FAKE_SKILL/scripts/send.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'send\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "${AGMSG_TEST_CALL_LOG:?}"
EOF
  chmod 755 "$FAKE_SKILL/scripts/join.sh" "$FAKE_SKILL/scripts/delivery.sh" "$FAKE_SKILL/scripts/send.sh"
}

require_command tmux
require_command fish
require_command sqlite3

mkdir -p "$TEST_HOME" "$PROJECT_A" "$PROJECT_B" "$PROJECT_C"
PROJECT_A="$(cd "$PROJECT_A" && pwd -P)"
PROJECT_B="$(cd "$PROJECT_B" && pwd -P)"
PROJECT_C="$(cd "$PROJECT_C" && pwd -P)"
make_fake_agmsg
mkdir -p "$FAKE_SKILL/db"
sqlite3 "$FAKE_SKILL/db/messages.db" <<'SQL'
CREATE TABLE messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  team TEXT NOT NULL,
  from_agent TEXT NOT NULL,
  to_agent TEXT NOT NULL,
  body TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  read_at TEXT
);
CREATE INDEX idx_unread ON messages(team, to_agent, read_at) WHERE read_at IS NULL;
SQL
export HOME="$TEST_HOME"
export TERM=xterm-256color
export AGMSG_TMUX_SOCKET="$SOCKET"
export AGMSG_SKILL_DIR="$FAKE_SKILL"
export AGMSG_TEST_CALL_LOG="$CALL_LOG"
mkdir -p "$TEST_HOME/.config"
ln -s "$SCRIPT_DIR" "$TEST_HOME/.config/tmux"

tmux_i new-session -d -s agmsg-scope-test -n first -c "$PROJECT_A" 'sleep 60'
tmux_i source-file "$SCRIPT_DIR/tmux.conf" >/dev/null
tmux_i move-window -r >/dev/null
first_window="$(tmux_i display-message -p -t 'agmsg-scope-test:first' '#{window_id}')"
first_session="$(tmux_i display-message -p -t "$first_window" '#{session_id}')"
first_pane="$(tmux_i list-panes -t "$first_window" -F '#{pane_id}' | head -1)"
tmux_i set-option -p -t "$first_pane" @ai_app codex

team_first="$("$SCRIPT_DIR/agmsg-tmux-team.sh" --target "$first_pane")"
expected_team_suffix=":$first_session:$first_window"
if [ "${team_first#tmux:}" = "$team_first" ] || [ "${team_first%"$expected_team_suffix"}" = "$team_first" ]; then
  echo "ERROR: unexpected first window team: $team_first" >&2
  exit 1
fi
if printf '%s\n' "$team_first" | grep -q '/'; then
  echo "ERROR: team contains raw socket path: $team_first" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$first_pane" >/dev/null
expected_join_codex=$'join\t'"$team_first"$'\t''controller1'$'\t''codex'$'\t'"$PROJECT_A"
expected_delivery_codex=$'delivery\tturn\tcodex\t'"$PROJECT_A"
if ! grep -Fqx "$expected_join_codex" "$CALL_LOG"; then
  echo "ERROR: codex join call was not recorded as expected" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if ! grep -Fqx "$expected_delivery_codex" "$CALL_LOG"; then
  echo "ERROR: codex delivery mode was not turn" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$first_pane" @agmsg_active_identity)" != "controller1" ]; then
  echo "ERROR: codex join did not set active identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$first_pane" @agmsg_display_identity)" != "controller1" ]; then
  echo "ERROR: codex join did not set display identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$first_pane" @agmsg_identity_source)" != "auto" ]; then
  echo "ERROR: codex join did not mark identity source as auto" >&2
  exit 1
fi

second_pane="$(tmux_i split-window -t "$first_pane" -c "$PROJECT_B" -P -F '#{pane_id}' 'sleep 60')"
tmux_i set-option -p -t "$second_pane" @ai_app claude
tmux_i select-pane -t "$second_pane" -T "agent | fake-session | Context 1% used"
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$second_pane" >/dev/null
expected_join_claude=$'join\t'"$team_first"$'\t''worker1'$'\t''claude-code'$'\t'"$PROJECT_B"
expected_delivery_claude=$'delivery\tmonitor\tclaude-code\t'"$PROJECT_B"
if ! grep -Fqx "$expected_join_claude" "$CALL_LOG"; then
  echo "ERROR: claude-code join call was not recorded in the same team" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if ! grep -Fqx "$expected_delivery_claude" "$CALL_LOG"; then
  echo "ERROR: claude-code delivery mode was not monitor" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_active_identity)" != "worker1" ]; then
  echo "ERROR: claude-code join did not set active identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_display_identity)" != "worker1" ]; then
  echo "ERROR: claude-code join did not set display identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_identity_source)" != "auto" ]; then
  echo "ERROR: claude-code join did not mark identity source as auto" >&2
  exit 1
fi

third_worker_pane="$(tmux_i split-window -t "$second_pane" -c "$PROJECT_C" -P -F '#{pane_id}' 'sleep 60')"
tmux_i set-option -p -t "$third_worker_pane" @ai_app codex
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$third_worker_pane" >/dev/null
expected_join_third_worker=$'join\t'"$team_first"$'\t''worker2'$'\t''codex'$'\t'"$PROJECT_C"
if ! grep -Fqx "$expected_join_third_worker" "$CALL_LOG"; then
  echo "ERROR: third pane was not joined as worker" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "worker2" ]; then
  echo "ERROR: third pane active identity was not worker" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_display_identity)" != "worker2" ]; then
  echo "ERROR: third pane display identity was not worker" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_identity_source)" != "auto" ]; then
  echo "ERROR: third pane identity source was not auto" >&2
  exit 1
fi
inserted_worker_pane="$(tmux_i split-window -b -t "$second_pane" -c "$PROJECT_C" -P -F '#{pane_id}' 'sleep 60')"
tmux_i set-option -p -t "$inserted_worker_pane" @ai_app codex
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$inserted_worker_pane" >/dev/null
worker1_count="$(
  tmux_i list-panes -t "$first_window" \
    -F '#{@agmsg_active_identity}	#{@agmsg_identity_source}' |
    awk -F '\t' '$1 == "worker1" && $2 == "auto" { count += 1 } END { print count + 0 }'
)"
if [ "$worker1_count" != "1" ]; then
  echo "ERROR: auto identity join left duplicate worker1 identities" >&2
  tmux_i list-panes -t "$first_window" -F '#{pane_id}	#{@ai_app}	#{@agmsg_active_identity}	#{@agmsg_identity_source}' >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$inserted_worker_pane" @agmsg_active_identity)" != "worker3" ]; then
  echo "ERROR: inserted worker pane should get the next stable worker identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_active_identity)" != "worker1" ]; then
  echo "ERROR: existing worker1 pane was renamed after inserted worker join" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "worker2" ]; then
  echo "ERROR: existing worker2 pane was renamed after inserted worker join" >&2
  exit 1
fi
tmux_i kill-pane -t "$inserted_worker_pane"
"$SCRIPT_DIR/agmsg-tmux-sync-active-identity.sh" "$first_pane"
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_active_identity)" != "worker1" ]; then
  echo "ERROR: identity sync renamed worker1 after removing inserted pane" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "worker2" ]; then
  echo "ERROR: identity sync renamed worker2 after removing inserted pane" >&2
  exit 1
fi
tmux_i set-option -p -t "$third_worker_pane" @agmsg_active_identity worker3
tmux_i set-option -p -t "$third_worker_pane" @agmsg_display_identity worker3
"$SCRIPT_DIR/agmsg-tmux-sync-active-identity.sh" "$first_pane"
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "worker3" ]; then
  echo "ERROR: auto identity sync renamed an existing worker identity" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_display_identity)" != "worker3" ]; then
  echo "ERROR: auto display identity sync renamed an existing worker identity" >&2
  exit 1
fi

skip_project="$SOCKET_DIR/skip-project"
mkdir -p "$skip_project"
skip_project="$(cd "$skip_project" && pwd -P)"
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$second_pane" --project-path "$skip_project" --skip-delivery >/dev/null
expected_join_skip=$'join\t'"$team_first"$'\t''worker1'$'\t''claude-code'$'\t'"$skip_project"
if ! grep -Fqx "$expected_join_skip" "$CALL_LOG"; then
  echo "ERROR: skip-delivery join with explicit project path was not recorded" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if grep -Fqx $'delivery\tmonitor\tclaude-code\t'"$skip_project" "$CALL_LOG"; then
  echo "ERROR: --skip-delivery still wrote a delivery call" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

peers="$("$SCRIPT_DIR/agmsg-tmux-peers.sh" --target "$first_pane")"
first_visible="$(tmux_i display-message -p -t "$first_pane" '#{?#{==:#{@ai_display_index},},#{pane_index},#{@ai_display_index}}')"
second_visible="$(tmux_i display-message -p -t "$second_pane" '#{?#{==:#{@ai_display_index},},#{pane_index},#{@ai_display_index}}')"
third_worker_visible="$(tmux_i display-message -p -t "$third_worker_pane" '#{?#{==:#{@ai_display_index},},#{pane_index},#{@ai_display_index}}')"
first_loc="$(tmux_i display-message -p -t "$first_pane" '#{window_index}'):$first_visible"
second_loc="$(tmux_i display-message -p -t "$second_pane" '#{window_index}'):$second_visible"
third_worker_loc="$(tmux_i display-message -p -t "$third_worker_pane" '#{window_index}'):$third_worker_visible"
expected_peer_codex=$'\t'"$first_loc"$'\t''controller1'$'\t'"$first_pane"$'\t''codex'$'\t'"$PROJECT_A"
expected_peer_claude=$'\t'"$second_loc"$'\t''worker1'$'\t'"$second_pane"$'\t''claude-code'$'\t'"$PROJECT_B"
expected_peer_third_worker=$'\t'"$third_worker_loc"$'\t''worker3'$'\t'"$third_worker_pane"$'\t''codex'$'\t'"$PROJECT_C"
if ! printf '%s\n' "$peers" | grep -Fq "$expected_peer_codex"; then
  echo "ERROR: codex peer was not listed" >&2
  printf '%s\n' "$peers" >&2
  exit 1
fi
if ! printf '%s\n' "$peers" | grep -Fq "$expected_peer_claude"; then
  echo "ERROR: claude-code peer was not listed" >&2
  printf '%s\n' "$peers" >&2
  exit 1
fi
if ! printf '%s\n' "$peers" | grep -Fq "$expected_peer_third_worker"; then
  echo "ERROR: third worker peer was not listed" >&2
  printf '%s\n' "$peers" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "$second_loc" "hello from isolated test" >/dev/null
expected_send=$'send\t'"$team_first"$'\t''controller1'$'\t''worker1'$'\t''hello from isolated test'
if ! grep -Fqx "$expected_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not send from current pane identity" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to worker1 "hello via worker name" >/dev/null
expected_worker_name_send=$'send\t'"$team_first"$'\t''controller1'$'\t''worker1'$'\t''hello via worker name'
if ! grep -Fqx "$expected_worker_name_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve worker1 identity by name" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "$second_loc" "hello via visible location" >/dev/null
expected_loc_send=$'send\t'"$team_first"$'\t''controller1'$'\t''worker1'$'\t''hello via visible location'
if ! grep -Fqx "$expected_loc_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve visible location to active identity" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "$second_visible" "hello via visible pane number" >/dev/null
expected_number_send=$'send\t'"$team_first"$'\t''controller1'$'\t''worker1'$'\t''hello via visible pane number'
if ! grep -Fqx "$expected_number_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve visible pane number to active identity" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if "$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "2:2" "should reject cross-window" >/dev/null 2>&1; then
  echo "ERROR: cross-window target from window 1 should not resolve before window 2 exists" >&2
  exit 1
fi

tmux_i select-layout -t "$first_window" even-horizontal >/dev/null
"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to right "hello via right" >/dev/null
expected_right_send=$'send\t'"$team_first"$'\t''controller1'$'\t''worker1'$'\t''hello via right'
if ! grep -Fqx "$expected_right_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve relative right to active identity" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

"$SCRIPT_DIR/agmsg-tmux-actas.sh" --target "$third_worker_pane" reviewer1 >/dev/null
expected_actas_reviewer=$'join\t'"$team_first"$'\t''reviewer1'$'\t''codex'$'\t'"$PROJECT_C"
if ! grep -Fqx "$expected_actas_reviewer" "$CALL_LOG"; then
  echo "ERROR: actas did not register reviewer1 identity" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "reviewer1" ]; then
  echo "ERROR: third pane active identity was not reviewer1" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_display_identity)" != "reviewer1" ]; then
  echo "ERROR: third pane display identity was not reviewer1" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_identity_source)" != "manual" ]; then
  echo "ERROR: actas did not mark identity source as manual" >&2
  exit 1
fi
"$SCRIPT_DIR/agmsg-tmux-sync-active-identity.sh" "$first_pane"
if [ "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" != "reviewer1" ]; then
  echo "ERROR: identity sync overwrote manual reviewer identity" >&2
  exit 1
fi
"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "$third_worker_loc" "hello reviewer" >/dev/null
expected_reviewer_send=$'send\t'"$team_first"$'\t''controller1'$'\t''reviewer1'$'\t''hello reviewer'
if ! grep -Fqx "$expected_reviewer_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve reviewer1 pane" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi

TMUX="$SOCKET,0,0" TMUX_PANE="$third_worker_pane" HOME="$TEST_HOME" \
  fish -c "source '$SCRIPT_DIR/../fish/functions/__ai_pane_title_sync.fish'; __ai_pane_title_sync clear '$third_worker_pane'"
if [ -n "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_active_identity)" ]; then
  echo "ERROR: pane title clear did not clear agmsg active identity" >&2
  exit 1
fi
if [ -n "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_display_identity)" ]; then
  echo "ERROR: pane title clear did not clear agmsg display identity" >&2
  exit 1
fi
if [ -n "$(tmux_i show-option -pqv -t "$third_worker_pane" @agmsg_identity_source)" ]; then
  echo "ERROR: pane title clear did not clear agmsg identity source" >&2
  exit 1
fi

tmux_i source-file "$SCRIPT_DIR/tmux.conf" >/dev/null
border_format="$(tmux_i show-option -gv pane-border-format)"
if ! printf '%s\n' "$border_format" | grep -Fq '@agmsg_display_identity'; then
  echo "ERROR: pane border format does not read display identity" >&2
  printf '%s\n' "$border_format" >&2
  exit 1
fi

tmux_i new-window -n second -c "$PROJECT_A" 'sleep 60'
second_window="$(tmux_i display-message -p -t 'agmsg-scope-test:second' '#{window_id}')"
third_pane="$(tmux_i list-panes -t "$second_window" -F '#{pane_id}' | head -1)"
tmux_i set-option -p -t "$third_pane" @ai_app codex
second_window_index="$(tmux_i display-message -p -t "$second_window" '#{window_index}')"
if [ "$second_window_index" != "2" ]; then
  echo "ERROR: second tmux window should be user-visible window 2: $second_window_index" >&2
  exit 1
fi
team_second="$("$SCRIPT_DIR/agmsg-tmux-team.sh" --target "$third_pane")"
if [ "$team_first" = "$team_second" ]; then
  echo "ERROR: different windows resolved to the same team: $team_first" >&2
  exit 1
fi
second_window_worker_pane="$(tmux_i split-window -t "$third_pane" -c "$PROJECT_B" -P -F '#{pane_id}' 'sleep 60')"
tmux_i set-option -p -t "$second_window_worker_pane" @ai_app codex
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$third_pane" --skip-delivery >/dev/null
"$SCRIPT_DIR/agmsg-tmux-join.sh" --target "$second_window_worker_pane" --skip-delivery >/dev/null
if [ "$(tmux_i show-option -pqv -t "$third_pane" @agmsg_active_identity)" != "controller1" ]; then
  echo "ERROR: second window controller did not get controller1" >&2
  exit 1
fi
if [ "$(tmux_i show-option -pqv -t "$second_window_worker_pane" @agmsg_active_identity)" != "worker1" ]; then
  echo "ERROR: second window worker did not get worker1" >&2
  exit 1
fi
second_window_peers="$("$SCRIPT_DIR/agmsg-tmux-peers.sh" --target "$third_pane")"
if ! printf '%s\n' "$second_window_peers" | grep -Fq $'\t2:1\tcontroller1\t'"$third_pane"$'\tcodex'; then
  echo "ERROR: second window controller loc was not displayed as 2:1" >&2
  printf '%s\n' "$second_window_peers" >&2
  exit 1
fi
if ! printf '%s\n' "$second_window_peers" | grep -Fq $'\t2:2\tworker1\t'"$second_window_worker_pane"$'\tcodex'; then
  echo "ERROR: second window worker loc was not displayed as 2:2" >&2
  printf '%s\n' "$second_window_peers" >&2
  exit 1
fi
"$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$third_pane" --to "2:2" "hello via user-visible window 2" >/dev/null
expected_second_window_send=$'send\t'"$team_second"$'\t''controller1'$'\t''worker1'$'\t''hello via user-visible window 2'
if ! grep -Fqx "$expected_second_window_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not resolve user-visible 2:2 to second window worker" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if "$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "2:2" "hello cross-window should fail" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-send allowed cross-window visible target" >&2
  exit 1
fi
if "$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to "$second_window_worker_pane" "hello cross-window pane id should fail" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-send allowed cross-window %pane target" >&2
  exit 1
fi
if env -u TMUX -u TMUX_PANE -u AGMSG_TMUX_CURRENT_PANE AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" \
    "$SCRIPT_DIR/agmsg-tmux-send.sh" --to worker1 "missing source should fail" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-send sent without a source pane" >&2
  exit 1
fi

sqlite3 "$FAKE_SKILL/db/messages.db" \
  "INSERT INTO messages (team, from_agent, to_agent, body) VALUES ('$team_first', 'controller1', 'worker1', '{\"type\":\"review_request\"}');"
"$SCRIPT_DIR/agmsg-tmux-notify.sh" >/dev/null
if [ "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_unread_summary)" != "worker1 !1 from controller1" ]; then
  echo "ERROR: agmsg unread summary was not written to worker pane" >&2
  printf 'pane identity=%s ai_app=%s team=%s\n' \
    "$(tmux_i show-option -pqv -t "$second_pane" @agmsg_active_identity)" \
    "$(tmux_i show-option -pqv -t "$second_pane" @ai_app)" \
    "$("$SCRIPT_DIR/agmsg-tmux-team.sh" --target "$second_pane")" >&2
  sqlite3 "$FAKE_SKILL/db/messages.db" "SELECT team, from_agent, to_agent, read_at FROM messages;" >&2
  tmux_i show-option -pqv -t "$second_pane" @agmsg_unread_summary >&2
  exit 1
fi
if [ "$(sqlite3 "$FAKE_SKILL/db/messages.db" "SELECT count(*) FROM messages WHERE read_at IS NULL;")" != "1" ]; then
  echo "ERROR: agmsg notification watcher marked unread messages as read" >&2
  sqlite3 "$FAKE_SKILL/db/messages.db" "SELECT id, read_at FROM messages;" >&2
  exit 1
fi
if tmux_i show-option -gv pane-border-format | grep -Fq '@agmsg_unread_summary'; then
  echo "ERROR: pane border format leaked agmsg unread summary into title" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
AGMSG_TMUX_CURRENT_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-peers.sh" |
  grep -Fq $'\t2:2\tworker1\t'"$second_window_worker_pane"$'\tcodex' || {
    echo "ERROR: agmsg-tmux-peers did not use AGMSG_TMUX_CURRENT_PANE fallback" >&2
    exit 1
  }
if AGMSG_TMUX_CURRENT_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-peers.sh" --target "$first_pane" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-peers allowed explicit source target that conflicts with AGMSG_TMUX_CURRENT_PANE" >&2
  exit 1
fi
if TMUX="$SOCKET,0,0" TMUX_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-peers.sh" --target "$first_pane" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-peers allowed explicit source target that conflicts with TMUX_PANE" >&2
  exit 1
fi
AGMSG_TMUX_CURRENT_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-send.sh" --to worker1 "hello without explicit target" >/dev/null
expected_fallback_target_send=$'send\t'"$team_second"$'\t''controller1'$'\t''worker1'$'\t''hello without explicit target'
if ! grep -Fqx "$expected_fallback_target_send" "$CALL_LOG"; then
  echo "ERROR: agmsg-tmux-send did not use current pane fallback with worker1 name" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if AGMSG_TMUX_CURRENT_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to worker1 "wrong window should fail" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-send allowed explicit source target that conflicts with AGMSG_TMUX_CURRENT_PANE" >&2
  exit 1
fi
if TMUX="$SOCKET,0,0" TMUX_PANE="$third_pane" "$SCRIPT_DIR/agmsg-tmux-send.sh" --target "$first_pane" --to worker1 "wrong window should fail" >/dev/null 2>&1; then
  echo "ERROR: agmsg-tmux-send allowed explicit source target that conflicts with TMUX_PANE" >&2
  exit 1
fi

fish_project="$SOCKET_DIR/fish-project"
mkdir -p "$fish_project"
fish_project="$(cd "$fish_project" && pwd -P)"
TMUX="$SOCKET,0,0" TMUX_PANE="$first_pane" HOME="$TEST_HOME" AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" AGMSG_TEST_CALL_LOG="$CALL_LOG" \
  fish -c "source '$SCRIPT_DIR/../fish/functions/codex.fish'; __codex_agmsg_tmux_scope_join '$fish_project'"
expected_fish_join=$'join\t'"$team_first"$'\t'"codex-$first_pane"$'\t''codex'$'\t'"$fish_project"
if grep -Fqx "$expected_fish_join" "$CALL_LOG"; then
  :
elif grep -Fqx $'join\t'"$team_first"$'\t''controller1'$'\t''codex'$'\t'"$fish_project" "$CALL_LOG"; then
  :
else
  echo "ERROR: codex fish wrapper did not join tmux agmsg scope" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if grep -Fqx $'delivery\tturn\tcodex\t'"$fish_project" "$CALL_LOG"; then
  echo "ERROR: codex fish wrapper wrote delivery despite --skip-delivery" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
codex_env_output="$(
  TMUX="$SOCKET,0,0" TMUX_PANE="$first_pane" HOME="$TEST_HOME" AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" AGMSG_TEST_CALL_LOG="$CALL_LOG" \
    fish -c "source '$SCRIPT_DIR/../fish/functions/codex.fish'; __codex_export_agmsg_identity; printf '%s\t%s\t%s\n' \"\$AGMSG_TMUX_CURRENT_PANE\" \"\$AGMSG_TMUX_SOCKET\" \"\$AGMSG_AGENT_ID\""
)"
if [ "$codex_env_output" != "$first_pane"$'\t'"$SOCKET"$'\t'"$(tmux_i show-option -pqv -t "$first_pane" @agmsg_active_identity)" ]; then
  echo "ERROR: codex fish wrapper did not export agmsg tmux source environment" >&2
  printf '%s\n' "$codex_env_output" >&2
  exit 1
fi

claude_fish_project="$SOCKET_DIR/claude-fish-project"
mkdir -p "$claude_fish_project"
claude_fish_project="$(cd "$claude_fish_project" && pwd -P)"
TMUX="$SOCKET,0,0" TMUX_PANE="$second_pane" HOME="$TEST_HOME" AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" AGMSG_TEST_CALL_LOG="$CALL_LOG" \
  fish -c "source '$SCRIPT_DIR/../fish/functions/claude.fish'; __claude_agmsg_tmux_scope_join '$claude_fish_project'"
expected_claude_fish_join=$'join\t'"$team_first"$'\t'"claude-code-$second_pane"$'\t''claude-code'$'\t'"$claude_fish_project"
if grep -Fqx "$expected_claude_fish_join" "$CALL_LOG"; then
  :
elif grep -Fqx $'join\t'"$team_first"$'\t''worker1'$'\t''claude-code'$'\t'"$claude_fish_project" "$CALL_LOG"; then
  :
else
  echo "ERROR: claude fish wrapper did not join tmux agmsg scope" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
if grep -Fqx $'delivery\tmonitor\tclaude-code\t'"$claude_fish_project" "$CALL_LOG"; then
  echo "ERROR: claude fish wrapper wrote delivery despite --skip-delivery" >&2
  cat "$CALL_LOG" >&2
  exit 1
fi
claude_env_output="$(
  TMUX="$SOCKET,0,0" TMUX_PANE="$second_pane" HOME="$TEST_HOME" AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" AGMSG_TEST_CALL_LOG="$CALL_LOG" \
    fish -c "source '$SCRIPT_DIR/../fish/functions/claude.fish'; __claude_export_agmsg_identity; printf '%s\t%s\t%s\n' \"\$AGMSG_TMUX_CURRENT_PANE\" \"\$AGMSG_TMUX_SOCKET\" \"\$AGMSG_AGENT_ID\""
)"
if [ "$claude_env_output" != "$second_pane"$'\t'"$SOCKET"$'\t'"$(tmux_i show-option -pqv -t "$second_pane" @agmsg_active_identity)" ]; then
  echo "ERROR: claude fish wrapper did not export agmsg tmux source environment" >&2
  printf '%s\n' "$claude_env_output" >&2
  exit 1
fi
tmux_i set-option -p -t "$second_pane" @ai_app ""
TMUX="$SOCKET,0,0" TMUX_PANE="$second_pane" HOME="$TEST_HOME" AGMSG_TMUX_SOCKET="$SOCKET" AGMSG_SKILL_DIR="$FAKE_SKILL" AGMSG_TEST_CALL_LOG="$CALL_LOG" \
  fish -c "source '$SCRIPT_DIR/../fish/functions/claude.fish'; __claude_ensure_ai_pane_title_sync; __ai_pane_title_sync set-base '$second_pane' fallback test; __ai_pane_title_sync mark-app '$second_pane' claude; __claude_agmsg_tmux_scope_join '$claude_fish_project'"
if [ "$(tmux_i show-option -pqv -t "$second_pane" @ai_app)" != "claude" ]; then
  echo "ERROR: claude wrapper flow did not mark pane as claude before join" >&2
  exit 1
fi
