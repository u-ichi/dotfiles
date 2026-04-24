#!/usr/bin/env bash
# 日常の更新スクリプト（symlink 同期 + パッケージ更新）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/permissions.sh"
source "$SCRIPT_DIR/lib/symlink.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/codex.sh"
source "$SCRIPT_DIR/lib/aws.sh"
source "$SCRIPT_DIR/lib/terraform.sh"

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

# === Codex CLI 設定 ===
echo "=== Codex CLI 設定 ==="
ensure_codex_config
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
NPMFILE="$SCRIPT_DIR/Npmfile"

if [ -f "$NPMFILE" ] && command -v npm &>/dev/null; then
  echo "=== npm グローバルパッケージの更新 ==="
  echo ""
  while IFS= read -r pkg || [ -n "$pkg" ]; do
    [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
    echo "更新: $pkg"
    npm install -g "$pkg@latest"
  done < "$NPMFILE"
  echo ""
fi

echo "完了しました"
