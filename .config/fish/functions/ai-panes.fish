function ai-panes --description 'Jump to an AI CLI pane in the current tmux session (fzf selector)'
    if not set -q TMUX
        echo "ai-panes: not inside tmux" >&2
        return 1
    end

    set -l session (tmux display-message -p '#S')

    # 各 pane を tab 区切り 9 フィールドで取得。pane_title には "|" が入ることがある。
    # pane_title: Claude Code が送る OSC 2 の状態 marker 判定に使う。
    # fixed_title: 手動固定タイトル。設定されていれば表示名として最優先する。
    # ai_base_title: AI CLI の自動生成セッション名など、手動固定ではない表示名。
    # pane_current_command: window 全体ではなく pane 固有の codex / claude 判定に使う。
    # @ai_app / @ai_state: sidebar が判定済みの app 種別と状態。Claude pane はこちらで分類。
    set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}	#{pane_title}	#{@fixed_title}	#{@ai_base_title}	#{@ai_sidebar}	#{pane_current_path}	#{pane_current_command}	#{@ai_app}	#{@ai_state}')

    # 状態判定して 3 バケツに振り分け:
    #   Claude pane (@ai_app=claude) は sidebar 算出の @ai_state で分類
    #   非 Claude: ✳ 始まり = 入力待ち、Braille 始まり = 生成中、その他 = idle
    set -l waiting
    set -l working
    set -l idle
    for line in $raw
        set -l parts (string split -m 8 \t -- $line)
        set -l loc $parts[1]
        set -l title $parts[2]
        set -l fixed_title $parts[3]
        set -l base_title $parts[4]
        set -l is_sidebar $parts[5]
        set -l path $parts[6]
        set -l command_name (string lower -- $parts[7])
        set -l ai_app $parts[8]
        set -l ai_state $parts[9]

        test "$is_sidebar" = 1; and continue

        set -l display
        set -l is_codex_console 0
        if test "$ai_app" = codex
            set is_codex_console 1
        else if string match -q '*codex*' -- $command_name
            set is_codex_console 1
        else if string match -q '*Context *% used*' -- $title
            set is_codex_console 1
        end
        set -l is_claude_console 0
        if test "$ai_app" = claude
            set is_claude_console 1
        else if string match -q '*claude*' -- $command_name
            set is_claude_console 1
        end

        if test -n "$fixed_title"
            set display $fixed_title
        else if test -n "$base_title"
            set display $base_title
        else if test "$is_codex_console" = 1; and test "$title" = (basename "$path")
            set display (string replace "$HOME" "~" -- "$path")
        else
            set display $title
        end

        if test "$is_claude_console" = 1
            switch "$ai_state"
                case waiting
                    set -a waiting "$loc  ● 待ち    │  $display"
                case working
                    set -a working "$loc  ◐ 動作中  │  $display"
                case '*'
                    set -a idle "$loc  ○ Claude  │  $display"
            end
        else if string match -q '✳*' -- $title
            set -a waiting "$loc  ● 待ち    │  $display"
        else if string match -qr '^[⠀-⣿]' -- $title
            set -a working "$loc  ◐ 動作中  │  $display"
        else if test "$is_codex_console" = 1
            set -a idle "$loc  ○ Codex   │  $display"
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
