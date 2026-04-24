function cc-panes --description 'Jump to a pane in the current tmux session (fzf selector)'
    if not set -q TMUX
        echo "cc-panes: not inside tmux" >&2
        return 1
    end

    set -l session (tmux display-message -p '#S')

    # 現在 session の全 pane を "<win>.<pane>  <title>" 形式で列挙
    # @fixed_title が設定されていればそれを優先、未設定なら Claude の pane_title
    set -l selected (tmux list-panes -s -F '#{window_index}.#{pane_index}  #{?#{==:#{@fixed_title},},#{pane_title},#{@fixed_title}}' \
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
