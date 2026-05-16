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
    if set -q TMUX; and set -q TMUX_PANE
        __claude_ensure_ai_pane_title_sync
        set -l fallback_title (__claude_fallback_title $argv)
        __ai_pane_title_sync set-base "$TMUX_PANE" "$fallback_title" claude-fallback
    end

    command claude $argv
    set -l exit_code $status

    # SessionEnd hook (`prompt_input_exit|logout`) が走らないケース
    # (Ctrl+C / kill / 異常終了 等) のために fallback で pane option を clear する。
    # 二重実行は冪等 (set-option -pu は idempotent)。
    if set -q TMUX; and set -q TMUX_PANE
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
        echo "main を最新に pull しています..."
        if not git -C "$repo" pull origin main --ff-only 2>/dev/null
            echo "⚠ pull に失敗しました（オフラインまたはコンフリクト）。現在の状態で続行します。"
        end
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
        echo "main を最新に pull しています..."
        if not git -C "$repo" pull origin main --ff-only 2>/dev/null
            echo "⚠ pull に失敗しました（オフラインまたはコンフリクト）。現在の状態で続行します。"
        end
        __claude_run --worktree $sel $argv
    end
end
