#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
mkdir -p "$ROOT/tmp/tests"
WORK_ROOT="$(mktemp -d "$ROOT/tmp/tests/maintenance.XXXXXX")"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'ok - %s\n' "$1"
}

test_install_maintenance_mode() {
  local home="$WORK_ROOT/home"
  local fake_bin="$WORK_ROOT/bin"
  local launchctl_log="$WORK_ROOT/launchctl.log"
  mkdir -p "$home" "$fake_bin"

  cat > "$fake_bin/launchctl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$DOTFILES_TEST_LAUNCHCTL_LOG"
EOF
  chmod +x "$fake_bin/launchctl"

  HOME="$home" \
    DOTFILES_MAINTENANCE_LAUNCHCTL_BIN="$fake_bin/launchctl" \
    DOTFILES_TEST_LAUNCHCTL_LOG="$launchctl_log" \
    "$ROOT/install.sh" maintenance > "$WORK_ROOT/install-maintenance.out"

  [[ -x "$home/.local/bin/dotfiles-daily-maintenance" ]] || fail "daily maintenance script was not installed"
  [[ -x "$home/.local/bin/dotfiles-cleanup-local-disk" ]] || fail "cleanup script was not installed"
  [[ -f "$home/.config/dotfiles-maintenance/env" ]] || fail "env template was not created"
  [[ -f "$home/Library/LaunchAgents/com.u-kt.dotfiles-daily-maintenance.plist" ]] || fail "plist was not copied"
  plutil -lint "$home/Library/LaunchAgents/com.u-kt.dotfiles-daily-maintenance.plist" >/dev/null
  grep -Fq "bootstrap" "$launchctl_log" || fail "launchctl bootstrap was not called"
  grep -Fq "enable gui/" "$launchctl_log" || fail "launchctl enable was not called"
  pass "install.sh maintenance installs scripts, env, plist, and loads LaunchAgent"
}

test_cleanup_script_fixture() {
  local home="$WORK_ROOT/cleanup-home"
  local workspace="$WORK_ROOT/workspace"
  local dotfiles="$WORK_ROOT/dotfiles"
  local tf_repo="$workspace/projects/aws-cliniconnect-terraform"
  local crude_state="$workspace/projects/crude-morning-report/state"
  local pending="$home/Library/Application Support/com.openai.codex/web/Crashpad/pending"
  local fake_bin="$WORK_ROOT/cleanup-bin"
  local brew_log="$WORK_ROOT/brew.log"

  mkdir -p "$pending" "$crude_state" "$tf_repo/environments/dev/.terraform" "$fake_bin" "$dotfiles"
  printf 'dump-data\n' > "$pending/example.dmp"
  printf 'backup-data\n' > "$crude_state/analysis-history.sqlite.backup-20260612-2050"
  printf 'provider\n' > "$tf_repo/environments/dev/.terraform/provider"

  git -C "$tf_repo" init >/dev/null
  printf '.terraform/\n' > "$tf_repo/.gitignore"
  git -C "$tf_repo" add .gitignore
  git -C "$tf_repo" -c user.name="Test" -c user.email="test@example.invalid" commit -m "initial" >/dev/null

  cat > "$fake_bin/brew" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$DOTFILES_TEST_BREW_LOG"
EOF
  chmod +x "$fake_bin/brew"

  DOTFILES_CLEANUP_HOME="$home" \
    DOTFILES_CLEANUP_REPO_ROOT="$dotfiles" \
    DOTFILES_CLEANUP_WORKSPACE_ROOT="$workspace" \
    DOTFILES_CLEANUP_BREW="$fake_bin/brew" \
    DOTFILES_TEST_BREW_LOG="$brew_log" \
    "$ROOT/scripts/cleanup-local-disk.sh" --apply > "$WORK_ROOT/cleanup.out"

  [[ "$(wc -c < "$pending/example.dmp" | tr -d ' ')" == "0" ]] || fail "Crashpad dump was not truncated"
  [[ ! -e "$crude_state/analysis-history.sqlite.backup-20260612-2050" ]] || fail "crude backup was not removed"
  [[ ! -d "$tf_repo/environments/dev/.terraform" ]] || fail "terraform cache was not removed"
  [[ "$(cat "$brew_log")" == "cleanup --prune=all -s" ]] || fail "brew cleanup was not called"
  pass "cleanup-local-disk cleans reproducible local data"
}

