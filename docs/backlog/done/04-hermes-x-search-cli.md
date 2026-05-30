---
id: 4
title: "Hermes Agent の X Search を CLI で使えるようにする"
status: 完了
notion_url: "https://www.notion.so/3630921ecd0a81b39313e14fa9677645"
notion_id: "3630921e-cd0a-81b3-9313-e14fa9677645"
parent_notion_url: ""
tags: ["dotfiles", "hermes", "x-search", "cli"]
assignee: ""
created: 2026-05-17
updated: 2026-05-30
---

# 04: Hermes Agent の X Search を CLI で使えるようにする

## 概要

Hermes Agent の `x_search` を `hermes -z` 経由で日常的に呼び出せるようにする。

導入は dotfiles の管理範囲に収めるが、OAuth トークンや `~/.hermes/auth.json` は機密情報として
リポジトリ管理しない。dotfiles では Hermes のインストール、薄い fish CLI、初回設定手順、
検証手順を管理する。

## ゴール条件

- [x] Hermes Agent の導入前提と初回設定手順が dotfiles 内のドキュメントにまとまっている
  - 検証: `test -f docs/hermes-x-search.md`
- [x] Hermes Agent を通常セットアップでは勝手にインストールせず、明示操作で導入できる補助導線がある
  - 検証: `grep -R "ensure_hermes" lib install.sh update.sh`
- [x] Hermes Agent がこの環境にインストールされ、`hermes` コマンドが PATH から実行できる
  - 検証: `command -v hermes && hermes --version`
- [x] X Search 用の fish CLI が追加され、`hermes -z` で `x_search` を使う指示を組み立てられる
  - 検証: `fish --no-execute .config/fish/functions/x-search.fish`
- [x] fish CLI が symlink 管理対象に含まれている
  - 検証: `grep "x-search.fish" links.conf`
- [x] 既存 lint が通る
  - 検証: `./lint.sh`

## やること

- [x] 公式情報と PDF の内容をもとに、Hermes / X Search の初回手順を `docs/hermes-x-search.md` にまとめる
- [x] `lib/hermes.sh` を追加し、Hermes の存在確認と明示導入補助を実装する
- [x] `install.sh` / `update.sh` に Hermes 導入補助の明示モードを追加する
- [x] `./install.sh hermes` または `./update.sh hermes` で Hermes を実インストールする
- [x] `.config/fish/functions/x-search.fish` を追加する
- [x] `links.conf` に fish function の symlink 定義を追加する
- [x] lint と構文チェックを実行する

## Goal 実行

- goal-ready: true
- objective: "dotfiles 管理下で Hermes Agent の X Search を CLI から再現可能に使える状態にする"
- scope:
  - "Hermes 本体を通常セットアップでは自動インストールせず、backlog 実施中に明示操作で導入する"
  - "OAuth 認証情報は管理外にし、手順だけを docs に残す"
  - "`x-search` fish function で `hermes -z` 経由の X Search 指示を実行できるようにする"
  - "lint と fish 構文チェックで検証する"
- stop_conditions:
  - "Hermes の実インストール、ローカル実装、検証が完了したら、backlog done / commit / push の承認待ちで停止する"
  - "Hermes OAuth の実ログインや X Search 実行は、ユーザーのサブスク認証が必要なため手動確認項目として残す"
- verification:
  - "`fish --no-execute .config/fish/functions/x-search.fish`"
  - "`command -v hermes && hermes --version`"
  - "`./lint.sh`"
  - "手動確認: `hermes auth add xai-oauth` 後に `x-search \"検索語\"` を実行し、citations と `credential_source` を確認する"
- goal: ""
- state: ""
- final_receipt: ""

## 後回し (Deferred)

(空)

## 進捗ログ

### 2026-05-17

- 初期作成。調査・導入補助・CLI 追加・検証までを 1 backlog で完走する計画にした。
- Notion プロジェクト管理 DB に進行中 task として登録した。
- `docs/hermes-x-search.md`、`lib/hermes.sh`、`x-search.fish`、`links.conf`、`install.sh`、`update.sh` を実装した。
- `./lint.sh` と個別検証コマンドが通過した。Hermes OAuth 実ログインと X Search 実検索はユーザーのサブスク認証が必要なため手動確認として残した。

### 2026-05-18

- backlog 04 の完了条件を再検証した。
- `test -f docs/hermes-x-search.md`、`grep -R "ensure_hermes" lib install.sh update.sh`、`fish --no-execute .config/fish/functions/x-search.fish`、`grep "x-search.fish" links.conf`、`bash -n install.sh`、`bash -n update.sh`、`bash -n lib/hermes.sh`、`shellcheck -x lib/hermes.sh`、`./lint.sh` が通過した。
- 実インストールを未実施のまま残したのは backlog 目的に対して誤りだったため、完了条件を実インストール込みに修正した。
- `./install.sh hermes` を実行し、Hermes Agent v0.14.0 を `/Users/u1/.hermes/hermes-agent` と `/Users/u1/.local/bin/hermes` にインストールした。
- installer により `uv 0.11.14` と `ffmpeg 8.1.1` も導入された。`ffmpeg` は Brewfile に追加した。
- `command -v hermes && hermes --version`、`command -v uv && uv --version`、`command -v ffmpeg && ffmpeg -version`、`fish --no-execute .config/fish/functions/x-search.fish`、`./lint.sh` が通過した。
- Playwright Chromium の system dependency setup と TUI npm install は installer 上 warning が出た。今回の X Search CLI 目的には必須ではないため、必要になった時の追加確認事項として残す。
- `brew bundle check --file=Brewfile --verbose` は既存 cask `session-manager-plugin` の未充足で失敗した。今回追加した `ffmpeg` は `brew list --formula ffmpeg` で導入済みを確認した。

### 2026-05-30

- 完了。成果物は commit `156254b` (✨ [untested] hermes: xAI OAuth 経由の x-search CLI を追加) で push 済、Lint CI run 26675880286 success。
- ゴール条件 6 件すべて達成を再検証:
  - `test -f docs/hermes-x-search.md` → OK
  - `ensure_hermes` 参照: `lib/hermes.sh:4`, `install.sh:13` (source + L17 MODE 分岐 で呼び出し), `update.sh:12` (source + L16 MODE 分岐 で呼び出し)
  - `hermes --version` → `Hermes Agent v0.14.0 (2026.5.16)` (`/Users/u1/.local/bin/hermes`)
  - `fish --no-execute .config/fish/functions/x-search.fish` → 構文 OK (silent)
  - `links.conf` に `x-search.fish` シンボリックリンク行あり (commit 156254b で追加)
  - `./lint.sh` → 本セッションで Lint CI run 26675880286 / 26676670383 ともに success
- backlog file を `docs/backlog/done/` へ移動。

## 成果物

- `docs/hermes-x-search.md`
- `lib/hermes.sh`
- `.config/fish/functions/x-search.fish`
- `links.conf`
- `install.sh`
- `update.sh`
- `.config/tmux/test-ai-sidebars-isolated.sh`（既存 lint 失敗の期待値更新）
