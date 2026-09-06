# dotfiles

macOS 環境の設定ファイルとパッケージを統合管理するリポジトリ。
Homebrew (Brewfile) でパッケージ管理し、各アプリの設定ファイルをバージョン管理する。

## 作業に応じて読む手順

以下のスキルは、このリポジトリでは Codex も作業手順として読む。
`.claude/skills/` は保存先であり、Claude Code への委譲を意味しない。
スキル一覧への自動表示を前提にせず、該当する変更・インストールの前にリンク先の `SKILL.md` を読む。

| 依頼 | 読む手順 |
|---|---|
| パッケージ・アプリ・ツールの追加、インストール | [pkg-add](.claude/skills/pkg-add/SKILL.md) |
| このリポジトリで管理するツールの設定変更 | [config-edit](.claude/skills/config-edit/SKILL.md) |
| 個人 tap `u-ichi/homebrew-tap` の既存 cask 定義の更新 | [cask-update](.claude/skills/cask-update/SKILL.md) |

Codex は本文の読取・編集・実行を、現在提供されているツールで行う。
`Read` / `Edit` / `Bash`、`allowed-tools`、Claude 向け hook の説明を Codex のツールや権限として扱わない。
承認と commit / push は、現在の実行環境・上位指示・適用される commit スキルに従う。

スキル内の配置方法に古い説明がある場合は、本書のコピー方式と、現在の `copy.conf`・`install.sh` を確認して適用する。
`symlink` による即時反映や `links.conf` への登録を前提にしない。

## パッケージ追加の完了条件

インストール依頼には、このリポジトリの管理ファイルへの登録と、その管理ファイルからの適用を含む。
公式サイトのインストールコマンドはパッケージ情報の確認に使い、実行手順は `pkg-add` に従う。
管理ファイルへの登録、指定経路での適用結果、実機のインストール状態を照合して完了を報告する。
実機に既に存在する場合も、管理ファイルへの登録を確認する。

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

# 個別モジュールの適用例 (対応する MODE は install.sh で確認)
./install.sh fish
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
