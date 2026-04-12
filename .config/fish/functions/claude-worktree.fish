function claude-worktree --description "Claude Code worktree に cd する"
    set -l repo (git rev-parse --show-toplevel 2>/dev/null)
    if test $status -ne 0
        echo "git リポジトリ内で実行してください" >&2
        return 1
    end

    set -l wt_dir "$repo/.claude/worktrees"

    if not test -d "$wt_dir"
        echo "worktree がありません: $wt_dir" >&2
        return 1
    end

    set -l worktrees
    for d in $wt_dir/*/
        if test -d "$d"
            set -a worktrees (basename $d)
        end
    end

    if test (count $worktrees) -eq 0
        echo "worktree がありません" >&2
        return 1
    end

    # 引数が指定された場合、部分一致で検索
    if test (count $argv) -gt 0
        set -l name $argv[1]

        # 完全一致
        if contains -- $name $worktrees
            cd "$wt_dir/$name"
            return
        end

        # 部分一致
        set -l matches
        for wt in $worktrees
            if string match -q "*$name*" $wt
                set -a matches $wt
            end
        end

        if test (count $matches) -eq 1
            cd "$wt_dir/$matches[1]"
            return
        else if test (count $matches) -gt 1
            echo "複数の worktree がマッチしました:"
            for m in $matches
                echo "  $m"
            end
            return 1
        else
            echo "該当する worktree がありません: $name" >&2
            echo "利用可能:" >&2
            for wt in $worktrees
                echo "  $wt" >&2
            end
            return 1
        end
    end

    # 引数なし: 一覧から選択
    if test (count $worktrees) -eq 1
        cd "$wt_dir/$worktrees[1]"
        return
    end

    echo "worktree を選択:"
    for i in (seq (count $worktrees))
        # ブランチ名も表示
        set -l branch (git -C "$wt_dir/$worktrees[$i]" branch --show-current 2>/dev/null; or echo "?")
        echo "  $i) $worktrees[$i] ($branch)"
    end
    read -P "> " sel

    if string match -qr '^\d+$' "$sel"; and test "$sel" -ge 1 -a "$sel" -le (count $worktrees)
        cd "$wt_dir/$worktrees[$sel]"
    else
        echo "キャンセルしました"
        return 1
    end
end
