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
│   ├── codex.sh                #   Codex CLI 設定の展開関数
│   ├── docker.sh               #   Docker Desktop 自動起動の有効化
│   ├── defaults.sh             #   macOS defaults の適用
│   └── aws.sh                  #   AWS config を config.d パターンで組み立て
├── Brewfile                    # Homebrew パッケージ・cask 定義
├── Npmfile                     # npm グローバルパッケージ定義 (任意)
├── .config/
│   ├── codex/config.toml       # Codex CLI 設定テンプレート (マネージドブロック方式)
│   ├── fish/                   # Fish Shell 設定
│   │   ├── config.fish         #   メイン設定 (PATH, alias)
│   │   ├── fish_plugins        #   Fisher プラグイン一覧
│   │   ├── completions/        #   補完定義 (gcloud, gsutil)
│   │   └── functions/          #   カスタム関数 (claude.fish 等、テーマ系は .gitignore)
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
| Codex CLI 設定 | コピー + マネージドブロック置換 | Codex が TUI 操作時に設定ファイル末尾を書き換えるため、symlink できない |
| AWS config | `config.d/` のスニペットを連結して `~/.aws/config` に書き出す | プロファイルごとに分割管理しつつ、AWS CLI が読む単一ファイルを提供 |

## スクリプトの責務

| スクリプト | 役割 |
|-----------|------|
| `install.sh` | 初回セットアップ。Brewfile 適用、symlink 作成、Git ローカル設定の対話的入力、Claude Code / mkcert / Fisher / Terraform のインストール、macOS defaults 適用 |
| `update.sh` | 日常運用。symlink 再同期、Codex/AWS 設定の再展開、`brew bundle` + `brew upgrade`、Terraform 最新化、Npmfile からの `npm i -g` |
| `lint.sh` | ShellCheck (Bash) / `fish --no-execute` / taplo (TOML) / `python3 -m json.tool` (JSON) を実行。GitHub Actions でも同等のチェックが走る |

`install.sh` と `update.sh` は冪等。何度実行しても安全。

## Codex CLI 設定の同期方式

`~/.codex/config.toml` は **マネージドブロック方式** で管理する。
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

`install.sh` / `update.sh` で呼ばれる `ensure_codex_config`（`lib/codex.sh`）が以下を行う:

1. **初回インストール**（`~/.codex/config.toml` 未存在）: テンプレートをそのままコピー
2. **マーカーあり**: BEGIN/END の間をテンプレートで丸ごと置換。ブロック外は手つかず
3. **マーカー未検出の既存ファイル**（マイグレーション）:
   - `~/.codex/config.toml.bak.YYYYMMDD-HHMMSS` に自動バックアップ
   - テンプレートを先頭に配置し、既存ファイルから `[projects.*]` / `[plugins.*]` のみ抽出して末尾に追加
   - 上記以外の手動追記は保持されない（バックアップから手で戻す）

用途別 profile（`routine` / `review` / `patch` / `research`）の設計意図は
[claude リポジトリの codex-delegation ルール](../../../home/rules/codex-delegation.md) を参照。

## 個人情報・マシン依存設定の分離

リポジトリには共通設定のみを置き、個人情報やマシン依存の設定は管理外のファイルに分離する。

| 種別 | 管理外ファイル | 生成方法 |
|------|--------------|---------|
| Git のユーザー名・メール | `~/.config/git/config.local` | `install.sh` 初回実行時に対話入力 |
| SSH ホスト定義 | `~/.ssh/config.local` | 手動作成。`.config/ssh/config` から `Include` で読み込み |
| Fisher テーマ系生成物 | `.config/fish/functions/.bobthefish_*.fish` 等 | `.gitignore` で除外 |
| Codex プロジェクト trust / plugin 有効化 | `~/.codex/config.toml` のマーカー外 | Codex が自動追記 |

## よくある落とし穴

- **Google Drive 同期で実行権限が落ちる**: `install.sh` / `update.sh` 冒頭で `chmod 755` を再付与している。手動で実行する前にエラーが出たら `bash` 経由で起動するか権限を再付与する
- **Fisher プラグインの自動生成ファイルが repo に混入**: Fish の `functions/` を丸ごと symlink すると bobthefish 等のテーマファイルが repo に書き込まれる。これを防ぐため個別ファイル単位で symlink している（`links.conf` 参照）
- **`~/.codex/config.toml` の手動追記が消える**: マネージドブロックの **外側** に書けば保持される。`[projects.*]` / `[plugins.*]` 以外のカスタム追記をしている場合は注意

## macOS 固有の設定ファイルパス

一部ツールは macOS で XDG (`~/.config/`) ではなく `~/Library/` 以下を既定の設定ファイル置き場にしている。
リポジトリ内は XDG 風の `.config/<tool>/` に統一してツリー見通しを揃え、`links.conf` で OS 側の実パスへ symlink する。

| ツール | macOS 既定の設定パス | 備考 |
|-------|--------------------|------|
| Ghostty | `~/Library/Application Support/com.mitchellh.ghostty/config` | アプリ bundle id ベース |
| Glow | `~/Library/Preferences/glow/glow.yml` | `XDG_CONFIG_HOME` は無視される (確認済み、v2.1.2) |

`~/.config/<tool>/` 配下に置いても読まれないツールがあるため、「リポジトリ内のパス」と「symlink 先のパス」は必ずしも一致しない。`links.conf` の右辺が正となる。
