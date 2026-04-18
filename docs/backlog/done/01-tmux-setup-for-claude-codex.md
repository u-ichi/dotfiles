---
id: 1
title: "tmux を dotfiles に正式導入し Claude/Codex CLI 向け設定を追加"
status: 完了
notion_url: "https://www.notion.so/3460921ecd0a819bbef4f1f44b802997"
notion_id: "3460921e-cd0a-819b-bef4-f1f44b802997"
parent_notion_url: ""
tags: []
assignee: ""
created: 2026-04-18
updated: 2026-04-18
---

# 01: tmux を dotfiles に正式導入し Claude/Codex CLI 向け設定を追加

## 概要

現状 dotfiles リポジトリに `.config/tmux/tmux.conf` は存在するが、Brewfile に tmux が無く実機にもインストールされていない（`which tmux` が not found）。また既存設定には Claude Code / Codex CLI を tmux 越しに使う際に必要な設定（Shift+Enter 対応・allow-passthrough・OSC52 など）が含まれていない。

参考レポート: `output/2026-04-18_tmux-claude-codex/tmux-claude-codex-便利設定統合レポート.md`

## ゴール条件

- [x] Brewfile に `brew 'tmux'` が追加されている
  - 検証: `rg "^brew 'tmux'$" Brewfile`
- [x] ローカル環境に tmux がインストールされている
  - 検証: `which tmux`
- [x] `.config/tmux/tmux.conf` に AI CLI 向けブロックが追加されている（extended-keys / allow-passthrough / set-clipboard external / terminal-features extkeys を含む）
  - 検証: `rg -c 'extended-keys on|allow-passthrough on|set-clipboard external|extkeys' .config/tmux/tmux.conf` が 4 以上
- [x] `history-limit` が 100000 に更新されている
  - 検証: `rg '^set -g history-limit 100000' .config/tmux/tmux.conf`
- [x] 既存設定（prefix C-s、pbcopy バインド、既存 keybinding）が温存されている
  - 検証: 手動確認（diff で意図しない削除がないこと）
- [x] `tmux -f .config/tmux/tmux.conf new-session -d \; kill-server` でパースエラーなし
  - 検証: 上記コマンドの exit code 0
- [x] tmux 内で起動した Claude Code が Shift+Enter を改行として認識する
  - 検証: 手動確認

> 通知系（tmux 内 Claude の Ghostty 通知）は #02 に切り出し済み。

## やること

- [x] Brewfile に `brew 'tmux'` を追加（CLI: システム・ユーティリティ セクション）
- [x] `brew bundle` でインストール（ユーザー承認後）
- [x] `.config/tmux/tmux.conf` に AI CLI 向け設定ブロックを追記
- [x] `tmux -f` でパース検証
- [x] tmux 起動 + Claude Code で Shift+Enter を手動確認（通知系は #02 に切り出し）

## 非対応（別バックログ候補）

- TPM + tmux-resurrect / continuum / yank / logging 導入
- tmux-which-key / fzf / fingers / catppuccin
- Claude Code Agent Teams `teammateMode: "tmux"` の settings.json 設定

## 進捗ログ

### 2026-04-18

- 初期作成。参考レポート（output/2026-04-18_tmux-claude-codex/）を元にゴール条件を定義。
- 実装完了。Brewfile と tmux.conf を更新、tmux 3.6a インストール、パース検証・Shift+Enter 手動確認まで pass。通知系は #02 に切り出した。

## 成果物

### コミット

- dotfiles `ac77b91` — tmux: Brewfile に追加し Claude/Codex CLI 向け設定を整備
- dotfiles `6c23d23` — backlog: tmux 導入と Ghostty 通知検証のバックログを追加

### インストール

- tmux 3.6a (`/opt/homebrew/bin/tmux`) via Homebrew

### tmux.conf 追加設定

- `default-terminal "tmux-256color"` + `terminal-features` (RGB / clipboard / extkeys)
- `extended-keys on` + `set-clipboard external`
- `allow-passthrough on`（Claude の通知・progress bar を outer terminal に通す）
- `history-limit` 20000 → 100000
- `aggressive-resize off`
- `pane-border-status top` + `pane-border-format`
- `monitor-activity` + `visual-activity` + `activity-action other` + `bell-action any`

### 検証結果

| # | 条件 | 検証方法 | 結果 |
|---|------|---------|------|
| 1 | Brewfile に `brew 'tmux'` | `rg "^brew 'tmux'$" Brewfile` | ✅ line 40 |
| 2 | tmux インストール | `which tmux` | ✅ 3.6a |
| 3 | AI CLI ブロック 4 keyword | `rg -c ... .config/tmux/tmux.conf` | ✅ count=4 |
| 4 | history-limit 100000 | `rg '^set -g history-limit 100000' ...` | ✅ |
| 5 | 既存設定温存 | 手動 diff 確認 | ✅ 追加のみ |
| 6 | `tmux -f` パース | exit code | ✅ 0 |
| 7 | Shift+Enter 動作 | 手動確認 | ✅ ユーザー確認済み |

### 切り出し

- #02 tmux 経由で Claude の通知を Ghostty に届ける（OSC 9 通知検証・プラグイン干渉の切り分け）
