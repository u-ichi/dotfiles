# Hermes Agent X Search CLI

Hermes Agent の `x_search` を、dotfiles 管理の `x-search` fish function から呼び出すための手順。

## 管理方針

- dotfiles で管理するもの:
  - Hermes Agent の明示導入補助
  - `x-search` fish function
  - 初回設定と検証手順
- dotfiles で管理しないもの:
  - `~/.hermes/auth.json`
  - `~/.hermes/config.yaml`
  - `XAI_API_KEY` などの認証情報

OAuth token は Hermes が `~/.hermes/auth.json` に保存する。これは機密情報なのでリポジトリに入れない。

## 導入

通常の `install.sh` では Hermes を自動導入しない。
導入する場合だけ、明示的に次を実行する。

```bash
./install.sh hermes
```

Hermes の公式 installer は `~/.hermes/hermes-agent/` に本体を置き、`~/.local/bin/hermes` を作る。
fish の PATH には `~/.local/bin` が含まれているため、新しい shell で `hermes` が見える。
初回導入時に `uv` が `~/.local/bin/uv`、`ffmpeg` が Homebrew に導入されることがある。
`ffmpeg` は Brewfile でも管理対象にしている。

## 初回認証

xAI OAuth を設定する。

```bash
hermes auth add xai-oauth
```

またはモデル選択 UI から設定する。

```bash
hermes model
```

`xAI Grok OAuth (SuperGrok Subscription)` を選び、ブラウザで `accounts.x.ai` の承認を完了する。
完了後、認証情報は `~/.hermes/auth.json` に保存される。

## X Search の有効化

`x_search` は既定で無効なので、`hermes tools` で有効化する。

```bash
hermes tools
```

`X (Twitter) Search` を選び、`xAI Grok OAuth (SuperGrok Subscription)` を指定する。
OAuth と `XAI_API_KEY` の両方がある場合、Hermes は OAuth を優先する。

## 使い方

```fish
x-search "OpenAI Codex CLI の直近アップデート"
```

`x-search` は内部で `hermes -z` を使い、`x_search` tool を使うように指示する。
出力では `citations` と `credential_source` を確認する。

## 検証

```bash
command -v hermes
hermes doctor
command -v uv
command -v ffmpeg
fish --no-execute .config/fish/functions/x-search.fish
./lint.sh
```

実検索は OAuth 完了後に実行する。

```fish
x-search "Hermes Agent x_search Grok OAuth"
```

期待結果:

- X 検索に基づく回答が返る
- citations が含まれる
- `credential_source` が `xai-oauth` になっている

## 参照

- Hermes installation: https://hermes-agent.nousresearch.com/docs/getting-started/installation/
- xAI Grok OAuth: https://hermes-agent.nousresearch.com/docs/guides/xai-grok-oauth
- CLI commands: https://github.com/nousresearch/hermes-agent/blob/main/website/docs/reference/cli-commands.md
