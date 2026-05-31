# Codex CLI 起動の内部ヘルパ。function 名の shadowing を避けるため command 経由で呼ぶ。
function __codex_ai_pane_title_sync_path
    set -l function_file (status filename)
    set -l helper_path (dirname "$function_file")/__ai_pane_title_sync.fish
    if not test -f "$helper_path"
        set -l linked_file (command readlink "$function_file" 2>/dev/null)
        test -n "$linked_file"; and set helper_path (dirname "$linked_file")/__ai_pane_title_sync.fish
    end

    test -f "$helper_path"; and printf '%s\n' "$helper_path"
end

function __codex_ensure_ai_pane_title_sync
    functions -q __ai_pane_title_sync; and return 0

    set -l helper_path (__codex_ai_pane_title_sync_path)
    test -n "$helper_path"; and source "$helper_path"
end

function __codex_physical_path
    set -l path $argv[1]
    set -l old_pwd "$PWD"

    if builtin cd "$path" 2>/dev/null
        pwd -P
        builtin cd "$old_pwd"
        return 0
    end

    echo "$path"
    return 1
end

function __codex_sync_repo_on_startup --argument-names repo
    set -l branch (git -C "$repo" branch --show-current 2>/dev/null)
    if test "$branch" = main
        echo "main を最新に pull しています..."
        if not git -C "$repo" pull --ff-only origin main 2>/dev/null
            echo "⚠ pull に失敗しました（オフラインまたはコンフリクト）。現在の状態で続行します。"
        end
    else
        echo "origin/main を取得しています..."
        if not git -C "$repo" fetch origin main 2>/dev/null
            echo "⚠ fetch に失敗しました（オフライン等）。現在の状態で続行します。"
        end
    end
end

function __codex_normalize_cd_args
    set -l normalized
    set -l expect_cd_path 0

    for arg in $argv
        if test $expect_cd_path -eq 1
            set -a normalized (__codex_physical_path "$arg")
            set expect_cd_path 0
            continue
        end

        set -a normalized "$arg"
        switch $arg
            case -C --cd
                set expect_cd_path 1
        end
    end

    printf '%s\n' $normalized
end

function __codex_run
    set -l old_pwd "$PWD"
    set -l physical_pwd (__codex_physical_path "$PWD")
    set -l normalized_argv (__codex_normalize_cd_args $argv)

    builtin cd "$physical_pwd"
    command codex $normalized_argv
    set -l exit_code $status
    builtin cd "$old_pwd"
    return $exit_code
end

function __codex_reset_pane_title
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    # pane title を pwd basename に戻す。手動指定の @fixed_title (prefix + t) も
    # __ai_pane_title_sync clear がクリアし、AI 終了時は border を basename 表示に戻す。
    set -l title (basename "$PWD")
    tmux select-pane -t "$TMUX_PANE" -T "$title" 2>/dev/null
    __codex_ensure_ai_pane_title_sync
    __ai_pane_title_sync clear "$TMUX_PANE"
end

function __codex_mark_pane_input_app
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    __codex_ensure_ai_pane_title_sync
    __ai_pane_title_sync mark-app "$TMUX_PANE" codex
end

function __codex_mark_session_probe --argument-names physical_pwd started_at
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    __codex_ensure_ai_pane_title_sync
    __ai_pane_title_sync mark-codex "$TMUX_PANE" "$started_at" "$physical_pwd"
end

function __codex_target_path
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

    __codex_physical_path "$path"
end

function __codex_agmsg_tmux_scope_join --argument-names project_path
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    set -l helper "$HOME/.config/tmux/agmsg-tmux-join.sh"
    set -l skill_dir "$HOME/.agents/skills/agmsg"
    if set -q AGMSG_SKILL_DIR
        set skill_dir "$AGMSG_SKILL_DIR"
    end
    test -x "$helper"; or return
    test -x "$skill_dir/scripts/join.sh"; or return

    command "$helper" --type codex --target "$TMUX_PANE" --project-path "$project_path" --skip-delivery >/dev/null 2>&1
end

