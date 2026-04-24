# Claude 終了後に tmux pane title を pwd basename にリセットする内部ヘルパ
# Claude Code は OSC 2 で動的に pane title を書き換えるが、終了時には何も送らず、
# 古い作業タイトル (cc-panes の「● 待ち」判定や非 active 時 border 色にも影響) が
# そのまま残る。終了直後に OSC 2 を 1 回送って「作業セッションが閉じた」状態に戻す。
function __claude_run
    command claude $argv
    set -l rc $status
    if set -q TMUX
        printf '\e]2;%s\e\\' (basename (pwd))
    end
    return $rc
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
