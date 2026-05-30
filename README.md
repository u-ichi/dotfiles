# dotfiles

macOS 環境の設定ファイルとパッケージを管理するリポジトリ。

## セットアップ

[Homebrew](https://brew.sh/) をインストールした状態で以下を実行する:

```bash
git clone git@github.com:u-ichi/dotfiles.git
cd dotfiles
./install.sh
```

`install.sh` が初回セットアップと日常更新を一括で行う:

1. Brewfile からパッケージをインストール / 更新
2. 設定ファイルを `~/` 配下へコピー
3. Git のユーザー情報を対話的に設定（`~/.config/git/config.local`）
4. Claude Code / mkcert / Fisher を必要に応じてインストール
5. macOS defaults を適用

Fish 設定と Fisher プラグインだけを復元する場合:

```bash
./install.sh fish
```

## 内部構成

ディレクトリ構成、設定ファイルコピー方式など内部設計の詳細は
[`docs/architecture.md`](docs/architecture.md) を参照。

## セキュリティに関する注意

`install.sh` は外部スクリプト（Claude Code インストーラー、Fisher）を `curl` で取得して実行します。
信頼できるネットワーク環境で実行し、必要に応じてスクリプトの内容を事前に確認してください。
