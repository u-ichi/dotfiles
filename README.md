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

日常の更新は `./update.sh` を実行する。

## 内部構成

ディレクトリ構成、symlink 同期方式、Codex CLI 設定のマネージドブロック方式など
内部設計の詳細は [`docs/architecture.md`](docs/architecture.md) を参照。

## セキュリティに関する注意

`install.sh` は外部スクリプト（Claude Code インストーラー、Fisher）を `curl` で取得して実行します。
信頼できるネットワーク環境で実行し、必要に応じてスクリプトの内容を事前に確認してください。
