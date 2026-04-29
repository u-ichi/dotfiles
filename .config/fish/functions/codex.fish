# Codex CLI 起動の内部ヘルパ。function 名の shadowing を避けるため command 経由で呼ぶ。
function __codex_run
    command codex $argv
end

function __codex_reset_pane_title
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    # Claude Code の SessionEnd hook と同じ方針で、終了後は作業ラベルを捨てる。
    set -l title (basename "$PWD")
    tmux select-pane -t "$TMUX_PANE" -T "$title" 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" @fixed_title "" 2>/dev/null
    tmux set-option -p -t "$TMUX_PANE" @ai_base_title "" 2>/dev/null
end

function __codex_set_pane_base_title
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    set -l path "$PWD"
    set -l argc (count $argv)
    if test $argc -gt 0
        for i in (seq $argc)
            switch $argv[$i]
                case -C --cd
                    set -l next (math $i + 1)
                    if test $next -le $argc
                        set path $argv[$next]
                    end
            end
        end
    end

    tmux set-option -p -t "$TMUX_PANE" @ai_base_title (basename "$path") 2>/dev/null
end

function __codex_run_interactive
    __codex_set_pane_base_title $argv
    command codex $argv
    set -l exit_code $status
    __codex_reset_pane_title
    return $exit_code
end

function __codex_generate_worktree_name
    set -l source_name $argv[1]
    set -l output_file (mktemp)
    set -l stderr_file (mktemp)

    set -l prompt "Convert the following Japanese task description into a short, kebab-case English git branch/worktree name. Output ONLY the name, 2-4 words, lowercase letters/numbers/hyphens only, no explanation: $source_name"
    command codex \
        --sandbox read-only \
        --ask-for-approval never \
        exec \
        --skip-git-repo-check \
        --output-last-message "$output_file" \
        "$prompt" >/dev/null 2>$stderr_file
    set -l exit_code $status
    set -l generated (string trim -- (cat $output_file 2>/dev/null))

    rm -f $output_file

    if test $exit_code -eq 0; and string match -qr '^[a-z][a-z0-9-]*$' "$generated"
        rm -f $stderr_file
        echo $generated
        return 0
    end

    echo "名前の自動生成に失敗しました (exit=$exit_code, output='$generated')。" >&2
    if test -s $stderr_file
        echo "エラー詳細:" >&2
        cat $stderr_file >&2
    end
    rm -f $stderr_file
    return 1
end

function __codex_run_in_worktree
    set -l repo $argv[1]
    set -l worktree_name $argv[2]
    set -e argv[1]
    set -e argv[1]

    set -l wt_dir "$repo/.codex/worktrees"
    set -l worktree_path "$wt_dir/$worktree_name"

    if not git -C "$repo" check-ref-format --branch "$worktree_name" >/dev/null 2>&1
        echo "git branch 名として使えません: $worktree_name" >&2
        return 1
    end

    mkdir -p "$wt_dir"

    echo "origin/main を取得しています..."
    if not git -C "$repo" fetch origin main 2>/dev/null
        echo "⚠ fetch に失敗しました（オフライン等）。現在の状態で続行します。"
    end

    if not test -d "$worktree_path"
        set -l base_ref origin/main
        if not git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null
            set base_ref main
        end

        if git -C "$repo" show-ref --verify --quiet "refs/heads/$worktree_name"
            git -C "$repo" worktree add "$worktree_path" "$worktree_name"
        else
            git -C "$repo" worktree add -b "$worktree_name" "$worktree_path" "$base_ref"
        end

        if test $status -ne 0
            echo "worktree の作成に失敗しました: $worktree_path" >&2
            return 1
        end
    end

    __codex_run_interactive -C "$worktree_path" $argv
end

function codex --description "Codex CLI を worktree モードで起動（既存選択 or 新規作成）"
    # pipe / redirect 経由の codex exec 等は対話セレクタを出さず、そのまま実行する。
    if not isatty stdin
        __codex_run $argv
        return
    end

    # subcommand や明示的な working root 指定は Codex 本体へそのまま渡す。
    for arg in $argv
        switch $arg
            case exec e review login logout mcp plugin mcp-server app-server app completion sandbox debug apply a resume fork cloud exec-server features help
                __codex_run $argv
                return
            case --cd -C --help -h --version -V
                __codex_run $argv
                return
        end
    end

    set -l repo (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        # git リポジトリ外ではそのまま実行
        __codex_run_interactive $argv
        return
    end

    set -l wt_dir "$repo/.codex/worktrees"
    set -l choices

    if test -d "$wt_dir"
        for d in $wt_dir/*/
            if test -d "$d"
                set -a choices (basename $d)
            end
        end
    end

    if test (count $choices) -gt 0
        echo "既存 worktree:"
        for i in (seq (count $choices))
            echo "  $i) $choices[$i]"
        end
    end
    echo "  Enter/s) worktree なしで起動"
    echo "  名前を入力すると新規 worktree を作成"
    read -P "選択 > " sel

    if test -z "$sel" -o "$sel" = s
        __codex_run_interactive $argv
    else if string match -qr '^\d+$' "$sel"; and test (count $choices) -gt 0 -a "$sel" -ge 1 -a "$sel" -le (count $choices)
        __codex_run_in_worktree "$repo" $choices[$sel] $argv
    else
        # non-ASCII characters detected → generate English worktree name via Codex
        if string match -qr '[^\x00-\x7F]' "$sel"
            echo "名前を生成中..."
            set -l generated (__codex_generate_worktree_name "$sel")
            if test $status -eq 0
                echo "→ $generated"
                read -P "この名前でOK? (Enter=OK / 別の名前を入力) > " confirm
                if test -n "$confirm"
                    set generated $confirm
                end
                set sel $generated
            else
                echo "英語名を入力してください:"
                read -P "> " manual
                if test -n "$manual"
                    set sel $manual
                else
                    echo "キャンセルしました"
                    return 1
                end
            end
        end

        __codex_run_in_worktree "$repo" "$sel" $argv
    end
end
