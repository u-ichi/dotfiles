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
6. 日次メンテナンス LaunchAgent を登録

Fish 設定と Fisher プラグインだけを復元する場合:

```bash
./install.sh fish
```

日次メンテナンスだけを同期し直す場合:

```bash
./install.sh maintenance
```

Slack 投稿を有効にするには `~/.config/dotfiles-maintenance/env` に Bot token と channel ID を設定する。
`install.sh maintenance` は env file が無い場合にテンプレートを作る。

## Antigravity CLI

Antigravity CLI だけを導入し、管理する設定を適用する場合:

```bash
./install.sh antigravity
agy
```

専用モードは未導入時に Homebrew の `antigravity-cli` をインストールし、導入済みの版は更新しない。
更新は通常の `./install.sh` による Homebrew 全体の更新に含まれる。

個人の AI Pro を使う場合は、初回起動で `Google OAuth` を選び、AI Pro を契約している個人アカウントでログインする。
Orca ではエージェント一覧の `Antigravity`（起動コマンド `agy`）を使う。
CLI に `Google AI Pro` と表示されることと、`/usage` で利用枠を確認する。

追加クレジット消費とデータ収集はオフ、Sandbox Mode はオン、ツールの承認方式は `request-review` として管理する。
初期設定を終えた後に `/settings` を開き、`Use AI Credits` と `Enable Telemetry` がともに `off`、`Sandbox Mode` が `on`、`Tool Permission` が `request-review` であることを確認する。
設定を再適用する場合は CLI を終了して `./install.sh antigravity` を実行し、再起動する。
管理ファイルにはメールアドレスや認証情報を保存しない。
管理元と適用先は[アーキテクチャ資料](docs/architecture.md#antigravity-cli-の設定同期)を参照。

## 内部構成

ディレクトリ構成、設定ファイルコピー方式など内部設計の詳細は
[`docs/architecture.md`](docs/architecture.md) を参照。

## セキュリティに関する注意

`install.sh` は外部スクリプト（Claude Code インストーラー、Fisher）を `curl` で取得して実行します。
信頼できるネットワーク環境で実行し、必要に応じてスクリプトの内容を事前に確認してください。
