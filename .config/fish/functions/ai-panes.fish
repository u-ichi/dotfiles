function ai-panes --description 'Jump to an AI CLI pane in the current tmux session (fzf selector)'
    if not set -q TMUX
        echo "ai-panes: not inside tmux" >&2
        return 1
    end

    set -l session (tmux display-message -p '#S')

    # 各 pane を 6 フィールド "<loc>|<pane_title>|<fixed_title>|<window_name>|<is_sidebar>|<path>" で取得。
    # pane_title: Claude Code が送る OSC 2 の状態 marker 判定に使う。
    # fixed_title: 手動固定タイトル。設定されていれば表示名として最優先する。
    # window_name: rename-windows.sh が argv[0] から付けた claude / codex 判定に使う。
    set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}|#{pane_title}|#{@fixed_title}|#{window_name}|#{@ai_sidebar}|#{pane_current_path}')

    # 状態判定して 3 バケツに振り分け:
    #   ✳ 始まり                      = Claude が user 入力待ち (最優先)
    #   Braille (U+2800-U+28FF) 始まり = Claude が生成中
    #   上記以外                       = Codex / Claude / シェル
    set -l waiting
    set -l working
    set -l idle
    for line in $raw
        set -l parts (string split -m 5 '|' -- $line)
        set -l loc $parts[1]
        set -l title $parts[2]
        set -l fixed_title $parts[3]
        set -l window_name (string lower -- $parts[4])
        set -l is_sidebar $parts[5]
        set -l path $parts[6]

        test "$is_sidebar" = 1; and continue

        set -l display
        if test -n "$fixed_title"
            set display $fixed_title
        else if string match -q '*codex*' -- $window_name; and test "$title" = (basename "$path")
            set display (string replace "$HOME" "~" -- "$path")
        else
            set display $title
        end

        if string match -q '✳*' -- $title
            set -a waiting "$loc  ● 待ち    │  $display"
        else if string match -qr '^[⠀-⣿]' -- $title
            set -a working "$loc  ◐ 動作中  │  $display"
        else if string match -q '*codex*' -- $window_name
            set -a idle "$loc  ○ Codex   │  $display"
        else if string match -q '*claude*' -- $window_name
            set -a idle "$loc  ○ Claude  │  $display"
        else
            set -a idle "$loc  ○ シェル  │  $display"
        end
    end

    # 待ち → 動作中 → その他 の順で並べて fzf に流す
    set -l selected (printf '%s\n' $waiting $working $idle \
        | fzf --height=100% --reverse --no-sort \
              --prompt='pane > ' \
              --header="session: $session  (Enter to jump, Esc to cancel)")

    test -z "$selected"; and return

    # 先頭の "<win>.<pane>" だけ取り出す
    set -l target (string split -m1 ' ' -- $selected)[1]
    set -l win (string split -m1 '.' -- $target)[1]

    tmux select-window -t "$session:$win"
    tmux select-pane -t "$session:$target"
end
