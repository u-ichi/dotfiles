#!/usr/bin/env bash
# 日常の更新スクリプト（symlink 同期 + パッケージ更新）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/permissions.sh"
source "$SCRIPT_DIR/lib/symlink.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/aws.sh"
source "$SCRIPT_DIR/lib/terraform.sh"
source "$SCRIPT_DIR/lib/hermes.sh"
source "$SCRIPT_DIR/lib/gws.sh"
source "$SCRIPT_DIR/lib/python.sh"

MODE="${1:-all}"

update_npm_globals() {
  local npmfile="$SCRIPT_DIR/Npmfile"
  local npm_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/npm"

  if [ -f "$npmfile" ] && command -v npm &>/dev/null; then
    echo "=== npm グローバルパッケージの更新 ==="
    echo ""
    mkdir -p "$npm_cache_dir"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
      echo "更新: $pkg"
      npm --cache "$npm_cache_dir" install -g "$pkg@latest"
    done < "$npmfile"
    echo ""
  fi

  if command -v goalbuddy &>/dev/null; then
    echo "=== GoalBuddy の更新 ==="
    goalbuddy update --json
    goalbuddy agents --force
    if ! goalbuddy extend doctor local-goal-board --json >/dev/null 2>&1; then
      if ! goalbuddy extend install local-goal-board --json; then
        echo "警告: local-goal-board extension のインストールに失敗しました"
      fi
    fi
    echo ""
  fi
}

if [ "$MODE" = "npm" ]; then
  update_npm_globals
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "hermes" ]; then
  echo "=== Hermes Agent セットアップ ==="
  ensure_hermes
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "gws" ]; then
  echo "=== Google Workspace CLI 更新 ==="
  update_gws
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "python" ]; then
  ensure_python_tools
  echo "完了しました"
  exit 0
fi

# === ファイル権限 ===
echo "=== ファイル権限の修復 ==="
fix_permissions
echo "完了"
echo ""

# === symlink ===
echo "=== symlink 同期 ==="
echo ""
sync_links
echo ""

# === アプリケーション設定 ===
echo "=== アプリケーション設定 ==="
ensure_docker_autostart
echo ""

# === AWS config ===
echo "=== AWS config ==="
assemble_aws_config
echo ""

# === Homebrew ===
echo "=== Homebrew パッケージの更新 ==="
echo ""
brew update
brew bundle --file="$SCRIPT_DIR/Brewfile"
brew upgrade
brew upgrade --cask
brew cleanup
echo ""

# === Terraform (tfenv) ===
echo "=== Terraform の更新 ==="
echo ""
ensure_terraform_latest
echo ""

# === npm グローバルパッケージ ===
update_npm_globals

# === Python automation packages ===
ensure_python_tools

echo "完了しました"
