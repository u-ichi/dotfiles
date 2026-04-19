# tmux 設定変更時のリロード挙動

IMPORTANT: tmux の `source-file` (`prefix + r` も含む) は**追記型**。
設定行をコメントアウトしても **tmux サーバーが保持する既存値はクリアされない**。

## 起きるミス

1. 以前設定した `set -g window-status-current-style bg=white,fg=black` が気に入らない
2. その行をコメントアウト
3. `prefix + r` で reload → 見た目が変わらない
4. 「reload が効いてない？」と混乱

実際は reload 自体は効いているが、コメントアウトした設定項目は
**設定されていないだけ** で、サーバーメモリの既存値 (`bg=white,fg=black`) が残る。

## 正しい対処

既存値を消したい場合は、**明示的に `default` (または初期値) を設定し直す**:

```tmux
# ❌ これではリセットされない
# set -g window-status-current-style bg=white,fg=black

# ✅ 明示的に default に上書き
set -g window-status-current-style default
```

## 完全リセット手段

複雑に絡まった場合はサーバーを殺して再生成:

```bash
tmux kill-server
# または
tmux kill-session -t <name>
```

ただしセッション内のプロセスが全部死ぬので最終手段。

## 適用対象

**style 系** (色・装飾):

- `window-status-current-style` / `window-status-style`
- `status-bg` / `status-fg` / `status-style`
- `window-status-activity-style` / `window-status-bell-style`
- `pane-border-style` / `pane-active-border-style`

**layout / position 系** (配置・方向):

- `status-justify` (left / centre / right / absolute-centre)
- `status-position` (top / bottom)
- `pane-border-status` (off / top / bottom)

**一般原則**: `set -g` / `setw -g` で一度でも設定したオプションは、
**行を削除しただけではサーバーメモリの既存値が残る**。
style/layout/position を問わずすべてに該当する。

## 関連

- `font-nf-detection.md` — フォント NF 対応判定
