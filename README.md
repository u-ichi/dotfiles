# dotfiles

macOS 環境の設定ファイルとパッケージを管理するリポジトリ。

## セットアップ

[Homebrew](https://brew.sh/) をインストールした状態で以下を実行する:

```bash
git clone git@github.com:u-ichi/dotfiles.git
cd dotfiles
./install.sh
```

`install.sh` が以下を一括で行う:

1. Brewfile からパッケージをインストール
2. 設定ファイルの symlink を作成
3. Git のユーザー情報を対話的に設定（`~/.config/git/config.local`）
4. Claude Code / mkcert / Fisher をインストール
5. macOS defaults を適用

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
