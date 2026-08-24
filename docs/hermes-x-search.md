# Hermes Agent X Search CLI

Hermes Agent の `x_search` を、dotfiles 管理の `x-search` fish function から呼び出すための手順。

## 管理方針

- dotfiles で管理するもの:
  - Hermes Agent Desktop の cask 登録 (`Brewfile` の `cask 'hermes-desktop'`)
  - `x-search` fish function (`copy.conf` でコピー)
  - 初回設定と検証手順
- dotfiles で管理しないもの:
  - Hermes 本体のバージョン (デスクトップアプリ起動時の更新に委ねる)
  - `~/.hermes/auth.json`
  - `~/.hermes/config.yaml`
  - `XAI_API_KEY` などの認証情報

OAuth token は Hermes が `~/.hermes/auth.json` に保存する。これは機密情報なのでリポジトリに入れない。

## 導入

`Brewfile` の `cask 'hermes-desktop'` で `/Applications/Hermes.app` が入る。
これはセットアップランチャー (`Hermes-Setup`、bundle ID `com.nousresearch.hermes.setup`) であり、
Hermes 本体ではない。

初回に `/Applications/Hermes.app` を起動すると公式 installer が `--include-desktop` 付きで走り、
次の 3 つを作る。

| 場所 | 中身 |
|------|------|
| `~/.hermes/hermes-agent/` | 本体 (NousResearch/hermes-agent の git clone、main ブランチ) |
| `~/.local/bin/hermes` | CLI ラッパー (`~/.hermes/hermes-agent/venv/bin/python` を exec する) |
| `~/.hermes/hermes-agent/apps/desktop/release/mac-arm64/Hermes.app` | Electron アプリ本体 |

fish の PATH には `~/.local/bin` が含まれているため、新しい shell で `hermes` が見える。
初回導入時に `uv` が `~/.hermes/bin/uv`、`ffmpeg` が Homebrew に導入されることがある。
`ffmpeg` は Brewfile でも管理対象にしている。

## 更新

CLI とデスクトップアプリは同じ git clone を共有するので、版は常に一致する。
更新経路はデスクトップアプリの起動に一本化している。

- `/Applications/Hermes.app` を起動する → 公式 installer が `git pull` し、Electron アプリも再ビルドする。
  既存の `auth.json` / `config.yaml` がある場合、対話が要る stage (`setup` / `gateway`) は skip される
- `hermes update` でも CLI 側の code は更新できるが、Electron アプリは再ビルドされない

`install.sh` は Hermes の版を管理しない (以前の `./install.sh hermes` MODE と `lib/hermes.sh` は廃止した)。
`x-search.fish` のコピーは `copy.conf` が担う。

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

`x-search` は内部で `hermes -t x_search -z` を使い、oneshot 実行でも `x_search` toolset を明示する。
出力では `citations`、`credential_source`、`degraded` を確認する。

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
