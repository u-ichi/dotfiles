function cc-panes --description 'Jump to a pane in the current tmux session (fzf selector)'
    if not set -q TMUX
        echo "cc-panes: not inside tmux" >&2
        return 1
    end

    set -l session (tmux display-message -p '#S')

    # 各 pane を 3 フィールド "<loc>|<pane_title>|<display>" で取得。
    # pane_title: 状態判定 (Claude が送る OSC 2 の先頭文字) に使う。
    # display: @fixed_title が設定されていればそれ、未設定なら pane_title。
    set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}|#{pane_title}|#{?#{==:#{@fixed_title},},#{pane_title},#{@fixed_title}}')

    # 状態判定して 3 バケツに振り分け:
    #   ✳ 始まり                 = Claude が user 入力待ち (最優先)
    #   Braille (U+2800-U+28FF) 始まり = Claude が生成中
    #   上記以外                       = シェル / 空きペイン
    set -l waiting
    set -l working
    set -l idle
    for line in $raw
        set -l parts (string split -m 2 '|' -- $line)
        set -l loc $parts[1]
        set -l title $parts[2]
        set -l display $parts[3]
        if string match -q '✳*' -- $title
            set -a waiting "$loc  ● 待ち    │  $display"
        else if string match -qr '^[⠀-⣿]' -- $title
            set -a working "$loc  ◐ 動作中  │  $display"
        else
            set -a idle "$loc  ○ シェル  │  $display"
        end
    end

    # 待ち → 動作中 → シェル の順で並べて fzf に流す
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
