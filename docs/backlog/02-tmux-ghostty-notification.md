---
id: 2
title: "tmux 経由で Claude の通知を Ghostty に届ける"
status: バックログ
notion_url: "https://www.notion.so/3460921ecd0a813d97cade03cb7e19b2"
notion_id: "3460921e-cd0a-813d-97ca-de03cb7e19b2"
parent_notion_url: ""
tags: []
assignee: ""
created: 2026-04-18
updated: 2026-04-18
---

# 02: tmux 経由で Claude の通知を Ghostty に届ける

## 概要

#01（tmux 導入）から切り出した確認事項。

tmux 内で `printf '\033]9;...\a'` を実行しても Ghostty のデスクトップ通知が出ない（tmux 外でも出ない）。Ghostty 向けに入れている拡張/プラグインが通知経路に干渉している可能性も含め、切り分けて調査する。音（bell）は主旨ではなく、あくまで「通知が届かない原因の切り分け用」として扱う。

## ゴール条件

- [ ] tmux 外で OSC 9 通知が出る条件が明らかになっている（フォーカス/非フォーカス、macOS 通知許可、拡張プラグインの影響など）
  - 検証: 手動検証結果を docs に記録
- [ ] tmux 内で OSC 9 通知が Ghostty 側に届く（`allow-passthrough on` が効いていることを確認）
  - 検証: tmux セッション内から `printf '\033]9;tmux test\a'` 等で手動確認
- [ ] Claude Code の実際の完了通知が tmux 越しに届く
  - 検証: tmux 内で Claude を起動し、適当なタスクを投げて完了時の通知を確認
- [ ] 通知が届かない原因が切り分けされている（Ghostty 設定 / macOS 許可 / 拡張プラグイン干渉 / tmux allow-passthrough のどれか）
  - 検証: 切り分け結果を docs にまとめる

## やること

- [ ] Ghostty 側の通知仕様調査（`desktop-notifications = true` 以外に必要な設定・macOS 側の許可）
- [ ] Ghostty 向けに入れているプラグイン/拡張（通知に干渉しそうなもの）を洗い出し、競合を判定
- [ ] tmux 外/内で OSC 9 / OSC 777 をそれぞれテストし結果を表にまとめる（bell は切り分け用の補助指標）
- [ ] Claude Code の Stop hook / notify.sh 経由通知の動作確認
- [ ] 必要に応じて ghostty/tmux 設定を調整

## 参考

- Ghostty OSC 9 docs: https://ghostty.org/docs/vt/osc/9
- tmux `allow-passthrough` は #01 で導入済み
- 関連レポート: `output/2026-04-18_tmux-claude-codex/tmux-claude-codex-便利設定統合レポート.md`

## 進捗ログ

### 2026-04-18

- 初期作成。#01 から切り出し。

## 成果物

（完了時に記載）
