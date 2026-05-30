#!/usr/bin/env bash
# Google Workspace CLI の明示導入補助

gws_version() {
  gws --version 2>/dev/null || echo "version unknown"
}

ensure_gws() {
  if command -v gws &>/dev/null; then
    echo "済み:     gws ($(gws_version))"
    return 0
  fi

  if ! command -v brew &>/dev/null; then
    echo "エラー: Homebrew がインストールされていません"
    echo "https://brew.sh/ からインストールしてください"
    return 1
  fi

  echo "インストール: Google Workspace CLI (googleworkspace-cli)"
  brew install googleworkspace-cli

  if command -v gws &>/dev/null; then
    echo "完了:     gws ($(gws_version))"
    echo "次に \`gws auth setup\` と \`gws auth login\` で Google Workspace 認証を設定してください"
  else
    echo "警告: gws が PATH 上に見つかりません。新しい shell を開くか Homebrew の PATH を確認してください"
  fi
}

update_gws() {
  if ! command -v brew &>/dev/null; then
    echo "エラー: Homebrew がインストールされていません"
    echo "https://brew.sh/ からインストールしてください"
    return 1
  fi

  if command -v gws &>/dev/null; then
    if brew outdated --quiet googleworkspace-cli | grep -q '^googleworkspace-cli$'; then
      echo "更新:     googleworkspace-cli"
      brew upgrade googleworkspace-cli
    else
      echo "済み:     googleworkspace-cli は最新です"
    fi
    echo "済み:     gws ($(gws_version))"
  else
    ensure_gws
  fi
}
