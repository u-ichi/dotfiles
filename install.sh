#!/usr/bin/env bash
# 初回セットアップスクリプト（symlink 作成 + Claude Code インストール）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/symlink.sh"
source "$SCRIPT_DIR/lib/defaults.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/codex.sh"

echo "=== dotfiles 初回セットアップ ==="
echo ""

# === symlink ===
echo "--- symlink ---"
sync_links
echo ""

# === Claude Code (ネイティブインストーラー) ===
echo "--- Claude Code ---"
if command -v claude &>/dev/null; then
  echo "済み:     claude ($(claude --version 2>/dev/null || echo '不明'))"
else
  echo "インストール: Claude Code"
  tmpfile="$(mktemp)"
  curl -fsSL https://claude.ai/install.sh -o "$tmpfile"
  echo "ダウンロード完了: $tmpfile"
  bash "$tmpfile"
  rm -f "$tmpfile"
fi

# === mkcert (ローカル TLS 証明書) ===
echo "--- mkcert ---"
if command -v mkcert &>/dev/null; then
  echo "済み:     mkcert"
else
  echo "インストール: mkcert"
  brew install mkcert
fi
# ローカル CA をシステムに登録（未登録なら）
mkcert -install 2>/dev/null || true

# === Fisher プラグイン復元 ===
echo "--- Fisher ---"
if command -v fish &>/dev/null; then
  if fish -c "type -q fisher" 2>/dev/null; then
    echo "済み:     fisher"
  else
    echo "インストール: Fisher + プラグイン"
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher update"
  fi
else
  echo "スキップ: fish がインストールされていません"
fi

# === Codex CLI 設定 ===
echo "--- Codex CLI ---"
ensure_codex_config
echo ""

# === macOS defaults ===
echo "--- macOS defaults ---"
apply_defaults
echo ""

# === アプリケーション設定 ===
echo "--- アプリケーション設定 ---"
ensure_docker_autostart
echo ""

echo "完了しました"
echo "以降は update.sh で symlink とパッケージを更新してください"
