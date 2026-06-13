#!/usr/bin/env bash
# macOS のローカル開発環境で肥大化しやすい再生成可能データを整理する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

APPLY=0
VERBOSE=0
CLEAN_CRASHPAD=1
CLEAN_CRUDE_BACKUPS=1
CLEAN_TERRAFORM=1
CLEAN_HOMEBREW=1

HOME_ROOT="${DOTFILES_CLEANUP_HOME:-$HOME}"
REPO_ROOT="${DOTFILES_CLEANUP_REPO_ROOT:-$DEFAULT_REPO_ROOT}"
WORKSPACE_ROOT="${DOTFILES_CLEANUP_WORKSPACE_ROOT:-}"
if [[ -z "$WORKSPACE_ROOT" ]]; then
  WORKSPACE_ROOT="$(cd "$REPO_ROOT/../.." 2>/dev/null && pwd || printf '%s\n' "$HOME_ROOT/agent")"
fi

usage() {
  cat <<'EOF'
Usage: scripts/cleanup-local-disk.sh [--apply] [--repo-root PATH] [options]

Options:
  --apply                 実際に整理する。指定しない場合は dry-run。
  --repo-root PATH        dotfiles repo root。
  --workspace-root PATH   agent workspace root。既定は dotfiles repo の 2 階層上。
  --no-crashpad           Codex Crashpad dump の整理をスキップする。
  --no-crude-backups      crude-morning-report の analysis-history backup 削除をスキップする。
  --no-terraform          aws-cliniconnect-terraform の .terraform 削除をスキップする。
  --no-homebrew           Homebrew cache cleanup をスキップする。
  --verbose               実行コマンドの補足を表示する。
  -h, --help              このヘルプを表示する。

既定では dry-run で、容量と実行予定だけを表示する。
EOF
}

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warn: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

run_or_print() {
  if [[ "$APPLY" -eq 1 ]]; then
    if [[ "$VERBOSE" -ne 0 ]]; then
      local arg
      printf '+' >&2
      for arg in "$@"; do
        printf ' %q' "$arg" >&2
      done
      printf '\n' >&2
    fi
    "$@"
  else
    printf 'dry-run:'
    local arg
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  fi
}

print_size() {
  local path="$1"
  if [[ -e "$path" ]]; then
    du -sh "$path" 2>/dev/null || true
  else
    printf 'missing\t%s\n' "$path"
  fi
}

print_disk() {
  if [[ -d /System/Volumes/Data ]]; then
    df -h /System/Volumes/Data
  else
    df -h "$HOME_ROOT"
  fi
}

truncate_crashpad() {
  local pending="$HOME_ROOT/Library/Application Support/com.openai.codex/web/Crashpad/pending"
  log
  log "=== Codex Crashpad pending dumps ==="
  [[ -d "$pending" ]] || return 0

  if [[ "$APPLY" -eq 1 ]]; then
    print_size "$pending"
    find "$pending" -maxdepth 1 -type f -name '*.dmp' -size +0c -exec truncate -s 0 {} +
  else
    log "path=$pending"
    log "size=dry-run-skipped"
    log "dry-run: find \"$pending\" -maxdepth 1 -type f -name '*.dmp' -size +0c -exec truncate -s 0 '{}' +"
  fi
}

delete_crude_backups() {
  local state="$WORKSPACE_ROOT/projects/crude-morning-report/state"
  log
  log "=== crude-morning-report analysis history backups ==="
  print_size "$state"
  [[ -d "$state" ]] || return 0

  local backups=()
  while IFS= read -r -d '' path; do
    backups+=("$path")
  done < <(find "$state" -maxdepth 1 -type f -name 'analysis-history.sqlite.backup-*' -print0)

  if [[ "${#backups[@]}" -eq 0 ]]; then
    log "backup_files=0"
    return 0
  fi

  du -sh "${backups[@]}" 2>/dev/null || true
  run_or_print rm -f "${backups[@]}"
}

clean_terraform_caches() {
  local repo="$WORKSPACE_ROOT/projects/aws-cliniconnect-terraform"
  log
  log "=== aws-cliniconnect-terraform .terraform caches ==="
  print_size "$repo/environments"
  [[ -d "$repo/.git" ]] || {
    warn "git repo not found: $repo"
    return 0
  }

  local caches=()
  while IFS= read -r -d '' path; do
    caches+=("${path#"$repo/"}")
  done < <(find "$repo/environments" -maxdepth 2 -type d -name .terraform -print0 2>/dev/null || true)

  if [[ "${#caches[@]}" -eq 0 ]]; then
    log "terraform_caches=0"
    return 0
  fi

  local abs=()
  local rel
  for rel in "${caches[@]}"; do
    abs+=("$repo/$rel")
  done
  du -sh "${abs[@]}" 2>/dev/null || true
  run_or_print git -C "$repo" clean -fdX -- "${caches[@]}"
}

clean_homebrew() {
  log
  log "=== Homebrew cleanup ==="
  local cache="$HOME_ROOT/Library/Caches/Homebrew"
  print_size "$cache"

  local brew_cmd="${DOTFILES_CLEANUP_BREW:-}"
  if [[ -z "$brew_cmd" ]]; then
    if ! brew_cmd="$(command -v brew 2>/dev/null)"; then
      warn "brew not found"
      return 0
    fi
  fi

  run_or_print "$brew_cmd" cleanup --prune=all -s
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        APPLY=1
        ;;
      --repo-root)
        [[ $# -ge 2 ]] || die "--repo-root requires PATH"
        REPO_ROOT="$2"
        shift
        ;;
      --workspace-root)
        [[ $# -ge 2 ]] || die "--workspace-root requires PATH"
        WORKSPACE_ROOT="$2"
        shift
        ;;
      --no-crashpad)
        CLEAN_CRASHPAD=0
        ;;
      --no-crude-backups)
        CLEAN_CRUDE_BACKUPS=0
        ;;
      --no-terraform)
        CLEAN_TERRAFORM=0
        ;;
      --no-homebrew)
        CLEAN_HOMEBREW=0
        ;;
      --verbose)
        VERBOSE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1"
        ;;
    esac
    shift
  done

  if [[ "$APPLY" -eq 1 ]]; then
    log "mode=apply"
  else
    log "mode=dry-run"
  fi
  log "repo_root=$REPO_ROOT"
  log "workspace_root=$WORKSPACE_ROOT"

  log
  log "=== disk before ==="
  print_disk

  [[ "$CLEAN_CRASHPAD" -eq 0 ]] || truncate_crashpad
  [[ "$CLEAN_CRUDE_BACKUPS" -eq 0 ]] || delete_crude_backups
  [[ "$CLEAN_TERRAFORM" -eq 0 ]] || clean_terraform_caches
  [[ "$CLEAN_HOMEBREW" -eq 0 ]] || clean_homebrew

  log
  log "=== disk after ==="
  print_disk
}

main "$@"
