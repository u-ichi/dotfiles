function __ai_pane_title_sync_clean --argument-names title
    set title (string replace -ar '[\t\r\n]+' ' ' -- "$title")
    set title (string trim -- "$title")
    test -n "$title"; and printf '%s\n' "$title"
end

function __ai_pane_title_sync_set_base --argument-names pane_id title source
    test -n "$pane_id"; or return 1

    set -l clean_title (__ai_pane_title_sync_clean "$title")
    test -n "$clean_title"; or return 1

    # tmux-bridge ヘッダは base_title に記録しない (表示が壊れるため)
    string match -q '\[tmux-bridge *' -- "$clean_title"; and return 0

    tmux set-option -p -t "$pane_id" @ai_base_title "$clean_title" 2>/dev/null
    test -n "$source"; and tmux set-option -p -t "$pane_id" @ai_title_source "$source" 2>/dev/null
    tmux set-option -p -t "$pane_id" @ai_title_updated_at (date +%s) 2>/dev/null
end

function __ai_pane_title_sync_clear --argument-names pane_id
    test -n "$pane_id"; or return 1

    # AI セッション終了時のクリーンアップ。手動指定の @fixed_title (prefix + t) も
    # ここでクリアし、pane border を pane_title (basename) 表示に戻す。
    tmux set-option -p -t "$pane_id" @fixed_title "" 2>/dev/null
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
    tmux set-option -p -t "$pane_id" @ai_claude_session_id "" 2>/dev/null
end