function __codex_export_agmsg_identity
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    set -gx AGMSG_TMUX_CURRENT_PANE "$TMUX_PANE"

    set -l socket_path (tmux display-message -p -t "$TMUX_PANE" '#{socket_path}' 2>/dev/null)
    if test -n "$socket_path"
        set -gx AGMSG_TMUX_SOCKET "$socket_path"
    end

    set -l identity (tmux show-option -p -v -t "$TMUX_PANE" @agmsg_active_identity 2>/dev/null)
    if test -n "$identity"
        set -gx AGMSG_AGENT_ID "$identity"
    end
end

function __codex_dotfiles_agent_add_dir --argument-names launch_pwd target_path
    set -l common_dir (git -C "$target_path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    if test $status -ne 0
        return
    end

    set -l dotfiles_root (dirname "$common_dir")
    set -l projects_dir (dirname "$dotfiles_root")
    set -l agent_root (dirname "$projects_dir")

    if test (basename "$dotfiles_root") != dotfiles
        return
    end
    if test (basename "$projects_dir") != projects
        return
    end
    if not test -d "$agent_root/home/config/codex"
        return
    end

    python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$agent_root" "$launch_pwd" 2>/dev/null
end

function __codex_set_pane_base_title
    if not set -q TMUX
        return
    end
    if not set -q TMUX_PANE
        return
    end

    __codex_ensure_ai_pane_title_sync
    set -l path (__codex_target_path $argv)
    tmux set-option -p -t "$TMUX_PANE" @fixed_title "" 2>/dev/null
    __ai_pane_title_sync set-base "$TMUX_PANE" (basename "$path") codex-fallback
end

function __codex_run_interactive
    __codex_mark_pane_input_app
    set -l old_pwd "$PWD"
    set -l physical_pwd (__codex_physical_path "$PWD")
    set -l normalized_argv (__codex_normalize_cd_args $argv)
    set -l target_path (__codex_target_path $normalized_argv)
    set -l dotfiles_agent_add_dir (__codex_dotfiles_agent_add_dir "$physical_pwd" "$target_path")
    set -l started_at (date +%s)
    set -l watcher_pid

    __codex_set_pane_base_title $normalized_argv
    builtin cd "$physical_pwd"
    __codex_mark_session_probe "$target_path" "$started_at"
    __codex_agmsg_tmux_scope_join "$target_path"
    __codex_export_agmsg_identity
    if set -q TMUX; and set -q TMUX_PANE
        set -l helper_path (__codex_ai_pane_title_sync_path)
        if test -n "$helper_path"
            command fish -c 'source "$argv[1]"; sleep 0.5; __ai_pane_title_sync codex-watch "$argv[2]" "$argv[3]" "$argv[4]"' "$helper_path" "$TMUX_PANE" "$target_path" "$started_at" >/dev/null 2>&1 &
            set watcher_pid $last_pid
        end
    end
    if test -n "$dotfiles_agent_add_dir"
        command codex --add-dir "$dotfiles_agent_add_dir" $normalized_argv
    else
        command codex $normalized_argv
    end
    set -l exit_code $status
    if test -n "$watcher_pid"
        kill $watcher_pid 2>/dev/null
    end
    builtin cd "$old_pwd"
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
    set repo (__codex_physical_path "$repo")

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

    # 非対話 subcommand は Codex 本体へそのまま渡す。resume/fork/-C は TUI なので title sync を通す。
    for arg in $argv
        switch $arg
            case exec e review login logout mcp plugin mcp-server app-server app completion sandbox debug apply a cloud exec-server features help
                __codex_run $argv
                return
            case resume fork
                __codex_run_interactive $argv
                return
            case --help -h --version -V
                __codex_run $argv
                return
        end
    end
    if contains -- -C $argv; or contains -- --cd $argv
        __codex_run_interactive $argv
        return
    end

    set -l repo (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        # git リポジトリ外ではそのまま実行
        __codex_run_interactive $argv
        return
    end
    set repo (__codex_physical_path "$repo")

    __codex_sync_repo_on_startup "$repo"

    set -l wt_dir "$repo/.codex/worktrees"
    set -l choices

    if test -d "$wt_dir"
        for d in $wt_dir/*/
            if test -d "$d"
                set -a choices (basename $d)
            end
        end
    end

    if test (count $choices) -eq 0; and test (count $argv) -eq 0
        __codex_run_interactive
        return
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
