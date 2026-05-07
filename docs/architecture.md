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
│   │   └── functions/          #   カスタム関数 (claude/codex/ai-panes/sidebar 等、テーマ系は .gitignore)
│   ├── git/config              # Git 設定 (共通、個人情報は config.local に分離)
│   ├── ssh/config              # SSH 設定 (Include のみ、ホスト定義は ~/.ssh/config.local に分離)
│   ├── tmux/tmux.conf          # tmux 設定 (prefix: Ctrl+S)
│   ├── tmux/rename-windows.sh  # tmux window 名の自動更新
│   ├── tmux/ensure-ai-sidebars.sh # tmux AI sidebar の作成
│   ├── tmux/update-ai-display-indexes.sh # tmux AI sidebar 用表示番号の再採番
│   ├── tmux/cleanup-ai-sidebars.sh # orphan 化した tmux AI sidebar の削除
│   ├── tmux/ai-sidebar-click.sh   # tmux AI sidebar のクリック解決
│   ├── tmux/test-ai-sidebars-isolated.sh # 専用 socket 上の tmux AI sidebar 検証
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
| `lint.sh` | ShellCheck (Bash) / `fish --no-execute` / tmux isolated smoke test / taplo (TOML) / `python3 -m json.tool` (JSON) を実行。GitHub Actions でも同等の静的チェックが走る |
| `.config/tmux/rename-windows.sh` | tmux window 名を active な通常 pane のプロセス名から更新する。AI sidebar pane が active の場合は最初の通常 pane を基準にする |
| `.config/tmux/ensure-ai-sidebars.sh` | 各 tmux window に AI pane 一覧 sidebar が無ければ作成する。既存 sidebar の kill / resize は行わない |
| `.config/tmux/update-ai-display-indexes.sh` | tmux pane の増減後に AI sidebar 用の表示番号 (`@ai_display_index`) だけを再採番する。sidebar の作成や layout 変更は行わない |
| `.config/tmux/cleanup-ai-sidebars.sh` | 通常 pane が残っていない window の orphan sidebar を閉じる |
| `.config/tmux/ai-sidebar-click.sh` | AI sidebar のクリック行から対象 pane を解決して移動する。`AI_SIDEBAR_CLICK_DRY_RUN=1` では対象 pane の出力だけ行う |
| `.config/tmux/test-ai-sidebars-isolated.sh` | 専用 socket の disposable tmux server だけを使い、sidebar 既定有効化と新規 window hook を検証する |

`install.sh` と `update.sh` は冪等。何度実行しても安全。

## tmux AI pane navigation

tmux の AI pane 移動は popup と sidebar の 2 系統を持つ。

| UI | 起動 | 役割 |
|----|------|------|
| popup | `prefix+g` | `fish -c ai-panes` を開き、fzf で現在 session の AI / shell pane を選んで移動する |
| sidebar | `prefix+G` | 各 window 左端に AI pane 一覧を表示する sidebar を作成する |

sidebar は責務を 3 つに分ける。

| ファイル | 責務 |
|----------|------|
| `.config/tmux/ensure-ai-sidebars.sh` | sidebar pane の作成 |
| `.config/tmux/update-ai-display-indexes.sh` | 通常 pane の表示番号 (`@ai_display_index`) 付与と再採番 |
| `.config/tmux/cleanup-ai-sidebars.sh` | orphan sidebar の削除 |
| `.config/fish/functions/ai-panes-sidebar.fish` | pane 一覧の表示、状態検出、状態遷移時刻、表示行ごとの click target (`@ai_click_target_N`) 更新 |
| `.config/tmux/ai-sidebar-click.sh` | クリックされた表示行を `%pane_id` に解決し、対象 window / pane へ移動 |

sidebar の既定幅は 26 cells とし、既存 pane の kill / resize を自動では行わない。幅を変えたい場合は
`ensure-ai-sidebars.sh <width>` で新規作成時の幅だけ指定するか、対象 sidebar に対して手動で
`tmux resize-pane` を実行する。`@ai_sidebars_enabled` は既定で有効化し、tmux client attach 時と
新規 window 作成時に hook から不足分の sidebar を作成する。`prefix+G` は既存 window に sidebar が
無い場合の再同期用として `ensure-ai-sidebars.sh` を実行する。