function __ai_pane_title_sync_codex_session_start_epoch --argument-names file
    set -l name (basename "$file")
    set -l match (string match -r '^rollout-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-' -- "$name")
    test (count $match) -ge 5; or return 1

    set -l stamp (printf '%sT%s-%s-%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]")
    command date -j -f '%Y-%m-%dT%H-%M-%S' "$stamp" +%s 2>/dev/null; or command date -d (printf '%s %s:%s:%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]") +%s 2>/dev/null
end

function __ai_pane_title_sync_codex_session_id_from_title --argument-names title
    set -l match (string match -r '([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})' -- "$title")
    test (count $match) -ge 2; and printf '%s\n' "$match[2]"
end

function __ai_pane_title_sync_codex_session_file_by_id --argument-names session_id
    string match -qr '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -- "$session_id"; or return 1

    set -l sessions_dir "$HOME/.codex/sessions"
    test -d "$sessions_dir"; or return 1

    command find "$sessions_dir" -type f -name "*$session_id.jsonl" -mtime -30 2>/dev/null | command head -n 1
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
    set -l candidate_count 0
    for file in (command find "$sessions_dir" -type f -name 'rollout-*.jsonl' -mtime -3 2>/dev/null)
        set -l session_cwd (command head -n 1 "$file" | command jq -r 'select(.type == "session_meta") | .payload.cwd // empty' 2>/dev/null)
        test "$session_cwd" = "$cwd"; or continue

        set -l session_started (__ai_pane_title_sync_codex_session_start_epoch "$file")
        string match -qr '^[0-9]+$' -- "$session_started"; or continue
        set -l delta (math "$session_started - $started_at")
        if test "$delta" -ge -5; and test "$delta" -le 30
            set candidate_count (math "$candidate_count + 1")
            if test "$delta" -lt "$best_delta"
                set best_delta "$delta"
                set best_file "$file"
            end
        end
    end

    test "$candidate_count" -eq 1; and test -n "$best_file"; and printf '%s\n' "$best_file"
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

function __ai_pane_title_sync_codex_goal_title --argument-names session_file
    command -q sqlite3; or return 1
    test -f "$session_file"; or return 1

    set -l session_id (__ai_pane_title_sync_codex_session_id_from_file "$session_file")
    test -n "$session_id"; or return 1

    set -l db "$HOME/.codex/goals_1.sqlite"
    test -f "$db"; or return 1

    set -l escaped_id (string replace -a "'" "''" -- "$session_id")
    set -l title (command sqlite3 "$db" "select objective from thread_goals where thread_id = '$escaped_id' and status = 'active' limit 1;" 2>/dev/null | command head -n 1)
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
                exec fish -c 'source $argv[1]; __ai_pane_title_sync codex-watch $argv[2] $argv[3] $argv[4] $argv[5]' "$function_path" "$pane_id" "$cwd" "$started_at" "$fallback_title"
            end
        end

        set -l session_file (tmux show-option -pqv -t "$pane_id" @ai_codex_session_file 2>/dev/null)
        set -l pane_title (tmux display-message -p -t "$pane_id" '#{pane_title}' 2>/dev/null)
        set -l pane_session_id (__ai_pane_title_sync_codex_session_id_from_title "$pane_title")
        if test -n "$session_file"
            if not test -f "$session_file"
                set session_file ""
            else if test -n "$pane_session_id"
                set -l cached_session_id (__ai_pane_title_sync_codex_session_id_from_file "$session_file")
                if test "$cached_session_id" != "$pane_session_id"
                    set session_file ""
                    tmux set-option -p -t "$pane_id" @ai_codex_session_file "" 2>/dev/null
                end
            end
        end
        if test -z "$session_file"; and test -n "$pane_session_id"
            set session_file (__ai_pane_title_sync_codex_session_file_by_id "$pane_session_id")
            test -n "$session_file"; and tmux set-option -p -t "$pane_id" @ai_codex_session_file "$session_file" 2>/dev/null
        end
        if test -z "$session_file"
            set session_file (__ai_pane_title_sync_codex_find_session_file "$cwd" "$started_at")
            test -n "$session_file"; and tmux set-option -p -t "$pane_id" @ai_codex_session_file "$session_file" 2>/dev/null
        end

        if test -n "$session_file"
            set -l goal_title (__ai_pane_title_sync_codex_goal_title "$session_file")
            set -l title "$goal_title"
            set -l source codex-goal
            if test -z "$title"
                set title (__ai_pane_title_sync_codex_thread_title "$session_file")
                set source codex-thread
            end
            set -l current_base_title (tmux show-option -pqv -t "$pane_id" @ai_base_title 2>/dev/null)
            set -l current_source (tmux show-option -pqv -t "$pane_id" @ai_title_source 2>/dev/null)
            if test -n "$title"; and string match -q '\[tmux-bridge *' -- "$title"
                if string match -q '\[tmux-bridge *' -- "$current_base_title"
                    tmux set-option -p -t "$pane_id" @ai_base_title "" 2>/dev/null
                    tmux set-option -p -t "$pane_id" @ai_title_source "" 2>/dev/null
                    tmux set-option -p -t "$pane_id" @ai_title_updated_at (date +%s) 2>/dev/null
                end
            else if test -n "$title"; and begin
                    test "$title" != "$last_title"
                    or test "$current_base_title" != "$title"
                    or test "$current_source" != "$source"
                end
                __ai_pane_title_sync_set_base "$pane_id" "$title" "$source"
                set last_title "$title"
            end
        end

        sleep 2
    end
end

# claude 側の watcher 関数群は廃止。Claude Code 本体の SessionStart hook
# (base-repo の `home/scripts/claude/sidepane-session-start.sh`) が pane option
# (@ai_claude_session_id / @ai_claude_cwd / @ai_claude_started_at) を直接書く。
# sidebar renderer は session_id + cwd から jsonl path を決定論的に組み立て、
# slug 等は renderer 内で読み出すため、ここでは watcher process / slug 取得関数も
# 不要になった。codex 側は SessionStart hook 未対応のため当面 watcher 維持。

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
        case codex-watch
            __ai_pane_title_sync_codex_watch "$pane_id" "$argv[3]" "$argv[4]" "$argv[5]"
        case '*'
            echo "__ai_pane_title_sync: unknown command '$command'" >&2
            return 1
    end
end
