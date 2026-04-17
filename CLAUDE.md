# dotfiles

macOS 環境の設定ファイルとパッケージを統合管理するリポジトリ。
Homebrew (Brewfile) でパッケージ管理し、各アプリの設定ファイルをバージョン管理する。

## 技術スタック

- macOS (Homebrew)
- Fish Shell (bob-the-fish テーマ, Fisher)
- Ghostty (Catppuccin テーマ, Moralerspace Neon)
- Neovim (vi/vim エイリアスで使用)
- tmux (prefix: Ctrl+S)
- Karabiner-Elements (キーリマップ)
- Raycast (ランチャー・拡張)
- Git (vimdiff, LFS, Azure DevOps 対応)

## ビルド・実行

```bash
# 初回セットアップ (symlink + Claude Code インストール)
./install.sh

# 日常の更新 (symlink 同期 + brew/npm 更新)
./update.sh

# パッケージインストール (Brewfile のみ)
brew bundle
```

## テスト

テストフレームワークなし。変更後は対象ツールを起動して動作確認する。

## リント

```bash
./lint.sh
```

ShellCheck (Bash), `fish --no-execute` (Fish), taplo (TOML), python3 json.tool (JSON) を実行する。
GitHub Actions (`push` / `PR` on `main`) でも同等のチェックが走る。

## アーキテクチャ

```
.
├── install.sh                  # 初回セットアップ (symlink + Claude Code)
├── update.sh                   # 日常更新 (symlink 同期 + brew/npm)
├── links.conf                  # symlink 定義 (ソース → リンク先の宣言)
├── lib/
│   ├── symlink.sh              #   symlink 作成関数 (links.conf を読み込む)
│   └── codex.sh                #   Codex CLI 設定の展開関数
├── Brewfile                    # Homebrew パッケージ・cask 定義
├── .config/
│   ├── codex/config.toml       # Codex CLI 設定テンプレート (マネージドブロック方式で ~/.codex/config.toml に展開)
│   ├── fish/                   # Fish Shell 設定
│   │   ├── config.fish         #   メイン設定 (PATH, alias)
│   │   ├── fish_plugins        #   Fisher プラグイン一覧
│   │   ├── completions/        #   補完定義 (gcloud, gsutil)
│   │   └── functions/          #   カスタム関数 (claude.fish 等、テーマ系は .gitignore)
│   ├── git/config              # Git 設定 (共通、個人情報は config.local に分離)
│   ├── ssh/config              # SSH 設定 (Include のみ、ホスト定義は ~/.ssh/config.local に分離)
│   ├── tmux/tmux.conf          # tmux 設定
│   ├── ghostty/config          # Ghostty ターミナル設定
│   └── karabiner/              # Karabiner-Elements キーリマップ
└── .claude/                    # Claude Code プロジェクト設定
```

設定ファイルはこのリポジトリからホームディレクトリへ symlink する方式（Stow 等は不使用）。
Fish は個別ファイル単位で symlink し、自動生成ファイル（bobthefish, fisher）の repo 混入を防ぐ。
Fisher プラグインは `fish_plugins` のみ追跡し、`fisher update` で復元する。

### Codex CLI のマネージドブロック方式

`~/.codex/config.toml` は symlink ではなくコピー + 部分置換で管理する
（Codex が TUI 操作時に `[projects.*]` / `[plugins.*]` をファイル末尾に追記するため、
一方向 symlink できない）。

テンプレート `.config/codex/config.toml` は BEGIN/END マーカーで囲まれており、
`ensure_codex_config`（`lib/codex.sh`）が以下を行う:

- 初回インストール: テンプレートをそのままコピー
- マーカーあり: BEGIN/END の間をテンプレートで丸ごと置換。ブロック外は手つかず
- マーカー未検出の既存ファイル: 自動バックアップ（`*.bak.YYYYMMDD-HHMMSS`）後、
  テンプレートを先頭に配置し、既存ファイルから `[projects.*]` / `[plugins.*]` のみ抽出して末尾に追加

ユーザーが追加の Codex 設定を手で書く場合はマーカーの**外側**に書く（上書きされない）。
用途別 profile の設計意図は claude リポジトリの `home/rules/codex-delegation.md` を参照。

## プロジェクト固有の規約

- Brewfile: `brew` (CLI) と `cask` (GUI) を分けて記述する
- 設定ファイルのコメントは日本語で書く
- Fish の functions/ 配下のテーマファイル (bobthefish, fisher) は .gitignore で除外済み
- `claude.fish` はカスタム関数（Claude Code worktree の対話的セレクタ）
