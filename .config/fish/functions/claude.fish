function __claude_ai_pane_title_sync_path
    set -l function_file (status filename)
    set -l helper_path (dirname "$function_file")/__ai_pane_title_sync.fish
    if not test -f "$helper_path"
        set -l linked_file (command readlink "$function_file" 2>/dev/null)
        test -n "$linked_file"; and set helper_path (dirname "$linked_file")/__ai_pane_title_sync.fish
    end

    test -f "$helper_path"; and printf '%s\n' "$helper_path"
end

function __claude_ensure_ai_pane_title_sync
    functions -q __ai_pane_title_sync; and return 0

    set -l helper_path (__claude_ai_pane_title_sync_path)
    test -n "$helper_path"; and source "$helper_path"
end

function __claude_physical_path
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

function __claude_sync_repo_on_startup --argument-names repo
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

function __claude_fallback_title
    set -l title (basename "$PWD")
    set -l argc (count $argv)
    if test $argc -gt 0
        for i in (seq $argc)
            switch $argv[$i]
                case --worktree -w
                    set -l next (math $i + 1)
                    if test $next -le $argc
                        set title $argv[$next]
                    end
            end
        end
    end

    printf '%s\n' "$title"
end

# agent-hub shim は前景が node になり herdr の agent 検出が外れる。
# 既定は素の claude。明示時のみ wrap: AGENT_HUB_FORCE_WRAP=1 claude
function __claude_should_bypass_agent_hub
    set -q AGENT_HUB_AUTO_WRAP_ACTIVE; and return 0
    set -q AGENT_HUB_AUTO_WRAP_BYPASS; and return 0
    set -q AGENT_HUB_FORCE_WRAP; and return 1
    # 既定: shim なし（herdr 検出 / 通常起動）
    return 0
end

function __claude_run_agent_hub_interactive
    if __claude_should_bypass_agent_hub; or not type -q agent-hub
        command claude $argv
        return $status
    end

    command env AGENT_HUB_AUTO_WRAP_ACTIVE=1 agent-hub claude $argv
end

function __claude_should_run_direct
    if not isatty stdin
        return 0
    end
    if not isatty stdout
        return 0
    end

    for arg in $argv
        switch $arg
            case -p --print --help -h --version -v
                return 0
        end
    end

    set -l first_non_option
    for arg in $argv
        switch $arg
            case '-*'
                continue
            case '*'
                set first_non_option "$arg"
                break
        end
    end

    switch "$first_non_option"
        case agents auth auto-mode doctor install mcp plugin plugins project setup-token ultrareview update upgrade
            return 0
    end

    return 1
end

# Claude Code 起動の内部ヘルパ。worktree モードのフラグ分岐から共通で呼ぶ。
#
# session 情報 (session_id / cwd / started_at) の pane option 書き込みは
# claude-code-base-repository 側の SessionStart hook (sidepane-session-start.sh)
# が担う。fish 側は session 起動直前に fallback title だけセットし (hook 発火
# までの数秒間 sidebar に何か表示するため)、起動後の cleanup は SessionEnd hook
# (sidepane-session-end.sh + session-end-reset-pane-title.sh) に任せる。
#
# 旧版は fish 側で watcher process を spawn して jsonl を mtime + cwd で
# ヒューリスティック探索していたが、orphan watcher の race が頻発したため廃止。
function __claude_run
    set -l original_argc (count $argv)

    if set -q TMUX; and set -q TMUX_PANE
        __claude_ensure_ai_pane_title_sync
        set -l fallback_title (__claude_fallback_title $argv)
        __ai_pane_title_sync set-base "$TMUX_PANE" "$fallback_title" claude-fallback
        __ai_pane_title_sync mark-app "$TMUX_PANE" claude
    end

    __claude_run_agent_hub_interactive $argv
    set -l exit_code $status

    # 終了時の pane title リセット。
    # SessionEnd hook (session-end-reset-pane-title.sh) は matcher を
    # `prompt_input_exit|logout` に絞っているが、これは非対話モード
    # (`claude --print`) の入力終端用 reason。対話セッションを Ctrl+D / `/exit`
    # で抜ける通常終了は reason が `other` (`/exit` では hook 自体が発火しない:
    # anthropics/claude-code#17885) のため matcher にマッチせず、hook 経由の
    # リセットが効かない。codex 側 (__codex_reset_pane_title) と同様に wrapper で
    # pane title を pwd basename に戻し、pane option も clear する。
    # hook と二重に走っても冪等 (select-pane -T / set-option -p は idempotent)。
    if set -q TMUX; and set -q TMUX_PANE
        tmux select-pane -t "$TMUX_PANE" -T (basename "$PWD") 2>/dev/null
        __claude_ensure_ai_pane_title_sync
        __ai_pane_title_sync clear "$TMUX_PANE"
    end
    return $exit_code
end

function claude --description "Claude Code を起動"
    if __claude_should_run_direct $argv
        command claude $argv
        return $status
    end

    set -l repo (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -eq 0
        set repo (__claude_physical_path "$repo")
        __claude_sync_repo_on_startup "$repo"
    end

    __claude_run $argv
end
