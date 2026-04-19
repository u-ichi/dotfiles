# フォント Nerd Font 対応の判定ルール

フォント cask の NF (Nerd Font) グリフ同梱有無を判定する時、
`brew info --cask` の artifact 一覧や配布ファイル名から推論しない。
**インストール済みフォントに対して `fc-match` で直接 glyph coverage を確認する**。

## 背景

`font-moralerspace` v2.0.0 は artifact に `MoralerspaceNeon-Regular.ttf` 等しか出ないが、
内部で NF グリフが統合されている。別 cask `font-moralerspace-nf` は
2025-07-29 に discontinued upstream で disabled。
artifact のファイル名だけ見て「NF 非同梱」と即断したミスあり。

## 判定手順

インストール済みフォントなら:

```bash
fc-match "Moralerspace Neon:charset=e0b0"  # powerline-right-arrow
fc-match "Moralerspace Neon:charset=f073"  # fa-calendar
fc-match "Moralerspace Neon:charset=f017"  # fa-clock-o
```

クエリしたフォント自身が返れば NF グリフあり。別フォント (Verdana 等) に
fallback したら非対応。

未インストール cask の場合は `brew info --cask <name>` の artifact 名では
判定せず、必要ならテスト用に一時インストールして fc-match で確認する。

## 適用場面

- Brewfile でフォント cask を追加・変更する前
- Ghostty / tmux / Neovim 等、グリフに依存する設定変更時
- 「NF が入っていない」「NF 同梱」等の主張をする前
