#!/usr/bin/env bash
# Hermes Agent の明示導入補助

ensure_hermes() {
  if command -v hermes &>/dev/null; then
    echo "済み:     hermes ($(hermes --version 2>/dev/null || echo 'version unknown'))"
    return 0
  fi

  echo "インストール: Hermes Agent"
  echo "公式 installer を取得して実行します"
  local tmpfile
  tmpfile="$(mktemp)"
  curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o "$tmpfile"
  bash "$tmpfile"
  rm -f "$tmpfile"

  if command -v hermes &>/dev/null; then
    echo "完了:     hermes ($(hermes --version 2>/dev/null || echo 'version unknown'))"
    echo "次に \`hermes auth add xai-oauth\` または \`hermes model\` で xAI OAuth を設定してください"
  else
    echo "警告: hermes が PATH 上に見つかりません。新しい shell を開くか ~/.local/bin を PATH に含めてください"
  fi
}
