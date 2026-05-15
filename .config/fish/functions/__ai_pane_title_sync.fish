function __ai_pane_title_sync_clean --argument-names title
    set title (string replace -ar '[\t\r\n]+' ' ' -- "$title")
    string trim -- "$title"
end

function __ai_pane_title_sync_set_base --argument-names pane_id title source
    test -n "$pane_id"; or return 1

    set -l clean_title (__ai_pane_title_sync_clean "$title")
    test -n "$clean_title"; or return 1

    tmux set-option -p -t "$pane_id" @ai_base_title "$clean_title" 2>/dev/null
    test -n "$source"; and tmux set-option -p -t "$pane_id" @ai_title_source "$source" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_title_updated_at (date +%s) 2>/dev/null
end

function __ai_pane_title_sync_clear --argument-names pane_id
    test -n "$pane_id"; or return 1

    tmux set-option -p -t "$pane_id" @ai_base_title "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_title_source "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_title_updated_at "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_app "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_input_app "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_codex_started_at "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_codex_cwd "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_codex_session_file "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_claude_started_at "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_claude_cwd "" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_claude_session_file "" 2>/dev/null
end

function __ai_pane_title_sync_codex_session_start_epoch --argument-names file
    set -l name (basename "$file")
    set -l match (string match -r '^rollout-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-' -- "$name")
    test (count $match) -ge 5; or return 1

    set -l stamp (printf '%sT%s-%s-%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]")
    command date -j -f '%Y-%m-%dT%H-%M-%S' "$stamp" +%s 2>/dev/null; or command date -d (printf '%s %s:%s:%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]") +%s 2>/dev/null
end

function __ai_pane_title_sync_codex_find_session_file --argument-names cwd started_at
    if not command -q jq
        return 1
    end
    string match -qr '^[0-9]+$' -- "$started_at"; or return 1

    set -l sessions_dir "$HOME/.codex/sessions"
    test -d "$sessions_dir"; or return 1

    set -l best_file
    set -l best_delta 999999999
    for file in (command find "$sessions_dir" -type f -name 'rollout-*.jsonl' -mtime -3 2>/dev/null)
        set -l session_cwd (command head -n 1 "$file" | command jq -r 'select(.type == "session_meta") | .payload.cwd // empty' 2>/dev/null)
        test "$session_cwd" = "$cwd"; or continue

        set -l session_started (__ai_pane_title_sync_codex_session_start_epoch "$file")
        string match -qr '^[0-9]+$' -- "$session_started"; or continue
        set -l delta (math "$session_started - $started_at")
        if test "$delta" -ge -5; and test "$delta" -le 600; and test "$delta" -lt "$best_delta"
            set best_delta "$delta"
            set best_file "$file"
        end
    end

    test -n "$best_file"; and printf '%s\n' "$best_file"
end

function __ai_pane_title_sync_codex_session_id_from_file --argument-names file
    set -l name (basename "$file")
    set -l match (string match -r '^rollout-.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$' -- "$name")
    if test (count $match) -ge 2
        printf '%s\n' "$match[2]"
        return 0
    end

    if command -q jq; and test -f "$file"
        command head -n 1 "$file" | command jq -r 'select(.type == "session_meta") | .payload.id // empty' 2>/dev/null
    end
end

function __ai_pane_title_sync_codex_thread_title --argument-names session_file
    command -q sqlite3; or return 1
    test -f "$session_file"; or return 1

    set -l db "$HOME/.codex/state_5.sqlite"
    test -f "$db"; or return 1

    set -l escaped_file (string replace -a "'" "''" -- "$session_file")
    set -l query "select title from threads where rollout_path = '$escaped_file'"
    set -l session_id (__ai_pane_title_sync_codex_session_id_from_file "$session_file")
    if test -n "$session_id"
        set -l escaped_id (string replace -a "'" "''" -- "$session_id")
        set query "$query or id = '$escaped_id'"
    end
    set query "$query order by updated_at desc limit 1;"

    set -l title (command sqlite3 "$db" "$query" 2>/dev/null | command head -n 1)
    __ai_pane_title_sync_clean "$title"
end

function __ai_pane_title_sync_codex_watch --argument-names pane_id cwd started_at fallback_title
    # NOTE: 関数定義ファイル更新を検知したら新版で自己 exec する (live 反映機構)。
    # fish の autoload キャッシュも source 済みプロセスも reload しないため、
    # watch loop が旧版で動き続ける問題を防ぐ。
    set -l function_path "$HOME/.config/fish/functions/__ai_pane_title_sync.fish"
    # -L (stat(2) = symlink follow) 必須: BSD stat (macOS) default は lstat(2) で
    # symlink 自体の mtime しか返さない。GNU stat (Linux) は default 辿るが -L も同義。
    set -l watch_mtime (command stat -L -f %m "$function_path" 2>/dev/null; or command stat -L -c %Y "$function_path" 2>/dev/null)
    set -l last_title ""
    while true
        if test -n "$watch_mtime"
            set -l current_mtime (command stat -L -f %m "$function_path" 2>/dev/null; or command stat -L -c %Y "$function_path" 2>/dev/null)
            if test -n "$current_mtime"; and test "$current_mtime" != "$watch_mtime"
                exec command fish -c 'source $argv[1]; __ai_pane_title_sync codex-watch $argv[2] $argv[3] $argv[4] $argv[5]' "$function_path" "$pane_id" "$cwd" "$started_at" "$fallback_title"
            end
        end

        set -l session_file (tmux show-option -pqv -t "$pane_id" @ai_codex_session_file 2>/dev/null)
        if test -z "$session_file"; or not test -f "$session_file"
            set session_file (__ai_pane_title_sync_codex_find_session_file "$cwd" "$started_at")
            test -n "$session_file"; and tmux set-option -p -t "$pane_id" @ai_codex_session_file "$session_file" 2>/dev/null
        end

        if test -n "$session_file"
            set -l title (__ai_pane_title_sync_codex_thread_title "$session_file")
            if test -n "$title"; and test "$title" != "$last_title"
                __ai_pane_title_sync_set_base "$pane_id" "$title" codex-thread
                set last_title "$title"
            end
        end

        sleep 2
    end
end

function __ai_pane_title_sync_claude_session_mtime --argument-names file
    command stat -f %m "$file" 2>/dev/null; or command stat -c %Y "$file" 2>/dev/null
end

function __ai_pane_title_sync_claude_find_session_file --argument-names cwd started_at
    if not command -q jq
        return 1
    end
    string match -qr '^[0-9]+$' -- "$started_at"; or return 1

    set -l projects_dir "$HOME/.claude/projects"
    test -d "$projects_dir"; or return 1

    set -l best_file
    set -l best_mtime 0
    for file in (command find "$projects_dir" -type f -name '*.jsonl' -mtime -3 2>/dev/null)
        set -l mtime (__ai_pane_title_sync_claude_session_mtime "$file")
        string match -qr '^[0-9]+$' -- "$mtime"; or continue
        test "$mtime" -ge (math "$started_at - 5"); or continue
        test "$mtime" -ge "$best_mtime"; or continue

        set -l session_cwd (command head -n 20 "$file" | command jq -r 'select(.cwd != null) | .cwd' 2>/dev/null | command head -n 1)
        test "$session_cwd" = "$cwd"; or continue

        set best_mtime "$mtime"
        set best_file "$file"
    end

    test -n "$best_file"; and printf '%s\n' "$best_file"
end

function __ai_pane_title_sync_claude_slug --argument-names session_file
    command -q jq; or return 1
    test -f "$session_file"; or return 1

    set -l slug (command tail -n 200 "$session_file" | command jq -r 'select(.slug != null) | .slug' 2>/dev/null | command tail -n 1)
    __ai_pane_title_sync_clean "$slug"
end

function __ai_pane_title_sync_claude_watch --argument-names pane_id cwd started_at
    # NOTE: 関数定義ファイル更新を検知したら新版で自己 exec する (live 反映機構)。
    # fish の autoload キャッシュも source 済みプロセスも reload しないため、
    # watch loop が旧版で動き続ける問題を防ぐ。
    set -l function_path "$HOME/.config/fish/functions/__ai_pane_title_sync.fish"
    # -L (stat(2) = symlink follow) 必須: BSD stat (macOS) default は lstat(2) で
    # symlink 自体の mtime しか返さない。GNU stat (Linux) は default 辿るが -L も同義。
    set -l watch_mtime (command stat -L -f %m "$function_path" 2>/dev/null; or command stat -L -c %Y "$function_path" 2>/dev/null)
    set -l last_title ""
    while true
        if test -n "$watch_mtime"
            set -l current_mtime (command stat -L -f %m "$function_path" 2>/dev/null; or command stat -L -c %Y "$function_path" 2>/dev/null)
            if test -n "$current_mtime"; and test "$current_mtime" != "$watch_mtime"
                exec command fish -c 'source $argv[1]; __ai_pane_title_sync claude-watch $argv[2] $argv[3] $argv[4]' "$function_path" "$pane_id" "$cwd" "$started_at"
            end
        end

        # 同 pane 内で claude が再起動された場合、mark-claude が @ai_claude_started_at を
        # 新値に更新する。watcher 引数の started_at は spawn 時の固定値なので、
        # 毎ループで pane option から最新値に追従し、変化したら session cache を捨てる。
        set -l current_started_at (tmux show-option -pqv -t "$pane_id" @ai_claude_started_at 2>/dev/null)
        if string match -qr '^[0-9]+$' -- "$current_started_at"; and test "$current_started_at" != "$started_at"
            set started_at "$current_started_at"
            tmux set-option -p -t "$pane_id" @ai_claude_session_file "" 2>/dev/null
        end

        set -l session_file (tmux show-option -pqv -t "$pane_id" @ai_claude_session_file 2>/dev/null)
        # 毎ループ最新の候補を find する。session_file 未設定なら採用、設定済みでも
        # 候補の mtime が現 session_file より新しければ切り替える。
        # find_session_file 自体が「mtime ≥ started_at - 5」を必須条件にしているため、
        # 古い jsonl は候補に入らず、新 jsonl があれば mtime 比較で必ず上書きされる。
        # よって cff3f05 で導入した別途の mtime invalidate (ブロックで強制クリア) は
        # ここでは不要 (新ロジックで覆われる)。
        set -l candidate (__ai_pane_title_sync_claude_find_session_file "$cwd" "$started_at")
        if test -n "$candidate"
            if test -z "$session_file"; or not test -f "$session_file"
                set session_file "$candidate"
                tmux set-option -p -t "$pane_id" @ai_claude_session_file "$session_file" 2>/dev/null
            else if test "$candidate" != "$session_file"
                set -l candidate_mtime (__ai_pane_title_sync_claude_session_mtime "$candidate")
                set -l current_mtime (__ai_pane_title_sync_claude_session_mtime "$session_file")
                if string match -qr '^[0-9]+$' -- "$candidate_mtime"; and string match -qr '^[0-9]+$' -- "$current_mtime"; and test "$candidate_mtime" -gt "$current_mtime"
                    set session_file "$candidate"
                    tmux set-option -p -t "$pane_id" @ai_claude_session_file "$session_file" 2>/dev/null
                end
            end
        end

        if test -n "$session_file"
            set -l title (__ai_pane_title_sync_claude_slug "$session_file")
            if test -n "$title"; and test "$title" != "$last_title"
                __ai_pane_title_sync_set_base "$pane_id" "$title" claude-slug
                set last_title "$title"
            end
        end

        sleep 2
    end
end

function __ai_pane_title_sync --argument-names command pane_id
    switch "$command"
        case set-base
            __ai_pane_title_sync_set_base "$pane_id" "$argv[3]" "$argv[4]"
        case clear
            __ai_pane_title_sync_clear "$pane_id"
        case mark-app
            test -n "$pane_id"; or return 1
            set -l app "$argv[3]"
            tmux set-option -p -t "$pane_id" @ai_app "$app" 2>/dev/null
            if test "$app" = codex
                tmux set-option -p -t "$pane_id" @ai_input_app codex 2>/dev/null
            end
        case mark-codex
            test -n "$pane_id"; or return 1
            tmux set-option -p -t "$pane_id" @ai_app codex 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_input_app codex 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_codex_started_at "$argv[3]" 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_codex_cwd "$argv[4]" 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_codex_session_file "" 2>/dev/null
        case mark-claude
            test -n "$pane_id"; or return 1
            tmux set-option -p -t "$pane_id" @ai_app claude 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_claude_started_at "$argv[3]" 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_claude_cwd "$argv[4]" 2>/dev/null
            tmux set-option -p -t "$pane_id" @ai_claude_session_file "" 2>/dev/null
        case codex-watch
            __ai_pane_title_sync_codex_watch "$pane_id" "$argv[3]" "$argv[4]" "$argv[5]"
        case claude-watch
            __ai_pane_title_sync_claude_watch "$pane_id" "$argv[3]" "$argv[4]"
        case '*'
            echo "__ai_pane_title_sync: unknown command '$command'" >&2
            return 1
    end
end
