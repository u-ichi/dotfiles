#!/usr/bin/env bash
# dotfiles の lint を一括実行する（git 管理下のファイルのみ対象）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
errors=0

# git 管理下のファイルを拡張子で抽出する
git_files_by_ext() {
  git -C "$SCRIPT_DIR" ls-files -z | tr '\0' '\n' | grep -E "\.$1$" || true
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
