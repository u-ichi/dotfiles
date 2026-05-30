# Google Workspace CLI (`gws`)

Google Workspace API を terminal から扱うための `gws` CLI は Homebrew と dotfiles の
`install.sh` で管理する。

```bash
./install.sh gws
```

初回認証は手元の shell で実行する。

```bash
gws auth setup
gws auth login
```

認証情報は `gws` 側の設定ディレクトリや OS keyring に保存される。OAuth token、credential
file、service account key はこのリポジトリに置かない。

通常の `./install.sh` でも `Brewfile` 経由で `googleworkspace-cli` は管理対象に
含まれる。`gws` だけを明示的に入れる/更新する時は上記の専用 mode を使う。

## Codex からの利用方針

Codex から Google Sheets / Spreadsheet を読み書きする時は `gws` を優先する。
特に書き込み、追記、更新は既存 Google connector ではなく `gws` 経由に寄せる。

実行前に確認すること:

```bash
command -v gws
gws --help
gws sheets --help
```

Sheets の範囲指定には `!` が含まれるため、shell では single quote で囲む。

```bash
gws sheets spreadsheets values get \
  --params '{"spreadsheetId":"<spreadsheet-id>","range":"Sheet1!A1:C10"}'
```

書き込み時は、対象 spreadsheet ID、range、操作種別、書き込む行数を確認してから実行する。
