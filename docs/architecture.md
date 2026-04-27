# dotfiles アーキテクチャ

このリポジトリの内部構成と設計判断をまとめる。
セットアップ手順は [README](../README.md) を参照。

## ディレクトリ構成

```
.
├── install.sh                  # 初回セットアップ (Brewfile + symlink + Claude Code 等)
├── update.sh                   # 日常更新 (symlink 同期 + brew/npm 更新)
├── lint.sh                     # ShellCheck / fish / taplo / json チェック
├── links.conf                  # symlink 定義 (ソース → リンク先の宣言)
├── lib/
│   ├── symlink.sh              #   symlink 作成関数 (links.conf を読み込む)
│   ├── docker.sh               #   Docker Desktop 自動起動の有効化
│   ├── defaults.sh             #   macOS defaults の適用
│   └── aws.sh                  #   AWS config を config.d パターンで組み立て
├── Brewfile                    # Homebrew パッケージ・cask 定義
├── Npmfile                     # npm グローバルパッケージ定義 (任意)
├── .config/
│   ├── fish/                   # Fish Shell 設定
│   │   ├── config.fish         #   メイン設定 (PATH, alias)
│   │   ├── fish_plugins        #   Fisher プラグイン一覧
│   │   ├── completions/        #   補完定義 (gcloud, gsutil)
│   │   └── functions/          #   カスタム関数 (claude/codex/ai-panes 等、テーマ系は .gitignore)
│   ├── git/config              # Git 設定 (共通、個人情報は config.local に分離)
│   ├── ssh/config              # SSH 設定 (Include のみ、ホスト定義は ~/.ssh/config.local に分離)
│   ├── tmux/tmux.conf          # tmux 設定 (prefix: Ctrl+S)
│   ├── ghostty/config          # Ghostty ターミナル設定
│   ├── glow/glow.yml           # Glow (markdown viewer) 設定
│   └── karabiner/              # Karabiner-Elements キーリマップ
├── hooks/
│   └── pre-commit              # Git pre-commit フック (lint.sh 実行)
└── docs/
    └── architecture.md         # 本ドキュメント
```

## 同期方式

設定ファイルはこのリポジトリからホームディレクトリへ **symlink** する方式（Stow 等は不使用）。
`links.conf` にソースとリンク先のペアを宣言し、`lib/symlink.sh` の `sync_links` が読み込む。

| 対象 | 方式 | 理由 |
|------|------|------|
| 一般的な設定ファイル | symlink (`links.conf`) | 編集が即反映され、リポジトリと実環境の乖離が起きない |
| Fish Shell | 個別ファイル単位の symlink | `fisher` 等が自動生成するファイル (`fish_variables`, テーマ系) の repo 混入を防ぐ |
| Fisher プラグイン | `fish_plugins` のみ追跡 + `fisher update` で復元 | プラグイン本体は upstream で管理されるため、リスト管理で十分 |
| AWS config | `config.d/` のスニペットを連結して `~/.aws/config` に書き出す | プロファイルごとに分割管理しつつ、AWS CLI が読む単一ファイルを提供 |

注: Codex CLI 設定 (`~/.codex/config.toml` / `~/.codex/AGENTS.md` / `~/.codex/hooks/` /
`~/.codex/rules/` / `~/.agents/skills/`) は別 repo (claude.codex) で一元管理する。
dotfiles 側では扱わない。詳細は claude.codex の `install.sh` と `docs/architecture.md` 参照。

## スクリプトの責務

| スクリプト | 役割 |
|-----------|------|
| `install.sh` | 初回セットアップ。Brewfile 適用、symlink 作成、Git ローカル設定の対話的入力、Claude Code / mkcert / Fisher / Terraform のインストール、macOS defaults 適用 |
| `update.sh` | 日常運用。symlink 再同期、AWS 設定の再展開、`brew bundle` + `brew upgrade`、Terraform 最新化、Npmfile からの `npm i -g` |
| `lint.sh` | ShellCheck (Bash) / `fish --no-execute` / taplo (TOML) / `python3 -m json.tool` (JSON) を実行。GitHub Actions でも同等のチェックが走る |

`install.sh` と `update.sh` は冪等。何度実行しても安全。

## 個人情報・マシン依存設定の分離

リポジトリには共通設定のみを置き、個人情報やマシン依存の設定は管理外のファイルに分離する。

| 種別 | 管理外ファイル | 生成方法 |
|------|--------------|---------|
| Git のユーザー名・メール | `~/.config/git/config.local` | `install.sh` 初回実行時に対話入力 |
| SSH ホスト定義 | `~/.ssh/config.local` | 手動作成。`.config/ssh/config` から `Include` で読み込み |
| Claude / Codex CLI worktree | `.claude/worktrees/`, `.codex/worktrees/` | 各 fish function の対話セレクタから作成 |
| Fisher テーマ系生成物 | `.config/fish/functions/.bobthefish_*.fish` 等 | `.gitignore` で除外 |

## よくある落とし穴

- **Google Drive 同期で実行権限が落ちる**: `install.sh` / `update.sh` 冒頭で `chmod 755` を再付与している。手動で実行する前にエラーが出たら `bash` 経由で起動するか権限を再付与する
- **Fisher プラグインの自動生成ファイルが repo に混入**: Fish の `functions/` を丸ごと symlink すると bobthefish 等のテーマファイルが repo に書き込まれる。これを防ぐため個別ファイル単位で symlink している（`links.conf` 参照）

## macOS 固有の設定ファイルパス

一部ツールは macOS で XDG (`~/.config/`) ではなく `~/Library/` 以下を既定の設定ファイル置き場にしている。
リポジトリ内は XDG 風の `.config/<tool>/` に統一してツリー見通しを揃え、`links.conf` で OS 側の実パスへ symlink する。

| ツール | macOS 既定の設定パス | 備考 |
|-------|--------------------|------|
| Ghostty | `~/Library/Application Support/com.mitchellh.ghostty/config` | アプリ bundle id ベース |
| Glow | `~/Library/Preferences/glow/glow.yml` | `XDG_CONFIG_HOME` は無視される (確認済み、v2.1.2) |

`~/.config/<tool>/` 配下に置いても読まれないツールがあるため、「リポジトリ内のパス」と「symlink 先のパス」は必ずしも一致しない。`links.conf` の右辺が正となる。
