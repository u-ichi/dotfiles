#!/usr/bin/env bash
# dotfiles の lint を一括実行する（git 管理下のファイルのみ対象）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
errors=0

# git 管理下のファイルを拡張子で抽出する
git_files_by_ext() {
  git -C "$SCRIPT_DIR" ls-files -z | tr '\0' '\n' | grep -E "\.$1$" | while IFS= read -r f; do
    [ -f "$SCRIPT_DIR/$f" ] && printf '%s\n' "$f"
  done || true
}

# === ShellCheck (Bash) ===
echo "=== ShellCheck ==="
if command -v shellcheck &>/dev/null; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "  $f"
    shellcheck -x "$SCRIPT_DIR/$f" || errors=$((errors + 1))
  done <<< "$(git_files_by_ext sh)"
else
  echo "  スキップ: shellcheck がインストールされていません (brew install shellcheck)"
fi
echo ""

# === Fish 構文チェック ===
echo "=== Fish ==="
if command -v fish &>/dev/null; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "  $f"
    fish --no-execute "$SCRIPT_DIR/$f" || errors=$((errors + 1))
  done <<< "$(git_files_by_ext fish)"
else
  echo "  スキップ: fish がインストールされていません"
fi
echo ""

# === Fish smoke tests ===
echo "=== Fish smoke tests ==="
if command -v fish &>/dev/null; then
  fish -c "source '$SCRIPT_DIR/.config/fish/functions/__ai_pane_title_sync.fish'; source '$SCRIPT_DIR/.config/fish/functions/codex.fish'; __codex_set_pane_base_title" || errors=$((errors + 1))
else
  echo "  スキップ: fish がインストールされていません"
fi
echo ""

# === tmux isolated tests ===
echo "=== tmux isolated tests ==="
if command -v tmux &>/dev/null && command -v fish &>/dev/null; then
  "$SCRIPT_DIR/.config/tmux/test-ai-sidebars-isolated.sh" || errors=$((errors + 1))
  "$SCRIPT_DIR/.config/tmux/test-agmsg-tmux-scope-isolated.sh" || errors=$((errors + 1))
else
  echo "  スキップ: tmux または fish がインストールされていません"
fi
echo ""

# === tmux safety guard ===
echo "=== tmux safety guard ==="
"$SCRIPT_DIR/scripts/check-tmux-safety.sh" --all || errors=$((errors + 1))
echo ""

# === taplo (TOML) ===
echo "=== TOML ==="
if command -v taplo &>/dev/null; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "  $f"
    taplo check "$SCRIPT_DIR/$f" || errors=$((errors + 1))
  done <<< "$(git_files_by_ext toml)"
else
  echo "  スキップ: taplo がインストールされていません (brew install taplo)"
fi
echo ""

# === Git config ===
echo "=== Git config ==="
# shellcheck disable=SC2088,SC2016
expected_git_include_path='~/.config/git/config.local'
# shellcheck disable=SC2016
expected_git_local_assignment='GIT_LOCAL="$HOME/.config/git/config.local"'
git_include_path="$(git -C "$SCRIPT_DIR" config --file "$SCRIPT_DIR/.config/git/config" --get include.path || true)"
if [ "$git_include_path" != "$expected_git_include_path" ]; then
  echo "  エラー: .config/git/config の include.path が ~/.config/git/config.local ではありません: $git_include_path"
  errors=$((errors + 1))
fi
if ! grep -Fq "$expected_git_local_assignment" "$SCRIPT_DIR/install.sh"; then
  echo "  エラー: install.sh の Git ローカル設定生成先が ~/.config/git/config.local ではありません"
  errors=$((errors + 1))
fi
echo ""

# === JSON (python3 組み込み) ===
echo "=== JSON ==="
while IFS= read -r f; do
  [ -z "$f" ] && continue
  echo "  $f"
  python3 -m json.tool "$SCRIPT_DIR/$f" > /dev/null || errors=$((errors + 1))
done <<< "$(git_files_by_ext json)"
echo ""

if [ "$errors" -gt 0 ]; then
  echo "エラー: $errors 件の問題が見つかりました"
  exit 1
fi
echo "すべてのチェックに通過しました"
