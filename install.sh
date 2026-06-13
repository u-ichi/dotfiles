#!/usr/bin/env bash
# dotfiles 同期スクリプト（初回セットアップ + 日常更新）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/permissions.sh"
source "$SCRIPT_DIR/lib/copy.sh"
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

# Homebrew Cask の codex バイナリは quarantine + notarization 未対応で
# macOS 26 Tahoe の Gatekeeper が _dyld_start でハングする (openai/codex#17447)。
# in-place の xattr -cr / codesign では解消しない (quarantine DB が path を記憶)。
# コピー + xattr クリア + ad-hoc 再署名で回避する。
fix_codex_quarantine() {
  local brew_link="/opt/homebrew/bin/codex"
  [[ -e "$brew_link" ]] || return 0

  local real_bin
  real_bin="$(readlink "$brew_link" 2>/dev/null || true)"
  [[ "$real_bin" == "$HOME/.local/bin/codex" ]] && {
    echo "済み:     codex quarantine 対策"
    return 0
  }

  local cask_bin
  cask_bin="$(realpath "$brew_link" 2>/dev/null || true)"
  [[ -x "$cask_bin" ]] || return 0

  local cask_dir
  cask_dir="$(dirname "$cask_bin")"
  if ! xattr -l "$cask_dir" 2>/dev/null | grep -q 'com.apple.quarantine'; then
    echo "済み:     codex quarantine なし"
    return 0
  fi

  echo "修正:     codex quarantine 対策 (Caskroom → ~/.local/bin)"
  mkdir -p "$HOME/.local/bin"
  cp "$cask_bin" "$HOME/.local/bin/codex"
  xattr -c "$HOME/.local/bin/codex" 2>/dev/null || true
  codesign --force --sign - "$HOME/.local/bin/codex" 2>/dev/null || true
  chmod +x "$HOME/.local/bin/codex"
  ln -sf "$HOME/.local/bin/codex" "$brew_link"
  echo "          $brew_link → $HOME/.local/bin/codex"
}

sync_fish_files() {
  for entry in "${COPY_ENTRIES[@]}"; do
    local src="${entry%%:*}"
    local dest="${entry#*:}"
    if [[ "$src" == .config/fish/* ]]; then
      copy_item "$src" "$dest"
    fi
  done
}

# Karabiner-Elements は ~/.config/karabiner を FSEvents で監視し karabiner.json の変更を
# 自動 reload するが、公式 docs によれば (1) 親ディレクトリを作り直すと監視が外れる、
# (2) karabiner.json を symlink にすると検知しない、という制約がある。install.sh のコピーは
# 親 dir 再作成やバックアップ mv を挟むことがあり監視が外れ得るため、コピー後に
# console_user_server を明示再起動して確実に再読み込みさせる。
# 参考: https://karabiner-elements.pqrs.org/docs/manual/misc/configuration-file-path/
reload_karabiner() {
  if ! pgrep -qf karabiner_console_user_server; then
    echo "スキップ: Karabiner 未起動 (次回 Karabiner 起動時に反映)"
    return 0
  fi
  echo "再読込:   Karabiner console_user_server を再起動"
  launchctl kickstart -k "gui/$(id -u)/org.pqrs.service.agent.karabiner_console_user_server" 2>/dev/null \
    || echo "  警告: 再起動に失敗。Karabiner-Elements を手動で再起動してください"
}

# karabiner.json をコピーし、内容が変わったときだけ Karabiner を reload する。
sync_karabiner() {
  local dest_json="$HOME/.config/karabiner/karabiner.json"
  local before="" after=""
  [ -f "$dest_json" ] && before="$(shasum "$dest_json" 2>/dev/null | awk '{print $1}')"

  copy_item ".config/karabiner" "$HOME/.config/karabiner"

  [ -f "$dest_json" ] && after="$(shasum "$dest_json" 2>/dev/null | awk '{print $1}')"

  if [ "$before" != "$after" ]; then
    reload_karabiner
  else
    echo "済み:     Karabiner 設定変更なし (reload 不要)"
  fi
}

restore_fisher_plugins() {
  echo "--- Fisher ---"
  if command -v fish &>/dev/null; then
    if fish -c "type -q fisher" 2>/dev/null; then
      echo "更新:     Fisher プラグイン"
      fish -c "fisher update"
    else
      echo "インストール: Fisher + プラグイン"
      fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher update"
    fi
  else
    echo "スキップ: fish がインストールされていません"
  fi
  echo ""
}

sync_hermes_files() {
  echo "--- Hermes Agent 関連ファイル ---"
  copy_item ".config/fish/functions/x-search.fish" "$HOME/.config/fish/functions/x-search.fish"
  echo ""
}

if [ "$MODE" = "hermes" ]; then
  echo "=== Hermes Agent セットアップ ==="
  ensure_hermes
  sync_hermes_files
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

if [ "$MODE" = "fish" ]; then
  echo "=== Fish 設定同期 ==="
  echo "--- Fish 設定ファイルコピー ---"
  sync_fish_files
  echo ""
  restore_fisher_plugins
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "karabiner" ]; then
  echo "=== Karabiner 設定同期 ==="
  sync_karabiner
  echo "完了しました"
  exit 0
fi

if [ "$MODE" = "docker" ]; then
  echo "=== Docker 設定同期 ==="
  ensure_docker_autostart
  install_docker_disk_maintenance
  echo "完了しました"
  exit 0
fi

if [ "$MODE" != "all" ]; then
  echo "エラー: 未知の MODE です: $MODE"
  echo "利用可能: all, hermes, gws, python, npm, fish, karabiner, docker"
  exit 1
fi

echo "=== dotfiles 同期 ==="
echo ""

# === 旧 Git config リンク移行 ===
cleanup_legacy_git_config_symlink
echo ""

# === ファイル権限 ===
echo "--- ファイル権限の修復 ---"
fix_permissions
echo "完了"
echo ""

# === Homebrew ===
sync_homebrew

# === Codex quarantine 対策 ===
echo "--- Codex CLI ---"
fix_codex_quarantine
echo ""

# === Hermes Agent ===
echo "--- Hermes Agent ---"
ensure_hermes
echo ""

# === 設定ファイルコピー ===
echo "--- 設定ファイルコピー ---"
sync_files
echo ""

# === Karabiner (コピー + 変更時のみ明示 reload) ===
echo "--- Karabiner ---"
sync_karabiner
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

# === Google Workspace CLI ===
echo "--- Google Workspace CLI ---"
update_gws
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

restore_fisher_plugins

# === macOS defaults ===
echo "--- macOS defaults ---"
apply_defaults
echo ""

# === アプリケーション設定 ===
echo "--- アプリケーション設定 ---"
ensure_docker_autostart
install_docker_disk_maintenance
echo ""

echo "完了しました"
echo "以降も ./install.sh で設定ファイルコピーとパッケージを同期してください"
