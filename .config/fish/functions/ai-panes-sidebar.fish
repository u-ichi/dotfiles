function __ai_codex_session_start_epoch --argument-names file
    set -l name (basename "$file")
    set -l match (string match -r '^rollout-([0-9]{4}-[0-9]{2}-[0-9]{2})T([0-9]{2})-([0-9]{2})-([0-9]{2})-' -- "$name")
    test (count $match) -ge 5; or return 1

    set -l stamp (printf '%sT%s-%s-%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]")
    command date -j -f '%Y-%m-%dT%H-%M-%S' "$stamp" +%s 2>/dev/null; or command date -d (printf '%s %s:%s:%s' "$match[2]" "$match[3]" "$match[4]" "$match[5]") +%s 2>/dev/null
end

function __ai_codex_session_matches_started_at --argument-names file started_at
    string match -qr '^[0-9]+$' -- "$started_at"; or return 1

    set -l session_started (__ai_codex_session_start_epoch "$file")
    string match -qr '^[0-9]+$' -- "$session_started"; or return 1

    set -l delta (math "$session_started - $started_at")
    test "$delta" -ge -5; and test "$delta" -le 600
end

function __ai_codex_find_session_file --argument-names cwd started_at
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

        set -l session_started (__ai_codex_session_start_epoch "$file")
        string match -qr '^[0-9]+$' -- "$session_started"; or continue
        set -l delta (math "$session_started - $started_at")
        if test "$delta" -ge -5; and test "$delta" -le 600; and test "$delta" -lt "$best_delta"
            set best_delta "$delta"
            set best_file "$file"
        end
    end

    test -n "$best_file"; and printf '%s\n' "$best_file"
end

function __ai_codex_plan_lines --argument-names session_file max_line_chars max_display_lines
    if not command -q jq
        return 1
    end
    test -f "$session_file"; or return 1
    if not string match -qr '^[0-9]+$' -- "$max_display_lines"
        set max_display_lines 20
    end
    if test "$max_display_lines" -lt 1
        set max_display_lines 1
    end

    set -l plan_event
    if command -q rg
        set plan_event (command rg '"name":"update_plan"' "$session_file" | command tail -n 1)
    else
        set plan_event (command grep '"name":"update_plan"' "$session_file" | command tail -n 1)
    end
    test -n "$plan_event"; or return 1

    set -l goal_line (printf '%s\n' "$plan_event" | command jq -r '
        (.payload.arguments | fromjson? | .explanation // "")
        | select(. != "")
    ' 2>/dev/null)

    set -l plan_rows (printf '%s\n' "$plan_event" | command jq -r '
        (.payload.arguments | fromjson? | .plan // [])
        | to_entries[]
        | "\(.key + 1)\t\(.value.status)\t\(.value.step)"
    ' 2>/dev/null)
    set -l total (count $plan_rows)
    test "$total" -gt 0; or return 1

    set -l display_rows (printf '%s\n' "$plan_event" | command jq -r '
        def strip_prefix: sub("^(Task|SubTask):\\\\s*"; "");
        (.payload.arguments | fromjson? | .plan // []) as $plan
        | reduce $plan[] as $item ({groups: []};
            ($item.step // "") as $step
            | if ($step | test("^Task:\\\\s*")) then
                .groups += [{
                    title: ($step | strip_prefix),
                    status: ($item.status // "pending"),
                    rows: []
                }]
              elif (.groups | length) == 0 then
                .groups += [{
                    title: ($step | strip_prefix),
                    status: ($item.status // "pending"),
                    rows: []
                }]
              else
                .groups[-1].rows += [$item]
              end
          )
        | .groups as $groups
        | (
            ($groups | to_entries | map(select((.value.status == "in_progress") or any(.value.rows[]?; .status == "in_progress"))) | .[0].key)
          ) as $active_index
        | $groups
        | to_entries[]
        | .key as $group_index
        | .value as $group
        | $group.rows as $rows
        | (if ($rows | length) > 0 then
            ($rows | map(select(.status == "completed")) | length)
          elif $group.status == "completed" then 1
          else 0
          end) as $completed
        | (if ($rows | length) > 0 then ($rows | length) else 1 end) as $total
        | ($group_index == $active_index) as $active
        | "task\t\($active)\t\($group.status // "pending")\t\($completed)\t\($total)\t\($rows | length)\t\($group.title)"
        , (if $active then
            ($rows[] | "row\t\(.status // "pending")\t\((.step // "") | strip_prefix)")
          else empty end)
    ' 2>/dev/null)
    test (count $display_rows) -gt 0; or return 1

    set -l remaining "$max_display_lines"
    if test -n "$goal_line"
        if string match -qr '^\s*(Goal|目標):' -- "$goal_line"
            printf '%s\n' (string shorten -m $max_line_chars -- "$goal_line")
        else
            printf '%s\n' (string shorten -m $max_line_chars -- (printf 'Goal: %s' "$goal_line"))
        end
        set remaining (math "$remaining - 1")
    end

    set -l processed 0
    set -l total_display_rows (count $display_rows)
    for display_row in $display_rows
        if test "$remaining" -le 0
            break
        end
        if test "$remaining" -eq 1; and test "$processed" -lt "$total_display_rows"
            printf '%s\n' (string shorten -m $max_line_chars -- '...')
            set remaining 0
            break
        end

        set -l parts (string split -m 6 \t -- "$display_row")
        switch "$parts[1]"
            case task
                set -l is_active $parts[2]
                set -l item_status $parts[3]
                set -l completed $parts[4]
                set -l total $parts[5]
                set -l row_count $parts[6]
                set -l title $parts[7]
                set -l marker -
                if test "$is_active" = true
                    set marker '>'
                else if test "$item_status" = completed
                    set marker '✓'
                end

                if test "$row_count" -gt 0
                    printf '%s\n' (string shorten -m $max_line_chars -- (printf '%s %s/%s %s' "$marker" "$completed" "$total" "$title"))
                else
                    printf '%s\n' (string shorten -m $max_line_chars -- (printf '%s %s' "$marker" "$title"))
                end
            case row
                set -l row_parts (string split -m 2 \t -- "$display_row")
                set -l item_status $row_parts[2]
                set -l marker -
                switch "$item_status"
                    case completed
                        set marker '✓'
                    case in_progress
                        set marker '>'
                end

                printf '%s\n' (string shorten -m $max_line_chars -- (printf '  %s %s' "$marker" "$row_parts[3]"))
        end
        set processed (math "$processed + 1")
        set remaining (math "$remaining - 1")
    end
end

function __ai_claude_task_lines --argument-names session_file max_line_chars max_display_lines
    if not command -q jq
        return 1
    end
    test -f "$session_file"; or return 1
    if not string match -qr '^[0-9]+$' -- "$max_display_lines"
        set max_display_lines 20
    end
    if test "$max_display_lines" -lt 1
        set max_display_lines 1
    end

    # task 関連 event だけ抽出する (TaskCreate / TaskUpdate の tool_use と TaskCreate の tool_result)。
    # session JSONL は MB 単位なので、まず ripgrep / grep で対象行を絞る。
    set -l events
    if command -q rg
        set events (command rg '"name":"TaskCreate"|"name":"TaskUpdate"|"toolUseResult":\{"task"' "$session_file")
    else
        set events (command grep -E '"name":"TaskCreate"|"name":"TaskUpdate"|"toolUseResult":\{"task"' "$session_file")
    end
    test (count $events) -gt 0; or return 1

    set -l rendered (printf '%s\n' $events | command jq -rs '
        [
          .[]
          | (
              ((.message.content // []) | (if (type) == "array" then . else [] end))[]?
              | select(.type == "tool_use" and (.name == "TaskCreate" or .name == "TaskUpdate"))
              | if .name == "TaskCreate" then
                  {kind: "create_use", tuid: .id, subject: .input.subject,
                   parent: ((.input.metadata // {}).parentTaskId // ""),
                   goal: ((.input.metadata // {}).goal // "")}
                else
                  {kind: "update", tid: (.input.taskId // ""),
                   subject: (.input.subject // null),
                   status: (.input.status // null),
                   parent: ((.input.metadata // {}).parentTaskId // null)}
                end
            ),
            (
              select(.toolUseResult.task.id != null)
              | {kind: "create_result",
                 tuid: ((.message.content // [])[]? | select(.type == "tool_result") | .tool_use_id),
                 tid: .toolUseResult.task.id}
            )
        ]
        | reduce .[] as $e (
            {creates: {}, tasks: {}, order: [], goal: null};
            if $e.kind == "create_use" then
              .creates[$e.tuid] = {subject: $e.subject, parent: $e.parent, goal: $e.goal}
            elif $e.kind == "create_result" then
              (.creates[$e.tuid] // null) as $c
              | if $c then
                  .tasks[$e.tid] = {id: $e.tid, subject: $c.subject, parent: $c.parent, status: "pending"}
                  | .order += [$e.tid]
                  | (if .goal == null and $c.goal != "" then .goal = $c.goal else . end)
                  | del(.creates[$e.tuid])
                else . end
            elif $e.kind == "update" then
              ($e.tid) as $tid
              | (.tasks[$tid] // null) as $t
              | if $t then
                  (if $e.subject  then .tasks[$tid].subject = $e.subject  else . end)
                  | (if $e.status then .tasks[$tid].status = $e.status else . end)
                  | (if $e.parent != null then .tasks[$tid].parent = $e.parent else . end)
                else . end
            else . end
          )
        | .order as $order | .tasks as $tasks | .goal as $goal
        | (if $goal then ["goal\t" + $goal] else [] end)
          + (
              [$order[] | $tasks[.]]
              | map(select(.status != "deleted"))
              | . as $alive
              | (map(select(.parent == "")) | map(.id)) as $root_ids
              | [
                  $root_ids[] as $rid
                  | ($alive[] | select(.id == $rid)) as $root
                  | ($alive | map(select(.parent == $rid))) as $children
                  | "root\t" + $root.status + "\t" + $root.id + "\t" +
                    (($children | map(select(.status == "completed")) | length) | tostring) + "/" +
                    ($children | length | tostring) + "\t" + $root.subject,
                    ($children[] | "child\t" + .status + "\t" + .id + "\t" + .subject)
                ]
            )
        | .[]
    ' 2>/dev/null)
    test (count $rendered) -gt 0; or return 1

    set -l remaining "$max_display_lines"
    set -l total_rendered (count $rendered)
    set -l processed 0
    for line in $rendered
        if test "$remaining" -le 0
            break
        end
        if test "$remaining" -eq 1; and test "$processed" -lt (math "$total_rendered - 1")
            printf '%s\n' (string shorten -m $max_line_chars -- '...')
            set remaining 0
            break
        end

        set -l parts (string split -m 4 \t -- "$line")
        switch "$parts[1]"
            case goal
                printf '%s\n' (string shorten -m $max_line_chars -- (printf 'Goal: %s' "$parts[2]"))
            case root
                set -l item_status $parts[2]
                set -l count $parts[4]
                set -l subject $parts[5]
                set -l marker -
                switch "$item_status"
                    case completed
                        set marker '✓'
                    case in_progress
                        set marker '>'
                end
                if test "$count" = "0/0"
                    printf '%s\n' (string shorten -m $max_line_chars -- (printf '%s %s' "$marker" "$subject"))
                else
                    printf '%s\n' (string shorten -m $max_line_chars -- (printf '%s %s %s' "$marker" "$count" "$subject"))
                end
            case child
                set -l item_status $parts[2]
                set -l subject $parts[4]
                set -l marker -
                switch "$item_status"
                    case completed
                        set marker '✓'
                    case in_progress
                        set marker '>'
                end
                printf '%s\n' (string shorten -m $max_line_chars -- (printf '  %s %s' "$marker" "$subject"))
        end
        set processed (math "$processed + 1")
        set remaining (math "$remaining - 1")
    end
end

function __ai_sidebar_max_line_chars --argument-names pane_width
    if not string match -qr '^[0-9]+$' -- "$pane_width"
        set pane_width 26
    end

    set -l max_line_chars (math "$pane_width - 1")
    if test "$max_line_chars" -lt 1
        set max_line_chars 1
    end
    printf '%s\n' "$max_line_chars"
end

function __ai_codex_signal_line_state --argument-names line
    if string match -qr '^\s*(diff --git|index |--- |\+\+\+ |@@|[+-])' -- "$line"
        return 1
    end

    if string match -q '*Working (*' -- "$line"
        printf '%s\n' working
    else if string match -q '*Booting MCP server:*esc to interrupt*' -- "$line"
        printf '%s\n' working
    else if string match -q '*Waiting for background terminal*' -- "$line"
        printf '%s\n' working
    else if string match -q '*background terminal running*' -- "$line"
        printf '%s\n' working
    else if string match -q '*Press enter to confirm or esc to cancel*' -- "$line"
        printf '%s\n' waiting
    else if string match -q '*Would you like to run the following command?*' -- "$line"
        printf '%s\n' waiting
    else if string match -qr '(Yes, proceed \(y\)|No, and tell Codex what to do differently)' -- "$line"
        printf '%s\n' waiting
    else if string match -q '*Conversation interrupted - tell the model what to do differently*' -- "$line"
        printf '%s\n' waiting
    else if string match -q '*To continue this session, run codex resume*' -- "$line"
        printf '%s\n' waiting
    else if string match -qr '(承認してください|承認をお願いします|実行してよいですか|OK.*返してください|どう進めますか|どうしますか|どちらにしますか|ご指示ください)' -- "$line"
        printf '%s\n' waiting
    else if string match -qr '^\s*[•●] Worked for ' -- "$line"
        printf '%s\n' idle
    else if string match -qr '^\s*›' -- "$line"
        printf '%s\n' idle
    end
end

function __ai_codex_visible_state
    set -l detected_state
    while read -l line
        set -l line_state (__ai_codex_signal_line_state "$line")
        if test "$line_state" = idle; and string match -qr '^\s*›' -- "$line"; and test -n "$detected_state"
            continue
        end
        test -n "$line_state"; and set detected_state "$line_state"
    end

    test -n "$detected_state"; and printf '%s\n' "$detected_state"
end

function __ai_claude_signal_line_state --argument-names line
    # diff 出力行を誤検知シグナルから除外する
    if string match -qr '^\s*(diff --git|index |--- |\+\+\+ |@@|[+-])' -- "$line"
        return 1
    end

    # AskUserQuestion (Submit プロンプト) の footer。
    # `Enter to select · ↑/↓ to navigate · Esc to cancel` が同行に並ぶのは
    # この prompt の固有 footer なので、応答待ちのシグナルとして拾う。
    # `↑/↓ to navigate` を必須条件にしているのは、agent 自身が Bash 等で
    # `Enter to select` / `Esc to cancel` をキーワード文字列として入力した時、
    # Claude Code TUI のコマンドエコーで capture-pane に出てしまい
    # 誤検知するのを防ぐため (難読 char を含む `↑/↓ to navigate` は通常の
    # コマンドや出力に出てこない)。
    if string match -q '*Enter to select*↑/↓ to navigate*Esc to cancel*' -- "$line"
        printf '%s\n' waiting
        # Permission prompt (Bash / Edit 等の Yes/No 確認)
    else if string match -q '*Do you want to proceed?*' -- "$line"
        printf '%s\n' waiting
    else if string match -q '*Do you want to make this edit*' -- "$line"
        printf '%s\n' waiting
    else if string match -q '*Do you want to allow*' -- "$line"
        printf '%s\n' waiting
        # ExitPlanMode の承認 prompt
    else if string match -q '*Would you like to proceed?*' -- "$line"
        printf '%s\n' waiting
    end
end

function __ai_claude_visible_state
    set -l detected_state
    while read -l line
        set -l line_state (__ai_claude_signal_line_state "$line")
        test -n "$line_state"; and set detected_state "$line_state"
    end

    test -n "$detected_state"; and printf '%s\n' "$detected_state"
end

function ai-panes-sidebar --description 'Show AI CLI panes in a tmux sidebar'
    if not set -q TMUX
        echo "ai-panes-sidebar: not inside tmux" >&2
        return 1
    end

    set -l last_output
    set -l last_target_count 0
    set -l seen_panes
    set -l has_loaded_once 0
    # NOTE: この state_version は ensure-ai-sidebars.sh / test-ai-sidebars-isolated.sh が
    # awk で読み取り、live sidebar pane の respawn 判定にも使う。
    # 関数のロジックを書き換えたら必ずこの数値を上げる (live writer pane は fish の
    # autoload で旧版を memory に抱え続けるため、bump → respawn でしか反映できない)。
    set -l state_version 5
    while true
        set -l lines
        set -l line_targets
        set -l line_texts
        set -l current_panes
        set -l active_codex_pane
        set -l active_codex_display
        set -l active_codex_path
        set -l active_codex_started_at
        set -l active_codex_session_file
        set -l active_claude_pane
        set -l active_claude_display
        set -l active_claude_session_file
        set -l now_hm (date +%H:%M)
        set -l sidebar_window_id (tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)
        set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}	#{pane_title}	#{@fixed_title}	#{@ai_base_title}	#{@ai_sidebar}	#{pane_current_path}	#{window_index}	#{@ai_display_index}	#{pane_current_command}	#{pane_id}	#{@ai_state}	#{@ai_state_since}	#{@ai_state_version}	#{pane_active}	#{window_id}	#{@ai_codex_started_at}	#{@ai_codex_session_file}	#{@ai_codex_cwd}	#{@ai_app}	#{@ai_claude_session_file}' 2>/dev/null)
        set -l writer_pane (tmux list-panes -s -F '#{pane_id}	#{@ai_sidebar}' 2>/dev/null | awk -F '\t' '$2 == "1" {print $1; exit}')
        set -l is_writer 0
        test "$TMUX_PANE" = "$writer_pane"; and set is_writer 1

        set -l entries
        for line in $raw
            set -l parts (string split -m 19 \t -- $line)
            set -l loc $parts[1]
            set -l title $parts[2]
            set -l fixed_title $parts[3]
            set -l base_title $parts[4]
            set -l is_sidebar $parts[5]
            set -l path $parts[6]
            set -l command_name (string lower -- $parts[9])
            set -l pane_id $parts[10]
            set -l cached_state $parts[11]
            set -l state_since $parts[12]
            set -l cached_version $parts[13]
            set -l pane_active $parts[14]
            set -l window_id $parts[15]
            set -l codex_started_at $parts[16]
            set -l codex_session_file $parts[17]
            set -l codex_cwd $parts[18]
            set -l ai_app $parts[19]
            set -l claude_session_file $parts[20]

            test "$loc" = (tmux display-message -p -t "$TMUX_PANE" '#{window_index}.#{pane_index}' 2>/dev/null); and continue
            test "$is_sidebar" = 1; and continue
            set -a current_panes "$pane_id"

            set -l display
            set -l is_codex_console 0
            if test "$ai_app" = codex
                set is_codex_console 1
            else if string match -q '*codex*' -- $command_name
                set is_codex_console 1
            else if string match -q '*Context *% used*' -- $title
                set is_codex_console 1
            end
            set -l is_claude_console 0
            if test "$ai_app" = claude
                set is_claude_console 1
            else if string match -q '*claude*' -- $command_name
                set is_claude_console 1
            end

            if test -n "$fixed_title"
                set display $fixed_title
            else if test -n "$base_title"
                set display $base_title
            else if test "$is_codex_console" = 1; and test "$title" = (basename "$path")
                set display (string replace "$HOME" "~" -- "$path")
            else
                set display $title
            end

            set -l codex_session_path "$path"
            test -n "$codex_cwd"; and set codex_session_path "$codex_cwd"

            set -l codex_user_waiting 0
            set -l codex_working 0
            if test "$is_codex_console" = 1
                set -l visible (tmux capture-pane -p -J -t "$pane_id" 2>/dev/null | tail -24)
                set -l codex_visible_state (printf '%s\n' $visible | __ai_codex_visible_state)
                if test "$codex_visible_state" = waiting
                    set codex_user_waiting 1
                else if test "$codex_visible_state" = working
                    set codex_working 1
                end
            end

            # Claude pane 側でも capture-pane で AskUserQuestion / Permission prompt を拾う。
            # title だけだと braille アニメ文字で working と誤判定されるため。
            set -l claude_user_waiting 0
            if test "$is_claude_console" = 1
                set -l visible (tmux capture-pane -p -J -t "$pane_id" 2>/dev/null | tail -24)
                set -l claude_visible_state (printf '%s\n' $visible | __ai_claude_visible_state)
                if test "$claude_visible_state" = waiting
                    set claude_user_waiting 1
                end
            end

            set -l is_llm_console 0
            if test "$is_codex_console" = 1
                set is_llm_console 1
            else if test "$is_claude_console" = 1
                set is_llm_console 1
            end
            set -l console_kind other
            test "$is_llm_console" = 1; and set console_kind llm

            set -l detected_state idle
            if test "$codex_user_waiting" = 1
                set detected_state waiting
            else if test "$claude_user_waiting" = 1
                # AskUserQuestion / Permission prompt 表示中は braille title より優先する
                set detected_state waiting
            else if string match -q '✳*' -- $title
                set detected_state waiting
            else if test "$codex_working" = 1
                set detected_state working
            else if string match -qr '^[⠀-⣿]' -- $title
                set detected_state working
            end

            set -l display_state $cached_state
            if test "$cached_version" != "$state_version"
                set display_state ""
                set state_since ""
            end
            if test -z "$display_state"
                set display_state $detected_state
            end
            if test -z "$state_since"
                set state_since "--:--"
            end
            if test "$is_writer" = 1; and test "$has_loaded_once" = 1; and not contains -- "$pane_id" $seen_panes
                set display_state $detected_state
                set state_since "$now_hm"
            end
            if test -n "$cached_state"; and test "$detected_state" != "$cached_state"
                set display_state $detected_state
                set state_since "$now_hm"
            end
            if test "$is_writer" = 1
                tmux set-option -p -t "$pane_id" @ai_state "$display_state" 2>/dev/null
                tmux set-option -p -t "$pane_id" @ai_state_since "$state_since" 2>/dev/null
                tmux set-option -p -t "$pane_id" @ai_state_version "$state_version" 2>/dev/null
            end

            set -l state_sort_key 0000
            if string match -qr '^[0-9][0-9]:[0-9][0-9]$' -- "$state_since"
                set state_sort_key (string replace ':' '' -- "$state_since")
            end
            set -l kind_sort_key 0
            test "$console_kind" = llm; and set kind_sort_key 1

            if test "$display_state" = waiting
                set -l row (printf '%s ? %s' "$state_since" "$display")
                set -a entries (printf 'waiting\t%s\t%s\t%s\tyellow\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id")
            else if test "$display_state" = working
                set -l row (printf '%s ▶ %s' "$state_since" "$display")
                set -a entries (printf 'working\t%s\t%s\t%s\tgreen\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id")
            else if test "$is_llm_console" = 1
                set -a entries (printf 'idle\t%s\t%s\t%s\tnormal\t%s\t%s' "$kind_sort_key" "$state_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id")
            else
                set -a entries (printf 'idle\t%s\t%s\t%s\tgray\t%s\t%s' "$kind_sort_key" "$state_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id")
            end

            if test "$window_id" = "$sidebar_window_id"; and test "$is_codex_console" = 1
                if test "$pane_active" = 1
                    set active_codex_pane "$pane_id"
                    set active_codex_display "$display"
                    set active_codex_path "$codex_session_path"
                    set active_codex_started_at "$codex_started_at"
                    set active_codex_session_file "$codex_session_file"
                end
            end
            if test "$window_id" = "$sidebar_window_id"; and test "$is_claude_console" = 1
                if test "$pane_active" = 1
                    set active_claude_pane "$pane_id"
                    set active_claude_display "$display"
                    set active_claude_session_file "$claude_session_file"
                end
            end
        end

        # 全角文字を含むタイトルでも sidebar 内で折り返さないよう pane 幅に合わせて切る。
        set -l pane_width (tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null)
        set -l pane_height (tmux display-message -p -t "$TMUX_PANE" '#{pane_height}' 2>/dev/null)
        set -l max_line_chars (__ai_sidebar_max_line_chars "$pane_width")
        set -l llm_bg_color 2a2a44
        for bucket in working waiting idle
            for item in (printf '%s\n' $entries | sort -r)
                set -l row_parts (string split -m 6 \t -- "$item")
                set -l row_bucket $row_parts[1]
                set -l row_kind $row_parts[4]
                set -l row_color $row_parts[5]
                set -l row_text $row_parts[6]
                set -l row_target $row_parts[7]
                test "$row_bucket" = "$bucket"; or continue

                set -l short_row (string shorten -m $max_line_chars -- "$row_text")
                # fish の cartesian 展開で `" "$color_prefix...` が 0 要素にならないよう、
                # 空でも 1 要素 (空文字) を保つ。
                set -l color_prefix ""
                if test "$row_kind" = llm
                    set color_prefix (set_color -b $llm_bg_color)
                end
                if test "$row_color" = yellow
                    set -a lines " "$color_prefix(set_color yellow)$short_row(set_color normal)
                else if test "$row_color" = green
                    set -a lines " "$color_prefix(set_color green)$short_row(set_color normal)
                else if test "$row_color" = gray
                    set -a lines " "(set_color 666666)$short_row(set_color normal)
                else
                    set -a lines " "$color_prefix$short_row(set_color normal)
                end
                set -a line_texts " "$short_row
                set -a line_targets "$row_target"
            end
        end

        if test -n "$active_codex_pane"
            set -l plan_session_file
            if string match -qr '^[0-9]+$' -- "$active_codex_started_at"
                set plan_session_file "$active_codex_session_file"
                if test -n "$plan_session_file"; and not __ai_codex_session_matches_started_at "$plan_session_file" "$active_codex_started_at"
                    set plan_session_file ""
                    test "$is_writer" = 1; and tmux set-option -p -t "$active_codex_pane" @ai_codex_session_file "" 2>/dev/null
                end
                if test -z "$plan_session_file"; or not test -f "$plan_session_file"
                    set plan_session_file (__ai_codex_find_session_file "$active_codex_path" "$active_codex_started_at")
                    if test -n "$plan_session_file"; and test "$is_writer" = 1
                        tmux set-option -p -t "$active_codex_pane" @ai_codex_session_file "$plan_session_file" 2>/dev/null
                    end
                end
            else
                test "$is_writer" = 1; and tmux set-option -p -t "$active_codex_pane" @ai_codex_session_file "" 2>/dev/null
            end

            set -l plan_lines
            if test -n "$plan_session_file"
                if not string match -qr '^[0-9]+$' -- "$pane_height"
                    set pane_height 30
                end
                set -l existing_lines (count $lines)
                set -l max_plan_lines (math "$pane_height - $existing_lines - 2")
                if test "$max_plan_lines" -lt 5
                    set max_plan_lines 5
                else if test "$max_plan_lines" -gt 24
                    set max_plan_lines 24
                end
                set plan_lines (__ai_codex_plan_lines "$plan_session_file" "$max_line_chars" "$max_plan_lines")
            end
            if test (count $plan_lines) -gt 0
                set -a lines ""
                set -a lines (string shorten -m $max_line_chars -- "$active_codex_display")
                for plan_line in $plan_lines
                    set -a lines " "$plan_line
                end
            end
        end

        # active Claude pane の TaskList を Codex plan tree と同じ枠で表示する。
        if test -n "$active_claude_pane"; and test -n "$active_claude_session_file"; and test -f "$active_claude_session_file"
            if not string match -qr '^[0-9]+$' -- "$pane_height"
                set pane_height 30
            end
            set -l existing_lines (count $lines)
            set -l max_task_lines (math "$pane_height - $existing_lines - 2")
            if test "$max_task_lines" -lt 5
                set max_task_lines 5
            else if test "$max_task_lines" -gt 24
                set max_task_lines 24
            end
            set -l task_lines (__ai_claude_task_lines "$active_claude_session_file" "$max_line_chars" "$max_task_lines")
            if test (count $task_lines) -gt 0
                set -a lines ""
                set -a lines (string shorten -m $max_line_chars -- "$active_claude_display")
                for task_line in $task_lines
                    set -a lines " "$task_line
                end
            end
        end

        set -l line_no 1
        set -l target_count (count $line_targets)
        if test "$target_count" -gt 0
            for i in (seq $target_count)
                set -l target $line_targets[$i]
                set -l line_text $line_texts[$i]
                tmux set-option -p -t "$TMUX_PANE" "@ai_click_target_$line_no" "$target" 2>/dev/null
                tmux set-option -p -t "$TMUX_PANE" "@ai_click_line_$line_no" "$line_text" 2>/dev/null
                set line_no (math $line_no + 1)
            end
        end
        while test "$line_no" -le "$last_target_count"
            tmux set-option -pu -t "$TMUX_PANE" "@ai_click_target_$line_no" 2>/dev/null
            tmux set-option -pu -t "$TMUX_PANE" "@ai_click_line_$line_no" 2>/dev/null
            set line_no (math $line_no + 1)
        end
        if test "$is_writer" = 1
            set seen_panes $current_panes
            set has_loaded_once 1
        end
        set last_target_count (count $line_targets)

        set -l output (printf '%s\n' $lines)
        if test "$output" != "$last_output"
            printf '\033[2J\033[H'
            printf '%s\n' $lines
            set last_output "$output"
        end

        sleep 2
    end
end
