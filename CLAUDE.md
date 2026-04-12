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

リントツールなし。

## アーキテクチャ

```
.
├── install.sh                  # 初回セットアップ (symlink + Claude Code)
├── update.sh                   # 日常更新 (symlink 同期 + brew/npm)
├── lib/
│   ├── symlink.sh              #   symlink 定義・作成関数 (共通)
│   └── codex.sh                #   Codex CLI 設定の展開関数
├── Brewfile                    # Homebrew パッケージ・cask 定義
├── .config/
│   ├── fish/                   # Fish Shell 設定
│   │   ├── config.fish         #   メイン設定 (PATH, alias)
│   │   ├── fish_plugins        #   Fisher プラグイン一覧
│   │   ├── completions/        #   補完定義 (gcloud, gsutil)
│   │   └── functions/          #   カスタム関数 (claude.fish 等、テーマ系は .gitignore)
│   ├── git/config              # Git 設定 (共通、個人情報は config.local に分離)
│   ├── tmux/tmux.conf          # tmux 設定
│   ├── ghostty/config          # Ghostty ターミナル設定
│   └── karabiner/              # Karabiner-Elements キーリマップ
└── .claude/                    # Claude Code プロジェクト設定
```

設定ファイルはこのリポジトリからホームディレクトリへ symlink する方式（Stow 等は不使用）。
Fish は個別ファイル単位で symlink し、自動生成ファイル（bobthefish, fisher）の repo 混入を防ぐ。
Fisher プラグインは `fish_plugins` のみ追跡し、`fisher update` で復元する。

## プロジェクト固有の規約

- Brewfile: `brew` (CLI) と `cask` (GUI) を分けて記述する
- 設定ファイルのコメントは日本語で書く
- Fish の functions/ 配下のテーマファイル (bobthefish, fisher) は .gitignore で除外済み
- `claude.fish` はカスタム関数（Claude Code worktree の対話的セレクタ）