状態表示は `working` / `waiting` / `idle` の 3 種類に正規化する。Codex の
`Working (` / `Waiting for background terminal` / `background terminal running` は `working`、
承認 prompt やユーザーへの明示的な確認文言は `waiting` として扱い、sidebar では `?` で表示する。
過去の Codex session log で確認した `Press enter to confirm or esc to cancel`、
`Would you like to run the following command?` + Yes/No メニュー、`実行してよいですか`、
`承認してください` などを検出対象にする。表示時刻は sidebar 起動時刻や
window 切替時刻ではなく、状態が変化した時刻を示す。状態と遷移時刻は対象 pane の
`@ai_state` / `@ai_state_since` option に保持し、`@ai_state_version` で古い形式の値を無効化する。
sidebar 起動時点で過去の遷移時刻を復元できない pane は `--:--` と表示する。
sidebar 起動後に新規出現した pane は検出時刻を初期時刻として使い、以後の状態変化で現在時刻を入れる。
Codex 起動直後の `project | Context ... used` title は status line 由来なので、pane border では
`@ai_base_title` に保存した短い起動ディレクトリ名を表示する。タスク名 title になった後は
`#{pane_title}` をそのまま表示する。
`@ai_display_index` は `after-split-window` / `after-kill-pane` hook で再採番する。通常 pane が
全て閉じられて sidebar だけが残った window は `after-kill-pane` hook で
`cleanup-ai-sidebars.sh` が sidebar を閉じる。sidebar 作成は hook からは行わず、layout 変更は
orphan cleanup に限定する。
表示順は `working` → `waiting` → `idle` を第一キーにする。`working` / `waiting` では状態遷移時刻の
新しいものを上、古いものを下に出す。`idle` では LLM console (`pane_current_command` /
Codex の `Context ... used` title が codex / claude 系) を通常 shell pane
より先に出し、その中で状態遷移時刻の新しいものを上に出す。LLM console は neutral navy の背景色、
通常 shell pane は gray foreground で区別する。

クリック target は window index / pane index ではなく `%pane_id` を正とする。pane index は
sidebar の追加・削除で変化しやすいため、表示行と移動先の対応には使わない。
sidebar 側は `@ai_click_target_N` と合わせて表示行テキスト (`@ai_click_line_N`) も保持する。
クリック解決では表示行テキストの一致を優先し、座標 fallback では `#{mouse_y}` を pane 内
0 始まりの行番号として扱う。
sidebar / popup の `tmux list-panes` parse は tab 区切りにする。Codex の pane title には
`project | Context ... used` のように `|` が入るため、`|` 区切りにすると field がずれて
LLM console が通常 shell 扱いになる。
tmux の `pane-scrollbars` は copy/view mode で右端に 1 カラムの scrollbar を出し、折り返し位置を
変えるため無効化する。

通常入力や window 切替で focus が飛ぶのを避けるため、sidebar 作成は `client-attached` /
`after-new-window` / `prefix+G` に限定する。`pane-focus-in` / `after-select-window` などの hook から
sidebar 作成や layout 変更は行わない。

tmux 設定や sidebar 挙動の検証では、default tmux server に対して `kill-server` を実行しない。
動作検証は `.config/tmux/test-ai-sidebars-isolated.sh` を使い、専用 socket の disposable server
だけを作成・破棄する。

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
- **live tmux の sidebar 再作成で focus が動く**: sidebar pane の kill / recreate は通常 pane が active でも active pane を変える場合がある。live 検証では dry-run / 読み取りを優先し、再作成が必要な場合は現在 pane を記録して復元する

## macOS 固有の設定ファイルパス

一部ツールは macOS で XDG (`~/.config/`) ではなく `~/Library/` 以下を既定の設定ファイル置き場にしている。
リポジトリ内は XDG 風の `.config/<tool>/` に統一してツリー見通しを揃え、`links.conf` で OS 側の実パスへ symlink する。

| ツール | macOS 既定の設定パス | 備考 |
|-------|--------------------|------|
| Ghostty | `~/Library/Application Support/com.mitchellh.ghostty/config` | アプリ bundle id ベース |
| Glow | `~/Library/Preferences/glow/glow.yml` | `XDG_CONFIG_HOME` は無視される (確認済み、v2.1.2) |

`~/.config/<tool>/` 配下に置いても読まれないツールがあるため、「リポジトリ内のパス」と「symlink 先のパス」は必ずしも一致しない。`links.conf` の右辺が正となる。
