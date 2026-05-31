# dotfiles

macOS 環境の設定ファイルとパッケージを統合管理するリポジトリ。
Homebrew (Brewfile) でパッケージ管理し、各アプリの設定ファイルをバージョン管理する。

## 技術スタック

- macOS (Homebrew)
- Fish Shell (bob-the-fish テーマ, Fisher)
- Ghostty (Catppuccin テーマ, Moralerspace Neon)
- Neovim (vi/vim エイリアスで使用)
- tmux (prefix: Ctrl+A)
- Karabiner-Elements (キーリマップ)
- Raycast (ランチャー・拡張)
- Git (vimdiff, LFS, Azure DevOps 対応)

## ビルド・実行

```bash
# 初回セットアップ / 日常更新 (設定ファイルコピー + brew/npm 更新)
./install.sh

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

**配置は symlink ではなく「コピー方式」**（`copy.conf` がソース→コピー先を宣言）。
`.config/...` を編集しても、live (`~/...`) に反映されるのは
`./install.sh`（または該当 MODE、例: fish だけなら `./install.sh fish`）で**再コピーした後**。
repo 編集 = 即反映ではない。symlink 前提で「編集したから live も変わったはず」と判断しないこと。

ディレクトリ構成、設定ファイルコピー方式、スクリプトの責務、Codex マネージドブロック方式の詳細は
[`docs/architecture.md`](docs/architecture.md) を参照。

## プロジェクト固有の規約

- Brewfile: `brew` (CLI) と `cask` (GUI) を分けて記述する
- 設定ファイルのコメントは日本語で書く
- Fish の functions/ 配下のテーマファイル (bobthefish, fisher) は .gitignore で除外済み
- `claude.fish` はカスタム関数（Claude Code worktree の対話的セレクタ）