test_daily_maintenance_uses_codex_summary_in_dry_run() {
  local repo="$WORK_ROOT/repo"
  local fake_bin="$WORK_ROOT/fake-bin"
  local state="$WORK_ROOT/state"
  local env_file="$WORK_ROOT/slack.env"
  local payload_file="$WORK_ROOT/slack-payload.json"
  mkdir -p "$repo" "$fake_bin"
  git -C "$repo" init >/dev/null
  git -C "$repo" checkout -b main >/dev/null 2>&1
  printf 'dirty\n' > "$repo/dirty.txt"

  cat > "$fake_bin/codex" <<'EOF'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output-last-message)
      out="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cat >/dev/null
cat > "$out" <<'SUMMARY'
dotfiles 日次メンテナンス: 試験実行

**実行内容**
- dry-run のため、ローカル更新・install・掃除は実行していません。
- `cleanup-local-disk.sh` は試験実行でした。

**結果**
- 未コミット変更があるため、git pull と ./install.sh は見送りました。

**対応要否**
- 未コミット変更を整理すると、次回は更新と install まで進みます。
SUMMARY
EOF
  cat > "$fake_bin/curl" <<'EOF'
#!/usr/bin/env bash
payload=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --data)
      payload="${2#@}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
cp "$payload" "$DOTFILES_TEST_SLACK_PAYLOAD"
printf '{"ok":true}\n'
EOF
  chmod +x "$fake_bin/codex" "$fake_bin/curl"

  printf 'SLACK_BOT_TOKEN=test-bot-token\nSLACK_CHANNEL_ID=C123\n' > "$env_file"

  DOTFILES_MAINTENANCE_STATE_ROOT="$state" \
    DOTFILES_MAINTENANCE_CODEX_BIN="$fake_bin/codex" \
    DOTFILES_MAINTENANCE_CURL_BIN="$fake_bin/curl" \
    DOTFILES_TEST_SLACK_PAYLOAD="$payload_file" \
    "$ROOT/scripts/daily-maintenance.sh" --dry-run --repo-root "$repo" --env-file "$env_file" >/dev/null

  grep -Fq "dotfiles 日次メンテナンス: 試験実行" "$payload_file" || fail "Codex summary was not used in Slack payload"
  grep -Fq "ローカル更新・install・掃除は実行していません" "$payload_file" || fail "human-readable dry-run summary missing"
  grep -Fq '"blocks"' "$payload_file" || fail "Slack payload does not use Block Kit blocks"
  grep -Fq '"type": "header"' "$payload_file" || fail "Slack payload does not include a header block"
  grep -Fq '"type": "rich_text"' "$payload_file" || fail "Slack payload does not include rich_text blocks"
  grep -Fq '"type": "rich_text_list"' "$payload_file" || fail "Slack payload does not include native list blocks"
  ! grep -Fq '**' "$payload_file" || fail "Slack payload still contains non-Slack bold markdown"
  python3 - "$payload_file" <<'PY' || fail "Slack payload list elements are not structured"
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

rich_lists = []
for block in payload.get("blocks", []):
    for element in block.get("elements", []):
        if element.get("type") == "rich_text_list":
            rich_lists.append(element)

assert rich_lists, "missing rich_text_list"
assert any(item.get("style", {}).get("code") for rich_list in rich_lists for section in rich_list.get("elements", []) for item in section.get("elements", [])), "missing inline code style"
PY
  pass "daily maintenance dry-run uses Codex summary for Slack payload"
}

bash -n "$ROOT/scripts/daily-maintenance.sh" "$ROOT/scripts/cleanup-local-disk.sh" "$ROOT/lib/maintenance.sh"
test_install_maintenance_mode
test_cleanup_script_fixture
test_daily_maintenance_uses_codex_summary_in_dry_run

printf 'maintenance tests passed\n'
