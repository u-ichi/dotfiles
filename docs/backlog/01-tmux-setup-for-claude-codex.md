---
id: 1
title: "tmux を dotfiles に正式導入し Claude/Codex CLI 向け設定を追加"
status: 進行中
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

- [ ] Brewfile に `brew 'tmux'` が追加されている
  - 検証: `rg "^brew 'tmux'$" Brewfile`
- [ ] ローカル環境に tmux がインストールされている
  - 検証: `which tmux`
- [ ] `.config/tmux/tmux.conf` に AI CLI 向けブロックが追加されている（extended-keys / allow-passthrough / set-clipboard external / terminal-features extkeys を含む）
  - 検証: `rg -c 'extended-keys on|allow-passthrough on|set-clipboard external|extkeys' .config/tmux/tmux.conf` が 4 以上
- [ ] `history-limit` が 100000 に更新されている
  - 検証: `rg '^set -g history-limit 100000' .config/tmux/tmux.conf`
- [ ] 既存設定（prefix C-s、pbcopy バインド、既存 keybinding）が温存されている
  - 検証: 手動確認（diff で意図しない削除がないこと）
- [ ] `tmux -f .config/tmux/tmux.conf new-session -d \; kill-server` でパースエラーなし
  - 検証: 上記コマンドの exit code 0
- [ ] tmux 内で起動した Claude Code が Shift+Enter を改行として認識する
  - 検証: 手動確認

> 通知系（tmux 内 Claude の Ghostty 通知）は #02 に切り出し済み。

## やること

- [ ] Brewfile に `brew 'tmux'` を追加（CLI: システム・ユーティリティ セクション）
- [ ] `brew bundle` でインストール（ユーザー承認後）
- [ ] `.config/tmux/tmux.conf` に AI CLI 向け設定ブロックを追記
- [ ] `tmux -f` でパース検証
- [ ] tmux 起動 + Claude Code で Shift+Enter を手動確認（通知系は #02 に切り出し）

## 非対応（別バックログ候補）

- TPM + tmux-resurrect / continuum / yank / logging 導入
- tmux-which-key / fzf / fingers / catppuccin
- Claude Code Agent Teams `teammateMode: "tmux"` の settings.json 設定

## 進捗ログ

### 2026-04-18

- 初期作成。参考レポート（output/2026-04-18_tmux-claude-codex/）を元にゴール条件を定義。

## 成果物

（完了時に記載）
