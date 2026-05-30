#!/usr/bin/env bash
# dotfiles 同期スクリプト（初回セットアップ + 日常更新）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/permissions.sh"
source "$SCRIPT_DIR/lib/symlink.sh"
source "$SCRIPT_DIR/lib/defaults.sh"
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
    echo "--- npm グローバルパッケージ ---"
    mkdir -p "$npm_cache_dir"
    while IFS= read -r pkg || [ -n "$pkg" ]; do
      [[ -z "$pkg" || "$pkg" =~ ^# ]] && continue
      echo "更新: $pkg"
      npm --cache "$npm_cache_dir" install -g "$pkg@latest"
    done < "$npmfile"
    echo ""
  fi
}

sync_homebrew() {
  if ! command -v brew &>/dev/null; then
    echo "エラー: Homebrew がインストールされていません"
    echo "https://brew.sh/ からインストールしてください"
    exit 1
  fi

  echo "--- Homebrew ---"
  brew update
  brew bundle --file="$SCRIPT_DIR/Brewfile"
  brew cleanup
  echo ""
}

if [ "$MODE" = "hermes" ]; then
  echo "=== Hermes Agent セットアップ ==="
  ensure_hermes
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "gws" ]; then
  echo "=== Google Workspace CLI 同期 ==="
  update_gws
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "python" ]; then
  ensure_python_tools
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "npm" ]; then
  update_npm_globals
  echo "完了しました"
  exit 0
fi

if [ "$MODE" != "all" ]; then
  echo "エラー: 未知の MODE です: $MODE"
  echo "利用可能: all, hermes, gws, python, npm"
  exit 1
fi

echo "=== dotfiles 同期 ==="
echo ""

# === ファイル権限 ===
echo "--- ファイル権限の修復 ---"
fix_permissions
echo "完了"
echo ""

# === Homebrew ===
sync_homebrew

# === 設定ファイルコピー ===
echo "--- 設定ファイルコピー ---"
sync_files
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

# === npm グローバルパッケージ ===
update_npm_globals

# === Python automation packages ===
ensure_python_tools

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

# === macOS defaults ===
echo "--- macOS defaults ---"
apply_defaults
echo ""

# === アプリケーション設定 ===
echo "--- アプリケーション設定 ---"
ensure_docker_autostart
echo ""

echo "完了しました"
echo "以降も ./install.sh で設定ファイルコピーとパッケージを同期してください"
