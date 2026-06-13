#!/usr/bin/env bash
# dotfiles 管理のパッケージ更新・ローカル掃除・Slack 通知を 1 日 1 回実行する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT="${DOTFILES_MAINTENANCE_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
DRY_RUN=0
NO_SLACK=0
ENV_FILE="${DOTFILES_MAINTENANCE_ENV_FILE:-$HOME/.config/dotfiles-maintenance/env}"

usage() {
  cat <<'EOF'
Usage: scripts/daily-maintenance.sh [--dry-run] [--no-slack] [--env-file PATH] [--repo-root PATH]

dotfiles の日次メンテナンスを実行する:
  1. worktree が clean なら git fetch / pull --ff-only。
  2. ./install.sh で Homebrew / npm / 設定コピーを同期。
  3. scripts/cleanup-local-disk.sh --apply で再生成可能なローカルデータを整理。
  4. Codex で結果を要約して Slack に投稿。
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      ;;
    --no-slack)
      NO_SLACK=1
      ;;
    --env-file)
      [[ $# -ge 2 ]] || { echo "--env-file requires PATH" >&2; exit 2; }
      ENV_FILE="$2"
      shift
      ;;
    --repo-root)
      [[ $# -ge 2 ]] || { echo "--repo-root requires PATH" >&2; exit 2; }
      REPO_ROOT="$2"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

[[ -n "$REPO_ROOT" ]] || {
  echo "repo root is not set. Use --repo-root PATH." >&2
  exit 2
}

if [[ -r "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

STATE_ROOT="${DOTFILES_MAINTENANCE_STATE_ROOT:-$HOME/.local/state/dotfiles-maintenance}"
RUN_ID="${DOTFILES_MAINTENANCE_RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RUN_DIR="$STATE_ROOT/runs/$RUN_ID"
EVENTS_FILE="$RUN_DIR/events.jsonl"
SUMMARY_FILE="$RUN_DIR/slack-summary.md"
PROMPT_FILE="$RUN_DIR/codex-summary-prompt.md"
SLACK_PAYLOAD_FILE="$RUN_DIR/slack-payload.json"
SLACK_RESPONSE_FILE="$RUN_DIR/slack-response.json"
INSTALL_CMD="${DOTFILES_MAINTENANCE_INSTALL_CMD:-$REPO_ROOT/install.sh}"
CLEANUP_CMD="${DOTFILES_MAINTENANCE_CLEANUP_CMD:-$REPO_ROOT/scripts/cleanup-local-disk.sh}"
CODEX_BIN="${DOTFILES_MAINTENANCE_CODEX_BIN:-codex}"
CURL_BIN="${DOTFILES_MAINTENANCE_CURL_BIN:-curl}"
CODEX_PROFILE="${DOTFILES_MAINTENANCE_CODEX_PROFILE:-routine}"
SKIP_SLACK="${DOTFILES_MAINTENANCE_SKIP_SLACK:-0}"
MAINTENANCE_RC=0

mkdir -p "$RUN_DIR"

log() {
  printf '%s\n' "$*"
}

append_event() {
  local step="$1"
  local status="$2"
  local rc="$3"
  local message="$4"
  local log_path="${5:-}"
  python3 - "$EVENTS_FILE" "$step" "$status" "$rc" "$message" "$log_path" <<'PY'
import json
import sys
from datetime import datetime, timezone

events_file, step, status, rc, message, log_path = sys.argv[1:7]
event = {
    "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "step": step,
    "status": status,
    "exit_code": int(rc),
    "message": message,
}
if log_path:
    event["log"] = log_path
with open(events_file, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
}

run_step() {
  local step="$1"
  shift
  local log_path="$RUN_DIR/$step.log"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf 'dry-run:' > "$log_path"
    printf ' %q' "$@" >> "$log_path"
    printf '\n' >> "$log_path"
    append_event "$step" "skipped" 0 "dry-run" "$log_path"
    return 0
  fi

  set +e
  "$@" > "$log_path" 2>&1
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    append_event "$step" "ok" "$rc" "completed" "$log_path"
  else
    append_event "$step" "failed" "$rc" "command failed" "$log_path"
    MAINTENANCE_RC=1
  fi
  return "$rc"
}

worktree_dirty() {
  [[ -n "$(git -C "$REPO_ROOT" status --short)" ]]
}

upstream_ref() {
  git -C "$REPO_ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null
}

run_git_update_and_install() {
  if worktree_dirty; then
    append_event "git-update" "skipped" 0 "worktree is dirty; skipped pull"
    append_event "install" "skipped" 0 "worktree is dirty; skipped ./install.sh"
    return 0
  fi

  local upstream
  if upstream="$(upstream_ref)"; then
    if ! run_step "git-fetch" git -C "$REPO_ROOT" fetch --prune; then
      append_event "git-pull" "skipped" 1 "git fetch failed; skipped pull"
      append_event "install" "skipped" 1 "git fetch failed; skipped ./install.sh"
      return 0
    fi
    if run_step "git-pull" git -C "$REPO_ROOT" pull --ff-only; then
      append_event "git-update" "ok" 0 "updated from $upstream"
    else
      append_event "install" "skipped" 1 "git pull failed; skipped ./install.sh"
      return 0
    fi
  else
    append_event "git-update" "skipped" 0 "upstream is not configured; using current checkout"
  fi

  run_step "install" "$INSTALL_CMD" || true
}

run_cleanup() {
  run_step "cleanup-local-disk" "$CLEANUP_CMD" --apply --repo-root "$REPO_ROOT" || true
}

tail_excerpt() {
  local path="$1"
  [[ -f "$path" ]] || return 0
  printf '%s\n' "--- $path ---"
  tail -n 80 "$path" || true
}

build_prompt() {
  {
    cat <<EOF
dotfiles 日次メンテナンス結果を Slack 投稿用に日本語で要約してください。

制約:
- 1200文字以内
- 先頭に「dotfiles 日次メンテナンス: <状態>」を1行で書く
- 次に「実行内容」「結果」「対応要否」を短く書く
- 各章の本文は1〜3項目の箇条書きにし、各項目は必ず「- 」で始める
- step 名や exit code の羅列だけで終わらせない
- dry-run の場合は「これは試験実行で、ローカル更新・掃除は実行していない」と明記する
- dirty worktree で pull/install が skip された場合は「未コミット変更があるため更新と install は見送った」と説明する
- 同じ意味の説明を重複させない
- 機密値は書かない
- Slack mrkdwn として自然な範囲に留める

Run directory: $RUN_DIR
Events:
EOF
    cat "$EVENTS_FILE"
    printf '\nLog excerpts:\n'
    while IFS= read -r event_log; do
      tail_excerpt "$event_log"
    done < <(python3 - "$EVENTS_FILE" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    for line in fh:
        event = json.loads(line)
        if event.get("status") != "ok" and event.get("log"):
            print(event["log"])
PY
)
  } > "$PROMPT_FILE"
}

fallback_summary() {
  python3 - "$EVENTS_FILE" "$RUN_DIR" <<'PY'
import json
import sys

events_file, run_dir = sys.argv[1:3]
events = []
with open(events_file, encoding="utf-8") as fh:
    for line in fh:
        events.append(json.loads(line))

failed = [e for e in events if e["status"] == "failed"]
skipped = [e for e in events if e["status"] == "skipped"]
if failed:
    status = "dotfiles 日次メンテナンス: 要確認"
elif skipped:
    status = "dotfiles 日次メンテナンス: 一部skip"
else:
    status = "dotfiles 日次メンテナンス: 完了"

lines = [status, f"run: {run_dir}"]
messages = [e["message"] for e in events]
dry_run = any("dry-run" in m for m in messages)
dirty = any("worktree is dirty" in m for m in messages)
slack_ok = any(e["step"] == "slack-post" and e["status"] == "ok" for e in events)

if dry_run:
    lines.append("実行内容: 試験実行です。ローカル更新・install・掃除は実行していません。")
else:
    lines.append("実行内容: dotfiles 更新、install、ローカル掃除、Slack 通知を実行しました。")

if dirty:
    lines.append("結果: 未コミット変更があるため、git pull と ./install.sh は見送りました。")
elif failed:
    failed_steps = ", ".join(e["step"] for e in failed)
    lines.append(f"結果: 失敗した処理があります: {failed_steps}")
elif skipped:
    skipped_steps = ", ".join(e["step"] for e in skipped if e["step"] not in {"codex-summary", "slack-post"})
    if skipped_steps:
        lines.append(f"結果: 一部処理を見送りました: {skipped_steps}")
    else:
        lines.append("結果: 主要処理は完了しました。")
else:
    lines.append("結果: 全ての処理が完了しました。")

if failed:
    lines.append("対応要否: run dir のログを確認してください。")
elif dirty:
    lines.append("対応要否: 未コミット変更を整理すると、次回は更新と install まで進みます。")
else:
    lines.append("対応要否: 追加対応はありません。")

if slack_ok:
    lines.append("Slack 投稿: 成功")
print("\n".join(lines))
PY
}

generate_summary() {
  build_prompt
  set +e
  "$CODEX_BIN" exec \
    --profile "$CODEX_PROFILE" \
    --cd "$REPO_ROOT" \
    --sandbox read-only \
    --output-last-message "$SUMMARY_FILE" \
    - < "$PROMPT_FILE" > "$RUN_DIR/codex-summary.stdout.log" 2> "$RUN_DIR/codex-summary.stderr.log"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 || ! -s "$SUMMARY_FILE" ]]; then
    fallback_summary > "$SUMMARY_FILE"
    append_event "codex-summary" "failed" "$rc" "Codex summary failed; used fallback summary" "$RUN_DIR/codex-summary.stderr.log"
    MAINTENANCE_RC=1
  else
    append_event "codex-summary" "ok" "$rc" "summary generated" "$SUMMARY_FILE"
  fi
}

build_slack_payload() {
  python3 - "$SUMMARY_FILE" "$SLACK_CHANNEL_ID" "$SLACK_PAYLOAD_FILE" <<'PY'
import json
import re
import sys

summary_file, channel, payload_file = sys.argv[1:4]
with open(summary_file, encoding="utf-8") as fh:
    raw_text = fh.read().strip()

def normalize_mrkdwn(value: str) -> str:
    value = re.sub(r"\*\*([^*\n][^*\n]*?)\*\*", r"*\1*", value)
    return value.strip()

def inline_elements(value: str):
    elements = []
    pos = 0
    for match in re.finditer(r"`([^`\n]+)`|\*([^*\n]+)\*", value):
        if match.start() > pos:
            elements.append({"type": "text", "text": value[pos:match.start()]})
        if match.group(1) is not None:
            elements.append({"type": "text", "text": match.group(1), "style": {"code": True}})
        else:
            elements.append({"type": "text", "text": match.group(2), "style": {"bold": True}})
        pos = match.end()
    if pos < len(value):
        elements.append({"type": "text", "text": value[pos:]})
    return elements or [{"type": "text", "text": value}]

def rich_text_section(value: str, *, bold: bool = False):
    if bold:
        return {
            "type": "rich_text_section",
            "elements": [{"type": "text", "text": value, "style": {"bold": True}}],
        }
    return {"type": "rich_text_section", "elements": inline_elements(normalize_mrkdwn(value))}

def rich_text_list(items):
    return {
        "type": "rich_text_list",
        "style": "bullet",
        "indent": 0,
        "border": 0,
        "elements": [
            {"type": "rich_text_section", "elements": inline_elements(normalize_mrkdwn(item))}
            for item in items
            if item.strip()
        ],
    }

def body_elements(body: str):
    elements = []
    paragraph = []
    bullets = []

    def flush_paragraph():
        nonlocal paragraph
        text = "\n".join(paragraph).strip()
        if text:
            elements.append(rich_text_list([text]))
        paragraph = []

    def flush_bullets():
        nonlocal bullets
        if bullets:
            elements.append(rich_text_list(bullets))
        bullets = []

    for line in body.splitlines():
        stripped = line.strip()
        bullet_match = re.match(r"^[-*]\s+(.+)$", stripped)
        if bullet_match:
            flush_paragraph()
            bullets.append(bullet_match.group(1).strip())
        elif stripped:
            flush_bullets()
            paragraph.append(stripped)
        else:
            flush_paragraph()
            flush_bullets()
    flush_paragraph()
    flush_bullets()
    return elements

def header_text(value: str) -> str:
    value = re.sub(r"^[#*\s]+|[*\s]+$", "", value).strip()
    return value[:150] if value else "dotfiles 日次メンテナンス"

def split_sections(value: str):
    lines = value.splitlines()
    title = ""
    while lines and not lines[0].strip():
        lines.pop(0)
    if lines:
        title = lines.pop(0).strip()

    sections = []
    current_heading = ""
    current_body = []

    def flush():
        nonlocal current_heading, current_body
        body = "\n".join(line.rstrip() for line in current_body).strip()
        if current_heading or body:
            sections.append((current_heading, body))
        current_heading = ""
        current_body = []

    for line in lines:
        stripped = line.strip()
        heading_match = re.fullmatch(r"\*{1,2}([^*\n]+)\*{1,2}", stripped)
        colon_match = re.match(r"^(実行内容|結果|対応要否|Slack 投稿|Slack投稿)[:：]\s*(.*)$", stripped)
        if heading_match:
            flush()
            current_heading = heading_match.group(1).strip()
        elif colon_match:
            flush()
            current_heading = colon_match.group(1).strip()
            if colon_match.group(2).strip():
                current_body.append(colon_match.group(2).strip())
        else:
            current_body.append(line)
    flush()

    if not sections:
        body = "\n".join(lines).strip()
        if body:
            sections.append(("", body))
    return header_text(title), sections

title, sections = split_sections(raw_text)
fallback_text = normalize_mrkdwn(raw_text)
if len(fallback_text) > 3900:
    fallback_text = fallback_text[:3890].rstrip() + "\n...(truncated)"

blocks = [
    {"type": "header", "text": {"type": "plain_text", "text": title, "emoji": False}},
    {"type": "divider"},
]
for heading, body in sections[:8]:
    elements = []
    if heading:
        elements.append(rich_text_section(heading, bold=True))
    if body:
        elements.extend(body_elements(body))
    if not elements:
        continue
    blocks.append({"type": "rich_text", "elements": elements[:12]})

if len(blocks) == 2:
    blocks.append({"type": "rich_text", "elements": body_elements(fallback_text)})

payload = {
    "channel": channel,
    "text": fallback_text,
    "blocks": blocks,
    "unfurl_links": False,
    "unfurl_media": False,
}
with open(payload_file, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, ensure_ascii=False)
PY
}

post_slack() {
  if [[ "$NO_SLACK" -eq 1 || "$SKIP_SLACK" == "1" ]]; then
    append_event "slack-post" "skipped" 0 "Slack posting disabled"
    return 0
  fi
  if [[ -z "${SLACK_BOT_TOKEN:-}" || -z "${SLACK_CHANNEL_ID:-}" ]]; then
    append_event "slack-post" "skipped" 0 "SLACK_BOT_TOKEN or SLACK_CHANNEL_ID is missing"
    return 0
  fi

  build_slack_payload
  set +e
  "$CURL_BIN" -sS \
    -X POST "https://slack.com/api/chat.postMessage" \
    -H "Authorization: Bearer $SLACK_BOT_TOKEN" \
    -H "Content-Type: application/json; charset=utf-8" \
    --data @"$SLACK_PAYLOAD_FILE" > "$SLACK_RESPONSE_FILE" 2> "$RUN_DIR/slack-post.stderr.log"
  local rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    append_event "slack-post" "failed" "$rc" "curl failed" "$RUN_DIR/slack-post.stderr.log"
    MAINTENANCE_RC=1
    return 0
  fi

  if python3 - "$SLACK_RESPONSE_FILE" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)
sys.exit(0 if data.get("ok") is True else 1)
PY
  then
    append_event "slack-post" "ok" 0 "posted to Slack" "$SLACK_RESPONSE_FILE"
  else
    append_event "slack-post" "failed" 1 "Slack API returned ok=false" "$SLACK_RESPONSE_FILE"
    MAINTENANCE_RC=1
  fi
}

main() {
  append_event "start" "ok" 0 "daily maintenance started"
  run_git_update_and_install
  run_cleanup
  generate_summary
  post_slack
  if [[ "$MAINTENANCE_RC" -eq 0 ]]; then
    append_event "finish" "ok" "$MAINTENANCE_RC" "daily maintenance finished"
  else
    append_event "finish" "failed" "$MAINTENANCE_RC" "daily maintenance finished with failures"
  fi
  log "run_dir=$RUN_DIR"
  exit "$MAINTENANCE_RC"
}

main "$@"
