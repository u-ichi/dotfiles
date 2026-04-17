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
| `.config/codex/config.toml` | Codex CLI 設定テンプレート（マネージドブロック方式、後述） |
| `lib/codex.sh` | Codex 設定の展開関数 |

## Codex CLI 設定の同期方式

`~/.codex/config.toml` は**マネージドブロック方式**で管理する。
symlink ではなくコピー + 部分置換を使うのは、Codex が TUI 操作時に
`[projects.*]` / `[plugins.*]` をファイル末尾に追記するため、
リポジトリから一方向 symlink できないため。

```
# ====== BEGIN: managed by dotfiles ======
<.config/codex/config.toml の内容で置換される範囲>
# ====== END: managed by dotfiles ======

[projects."..."]      ← Codex が trust を追加した際に自動追記（保持される）
[plugins."..."]       ← Codex がプラグインを有効化した際に自動追記（保持される）
<その他のカスタム追記> ← マーカー外に書けば保持される
```

`install.sh` / `update.sh` で呼ばれる `ensure_codex_config` が以下を行う:

1. **初回インストール**（`~/.codex/config.toml` 未存在）: テンプレートをそのままコピー
2. **マーカーあり**: BEGIN/END の間をテンプレートで丸ごと置換。ブロック外は手つかず
3. **マーカー未検出の既存ファイル**（マイグレーション）:
   - `~/.codex/config.toml.bak.YYYYMMDD-HHMMSS` に自動バックアップ
   - テンプレートを先頭に配置し、既存ファイルから `[projects.*]` / `[plugins.*]` のみ抽出して末尾に追加
   - 上記以外の手動追記は保持されない（バックアップから手で戻す）

用途別 profile（`routine` / `review` / `patch` / `research`）の設計意図は
[claude リポジトリの codex-delegation ルール](../../home/rules/codex-delegation.md) を参照。

## セキュリティに関する注意

`install.sh` は外部スクリプト（Claude Code インストーラー、Fisher）を `curl` で取得して実行します。
信頼できるネットワーク環境で実行し、必要に応じてスクリプトの内容を事前に確認してください。
