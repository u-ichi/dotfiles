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

# agent-hub shim は前景が node になり herdr の agent 検出が外れる。
# 既定は素の codex。明示時のみ wrap: AGENT_HUB_FORCE_WRAP=1 codex
function __codex_should_bypass_agent_hub
    set -q AGENT_HUB_AUTO_WRAP_ACTIVE; and return 0
    set -q AGENT_HUB_AUTO_WRAP_BYPASS; and return 0
    set -q AGENT_HUB_FORCE_WRAP; and return 1
    # 既定: shim なし（herdr 検出 / 通常起動）
    return 0
end

function __codex_run_agent_hub_interactive
    if __codex_should_bypass_agent_hub; or not type -q agent-hub
        command codex $argv
        return $status
    end

    command env AGENT_HUB_AUTO_WRAP_ACTIVE=1 agent-hub codex $argv
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

function __codex_explicit_sandbox_mode
    set -l expect_mode 0

    for arg in $argv
        if test $expect_mode -eq 1
            echo "$arg"
            return 0
        end

        switch $arg
            case -s --sandbox
                set expect_mode 1
            case '--sandbox=*'
                string replace -- '--sandbox=' '' "$arg"
                return 0
            case '-s=*'
                string replace -- '-s=' '' "$arg"
                return 0
            case --dangerously-bypass-approvals-and-sandbox
                echo danger-full-access
                return 0
        end
    end

    return 1
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
    if set -q TMUX; and set -q TMUX_PANE
        set -l helper_path (__codex_ai_pane_title_sync_path)
        if test -n "$helper_path"
            command fish -c 'source "$argv[1]"; sleep 0.5; __ai_pane_title_sync codex-watch "$argv[2]" "$argv[3]" "$argv[4]"' "$helper_path" "$TMUX_PANE" "$target_path" "$started_at" >/dev/null 2>&1 &
            set watcher_pid $last_pid
        end
    end
    if test -n "$dotfiles_agent_add_dir"
        set -l sandbox_mode (__codex_explicit_sandbox_mode $normalized_argv)
        switch "$sandbox_mode"
            case read-only
                __codex_run_agent_hub_interactive $normalized_argv
            case workspace-write danger-full-access
                __codex_run_agent_hub_interactive --add-dir "$dotfiles_agent_add_dir" $normalized_argv
            case '*'
                __codex_run_agent_hub_interactive -s workspace-write --add-dir "$dotfiles_agent_add_dir" $normalized_argv
        end
    else
        __codex_run_agent_hub_interactive $normalized_argv
    end
    set -l exit_code $status
    if test -n "$watcher_pid"
        kill $watcher_pid 2>/dev/null
    end
    builtin cd "$old_pwd"
    __codex_reset_pane_title
    return $exit_code
end

function codex --description "Codex CLI を起動"
    # pipe / redirect 経由の codex exec 等は対話セレクタを出さず、そのまま実行する。
    if not isatty stdin
        __codex_run $argv
        return
    end

    # 非対話 subcommand は Codex 本体へそのまま渡す。resume/fork/-C は TUI なので title sync を通す。
    for arg in $argv
        switch $arg
            case exec e review login logout mcp plugin mcp-server app-server remote-control app completion update doctor sandbox debug apply a archive delete unarchive cloud exec-server features help
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
        __codex_run_interactive $argv
        return
    end
    set repo (__codex_physical_path "$repo")

    __codex_sync_repo_on_startup "$repo"

    __codex_run_interactive $argv
end
