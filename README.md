# dotfiles

macOS 環境の設定ファイルとパッケージを管理するリポジトリ。

## セットアップ

```bash
# Homebrew パッケージのインストール
brew bundle

# 設定ファイルのシンボリックリンク作成
./install.sh
```

## 初回セットアップ後の設定

Git のユーザー情報は `.config/git/config.local` に設定する（リポジトリ管理外）:

```bash
cat > ~/.config/git/config.local <<'EOF'
[user]
    name = Your Name
    email = your@email.com
EOF
```

## 構成

| ファイル/ディレクトリ | 内容 |
|---------------------|------|
| `Brewfile` | Homebrew パッケージ・cask 定義 |
| `.config/tmux/tmux.conf` | tmux 設定 (prefix: Ctrl+A) |
| `.config/fish/` | Fish Shell 設定・関数・プラグイン |
| `.config/git/config` | Git 設定（共通部分） |
| `.config/git/config.local` | Git 設定（個人情報、管理外） |
| `.config/ghostty/config` | Ghostty ターミナル設定 |
| `.config/karabiner/` | Karabiner-Elements キーリマップ |

## セキュリティに関する注意

`install.sh` は外部スクリプト（Claude Code インストーラー、Fisher）を `curl` で取得して実行します。
信頼できるネットワーク環境で実行し、必要に応じてスクリプトの内容を事前に確認してください。
