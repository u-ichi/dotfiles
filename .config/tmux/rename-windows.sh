#!/usr/bin/env bash
# すべての tmux window を走査し、pane の実際の argv[0] に基づいて window を rename する。
#
# 背景: Claude Code / Codex CLI はバイナリがバージョンディレクトリ (例:
# ~/.local/share/claude/versions/2.1.114) に置かれているため、カーネルの p_comm
# が `2.1.114` となり、tmux の automatic-rename / pane_current_command も
# そのバージョン文字列を拾ってしまう。ps -o command は argv[0] を返すので
# claude / codex 等の正しい名前が得られる。本スクリプトは tmux hook から呼ばれ、
# pane 毎に argv[0] を調べて window 名を更新する。
set -u

detect_name() {
    local pane_pid="$1"
    local child target argv0 name
    # macOS の pgrep は pattern 必須で -P 単体では使えないため ps -A で代替。
    # 直近の子プロセス (最大 pid = 最後に fork されたもの) を拾う。
    child=$(ps -A -o pid=,ppid= 2>/dev/null | awk -v p="$pane_pid" '$2==p {print $1}' | sort -n | tail -1)
    target="${child:-$pane_pid}"
    argv0=$(ps -p "$target" -o command= 2>/dev/null | awk '{print $1}')
    name=$(basename "${argv0:-}" 2>/dev/null)
    [[ -z "$name" ]] && name=$(ps -p "$target" -o comm= 2>/dev/null)
    name="${name#-}"
    echo "${name:-?}"
}

# 各 window の active pane を調べて rename
while IFS=$'\t' read -r win_id pane_pid; do
    name=$(detect_name "$pane_pid")
    tmux rename-window -t "$win_id" "$name" 2>/dev/null || true
done < <(tmux list-windows -a -F '#{window_id}	#{pane_pid}' 2>/dev/null)
