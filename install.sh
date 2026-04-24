#!/usr/bin/env bash
# 初回セットアップスクリプト（symlink 作成 + Claude Code インストール）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/permissions.sh"
source "$SCRIPT_DIR/lib/symlink.sh"
source "$SCRIPT_DIR/lib/defaults.sh"
source "$SCRIPT_DIR/lib/docker.sh"
source "$SCRIPT_DIR/lib/codex.sh"
source "$SCRIPT_DIR/lib/aws.sh"
source "$SCRIPT_DIR/lib/terraform.sh"

echo "=== dotfiles 初回セットアップ ==="
echo ""

# === ファイル権限 ===
echo "--- ファイル権限の修復 ---"
fix_permissions
echo "完了"
echo ""

# === Homebrew パッケージ ===
echo "--- Homebrew ---"
if command -v brew &>/dev/null; then
  echo "Brewfile からパッケージをインストールします"
  brew bundle --file="$SCRIPT_DIR/Brewfile"
else
  echo "エラー: Homebrew がインストールされていません"
  echo "https://brew.sh/ からインストールしてください"
  exit 1
fi
echo ""

# === symlink ===
echo "--- symlink ---"
sync_links
echo ""

# === Git ローカル設定 ===
echo "--- Git ローカル設定 ---"
GIT_LOCAL="$HOME/.config/git/config.local"
if [ -f "$GIT_LOCAL" ]; then
  echo "済み:     $GIT_LOCAL"
else
  echo "Git のユーザー情報を設定します"
  read -rp "  名前: " git_name
  read -rp "  メール: " git_email
  mkdir -p "$(dirname "$GIT_LOCAL")"
  cat > "$GIT_LOCAL" <<EOF
[user]
	name = $git_name
	email = $git_email
EOF
  echo "作成:     $GIT_LOCAL"
fi
echo ""

# === AWS config ===
echo "--- AWS config ---"
assemble_aws_config
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

# === Terraform (tfenv) ===
echo "--- Terraform ---"
ensure_terraform_latest
echo ""

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
