#!/usr/bin/env bash
# Docker Desktop のローカルディスク肥大化を抑える保守スクリプト。

set -euo pipefail

MODE="status"
FORCE=0

RAW_PATH="${DOTFILES_DOCKER_RAW_PATH:-$HOME/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw}"
PRUNE_THRESHOLD_GIB="${DOTFILES_DOCKER_PRUNE_THRESHOLD_GIB:-60}"
MIN_FREE_GIB="${DOTFILES_DOCKER_MIN_FREE_GIB:-30}"
PRUNE_UNTIL="${DOTFILES_DOCKER_PRUNE_UNTIL:-168h}"
CACHE_UNTIL="${DOTFILES_DOCKER_CACHE_UNTIL:-168h}"
LOG_DIR="${DOTFILES_DOCKER_LOG_DIR:-$HOME/Library/Logs/dotfiles}"
LOG_FILE="$LOG_DIR/docker-disk-maintenance.log"

usage() {
  cat <<'USAGE'
Usage: docker-disk-maintenance.sh [--status|--dry-run|--force]

Docker Desktop の Docker.raw とホスト空き容量を確認し、--force 指定時だけ
volume を除外した安全側の prune を実行する。

環境変数:
  DOTFILES_DOCKER_PRUNE_THRESHOLD_GIB  Docker.raw がこの GiB 以上なら image/container/network も prune (既定: 60)
  DOTFILES_DOCKER_MIN_FREE_GIB         ホスト空き容量がこの GiB 以下なら image/container/network も prune (既定: 30)
  DOTFILES_DOCKER_PRUNE_UNTIL          image/container/network の prune 対象期間 (既定: 168h)
  DOTFILES_DOCKER_CACHE_UNTIL          build cache の prune 対象期間 (既定: 168h)
USAGE
}

log() {
  local message="$1"
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S') $message"
  echo "$line"
  if mkdir -p "$LOG_DIR" 2>/dev/null; then
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

gib_from_kib() {
  local kib="$1"
  awk -v kib="$kib" 'BEGIN { printf "%.1f", kib / 1024 / 1024 }'
}

raw_kib() {
  if [ ! -e "$RAW_PATH" ]; then
    echo 0
    return
  fi
  du -sk "$RAW_PATH" | awk '{print $1}'
}

host_free_kib() {
  local target="$RAW_PATH"
  [ -e "$target" ] || target="$HOME"
  df -k "$target" | awk 'NR == 2 {print $4}'
}

docker_ready() {
  [ -S "$HOME/.docker/run/docker.sock" ] || return 1
  curl --max-time 5 --silent --show-error --unix-socket "$HOME/.docker/run/docker.sock" \
    http://localhost/_ping 2>/dev/null | grep -qx OK
}

should_deep_prune() {
  local raw="$1"
  local free="$2"
  awk -v raw="$raw" -v free="$free" -v threshold="$PRUNE_THRESHOLD_GIB" -v minfree="$MIN_FREE_GIB" \
    'BEGIN { exit !((raw >= threshold) || (free <= minfree)) }'
}

run_or_report() {
  if [ "$FORCE" -eq 1 ]; then
    log "実行: $*"
    "$@" 2>&1 | while IFS= read -r line; do
      log "  $line"
    done
  else
    log "dry-run: $*"
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --status)
      MODE="status"
      ;;
    --dry-run)
      MODE="prune"
      FORCE=0
      ;;
    --force)
      MODE="prune"
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "未知の引数です: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

raw_gib="$(gib_from_kib "$(raw_kib)")"
free_gib="$(gib_from_kib "$(host_free_kib)")"

log "Docker.raw=${raw_gib}GiB host_free=${free_gib}GiB threshold=${PRUNE_THRESHOLD_GIB}GiB min_free=${MIN_FREE_GIB}GiB"

if [ "$MODE" = "status" ]; then
  if docker_ready; then
    docker system df
  else
    log "Docker daemon が応答しないため docker system df をスキップ"
  fi
  exit 0
fi

if ! docker_ready; then
  log "Docker daemon が応答しないため prune をスキップ"
  exit 0
fi

run_or_report docker builder prune -af --filter "until=$CACHE_UNTIL"

if should_deep_prune "$raw_gib" "$free_gib"; then
  run_or_report docker container prune -f --filter "until=$PRUNE_UNTIL"
  run_or_report docker network prune -f --filter "until=$PRUNE_UNTIL"
  run_or_report docker image prune -af --filter "until=$PRUNE_UNTIL"
else
  log "深い prune は不要: Docker.raw とホスト空き容量が閾値内"
fi

if [ "$FORCE" -eq 1 ]; then
  log "prune 後の使用量:"
  docker system df 2>&1 | while IFS= read -r line; do
    log "  $line"
  done
fi
