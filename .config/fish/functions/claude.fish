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

function __claude_agmsg_tmux_scope_join --argument-names project_path
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

    command "$helper" --type claude-code --target "$TMUX_PANE" --project-path "$project_path" --skip-delivery >/dev/null 2>&1
end

function __claude_export_agmsg_identity
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

function __claude_agmsg_should_bootstrap_worker
    if not set -q AGMSG_AGENT_ID
        return 1
    end

    switch "$AGMSG_AGENT_ID"
        case 'worker*' 'reviewer*'
            return 0
        case '*'
            return 1
    end
end

function __claude_agmsg_worker_bootstrap_prompt
    printf '%s\n' 'agmsg worker bootstrap: Monitor が未起動なら起動し、ready だけ返してください。依頼処理はしないでください。'
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
        __claude_agmsg_tmux_scope_join (__claude_physical_path "$PWD")
        __claude_export_agmsg_identity
    end

    if test $original_argc -eq 0
        if __claude_agmsg_should_bootstrap_worker
            command claude (__claude_agmsg_worker_bootstrap_prompt)
            set -l exit_code $status
            if set -q TMUX; and set -q TMUX_PANE
                tmux select-pane -t "$TMUX_PANE" -T (basename "$PWD") 2>/dev/null
                __claude_ensure_ai_pane_title_sync
                __ai_pane_title_sync clear "$TMUX_PANE"
            end
            return $exit_code
        end
    end

    command claude $argv
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

function claude --description "Claude Code を worktree モードで起動（既存選択 or 新規作成）"
    # --worktree や -w が既に指定されている場合、またはサブコマンド/フラグがある場合はそのまま実行
    for arg in $argv
        switch $arg
            case --worktree -w --help -h --version -v --resume -r
                __claude_run $argv
                return
        end
    end

    set -l repo (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        # git リポジトリ外ではそのまま実行
        __claude_run $argv
        return
    end
    set repo (__claude_physical_path "$repo")

    __claude_sync_repo_on_startup "$repo"

    set -l wt_dir "$repo/.claude/worktrees"
    set -l choices

    if test -d "$wt_dir"
        for d in $wt_dir/*/
            if test -d "$d"
                set -a choices (basename $d)
            end
        end
    end

    if test (count $choices) -eq 0; and test (count $argv) -eq 0
        __claude_run
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
        __claude_run $argv
    else if string match -qr '^\d+$' "$sel"; and test (count $choices) -gt 0 -a "$sel" -ge 1 -a "$sel" -le (count $choices)
        __claude_run --worktree $choices[$sel] $argv
    else
        # non-ASCII characters detected → generate English worktree name via LLM
        if string match -qr '[^\x00-\x7F]' "$sel"
            echo "名前を生成中..."
            set -l stderr_file (mktemp)
            set -l raw (command claude --print --model haiku --no-session-persistence --system-prompt "You are a naming assistant. Output ONLY the requested name, nothing else." "Convert the following Japanese task description into a short, kebab-case English worktree branch name (2-4 words, lowercase, hyphens only, no explanation, output ONLY the name): $sel" 2>$stderr_file)
            set -l exit_code $status
            set -l generated (string trim -- $raw[1])
            if test -n "$generated"; and string match -qr '^[a-z][a-z0-9-]*$' "$generated"
                rm -f $stderr_file
                echo "→ $generated"
                read -P "この名前でOK? (Enter=OK / 別の名前を入力) > " confirm
                if test -n "$confirm"
                    set generated $confirm
                end
                set sel $generated
            else
                echo "名前の自動生成に失敗しました (exit=$exit_code, output='$generated')。"
                if test -s $stderr_file
                    echo "エラー詳細:"
                    cat $stderr_file
                end
                rm -f $stderr_file
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
        __claude_run --worktree $sel $argv
    end
end
