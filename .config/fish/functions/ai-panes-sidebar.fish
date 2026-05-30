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

    set -l plan_event (command jq -c '
        select(
            (.type == "response_item" and .payload.type == "function_call" and .payload.name == "update_plan")
            or (.name == "update_plan")
        )
        | if .name == "update_plan" then
            .
          else
            {payload: {arguments: .payload.arguments}}
          end
    ' "$session_file" 2>/dev/null | command tail -n 1)
    test -n "$plan_event"; or return 1

    set -l goal_line (printf '%s\n' "$plan_event" | command jq -r '
        (.payload.arguments | fromjson? | .explanation // "")
        | select(. != "")
    ' 2>/dev/null)
    set -l native_goal_status (__ai_codex_native_goal_status "$session_file")

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
          ) as $maybe_active_index
        | (if $maybe_active_index == null then (($groups | length) - 1) else $maybe_active_index end) as $active_index
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
    # explanation は task-progress-async.md の規約上 `Goal:` / `目標:` で始まる形で
    # 書かれる前提。この形で始まる時だけ上位目標として Goal 行に描画する。
    # 「Goal は作らず、この発話の短期ゴールとして…します」のような地の文 explanation は
    # 規約を満たさないため Goal 行に昇格させない (昇格させると `Goal: Goal は作らず…` の
    # ように二重化し意味不明になる)。
    if test -n "$goal_line"; and string match -qr '^\s*(Goal|目標):' -- "$goal_line"
        set -l goal_color (set_color yellow)
        if test -n "$native_goal_status"
            set goal_color (set_color --bold cyan)
        end
        set -l goal_reset (set_color normal)
        set -l shortened_goal (string shorten -m $max_line_chars -- "$goal_line")
        printf '%s%s%s\n' "$goal_color" "$shortened_goal" "$goal_reset"
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
                if test "$item_status" = completed
                    set marker '✓'
                else if test "$is_active" = true
                    set marker '>'
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

# cwd を Claude Code 内部の projects/ ディレクトリ名規約に変換する。
# 規約: 英数字とハイフン以外の全文字を `-` に置換する。
# 例: `/Users/u1@u-kt.com/My Drive/foo` →
#     `-Users-u1-u-kt-com-My-Drive-foo`
# (`/`, `@`, `.`, space すべて `-` に変換、連続 `-` は merge しない)。
function __ai_encode_cwd --argument-names cwd
    test -n "$cwd"; or return 1
    printf '%s\n' (string replace -ar '[^a-zA-Z0-9-]' '-' -- "$cwd")
end

# Claude session_id + cwd から `~/.claude/projects/<encoded>/<session_id>.jsonl`
# を決定論的に組み立てる。session_id 不明 / 形式異常なら空を返す。
function __ai_claude_session_path --argument-names cwd session_id
    test -n "$cwd"; or return 1
    test -n "$session_id"; or return 1
    # UUID 形式 (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) で受ける軽い sanity check
    string match -qr '^[0-9a-f-]+$' -- "$session_id"; or return 1
    set -l encoded (__ai_encode_cwd "$cwd")
    test -n "$encoded"; or return 1
    printf '%s/.claude/projects/%s/%s.jsonl\n' "$HOME" "$encoded" "$session_id"
end

# Codex session_id から `~/.codex/sessions/.../rollout-*-<session_id>.jsonl` を解決する。
# Codex 側の jsonl path は `rollout-YYYY-MM-DDTHH-MM-SS-<uuid>.jsonl` 命名で、
# 上位 directory が日付別 (`~/.codex/sessions/YYYY/MM/DD/`) のため、Claude と違い
# session_id だけでは合成できない。当面は find による検索を行う。
# 将来 Codex 側に SessionStart hook を追加して `transcript_path` を直接 pane option
# に書く設計に切り替えたら、この関数は不要になる (= 直接 pane option から取れる)。
function __ai_codex_session_path --argument-names session_id
    test -n "$session_id"; or return 1
    string match -qr '^[0-9a-f-]+$' -- "$session_id"; or return 1
    set -l sessions_dir "$HOME/.codex/sessions"
    test -d "$sessions_dir"; or return 1
    command find "$sessions_dir" -type f -name "rollout-*-$session_id.jsonl" -mtime -7 2>/dev/null | command head -n 1
end

function __ai_codex_session_id_from_file --argument-names session_file
    test -f "$session_file"; or return 1

    set -l session_id
    if command -q jq
        set session_id (command head -n 1 "$session_file" | command jq -r 'select(.type == "session_meta") | .payload.id // empty' 2>/dev/null)
    end
    if test -z "$session_id"
        set -l name (basename "$session_file")
        set -l match (string match -r '^rollout-.*-([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.jsonl$' -- "$name")
        if test (count $match) -ge 2
            set session_id "$match[2]"
        end
    end

    string match -qr '^[0-9a-f-]+$' -- "$session_id"; and printf '%s\n' "$session_id"
end

function __ai_codex_native_goal_status --argument-names session_file
    command -q sqlite3; or return 1
    set -l session_id (__ai_codex_session_id_from_file "$session_file")
    test -n "$session_id"; or return 1

    set -l db "$HOME/.codex/goals_1.sqlite"
    test -f "$db"; or return 1

    set -l escaped_id (string replace -a "'" "''" -- "$session_id")
    command sqlite3 "$db" "select status from thread_goals where thread_id = '$escaped_id' limit 1;" 2>/dev/null | command head -n 1
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
                  | (if $c.goal != "" then .goal = $c.goal else . end)
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
        # subject から `[#N系]` 親参照 prefix を strip する。Codex 側で `Task:` /
        # `SubTask:` prefix を strip しているのと同じ display layer 整形。
        # 親子関係は parentTaskId + ツリーインデントで表現されるため、subject 内の
        # 親参照テキストは renderer 段階で不可視にする。
        | def strip_claude_prefix:
            # 順番: `#N` / `#?` (先頭 ID prefix) → `[#N系]` (親参照) → 余白
            sub("^#[0-9?]+\\\\s+"; "")
            | sub("\\\\s*\\\\[#[0-9]+系\\\\]\\\\s*"; " ")
            | sub("^ +"; "")
            | sub(" +$"; "");
          (if $goal then ["goal\t" + ($goal | strip_claude_prefix)] else [] end)
          + (
              [$order[] | $tasks[.]]
              | map(select(.status != "deleted"))
              | . as $alive
              | (map(select((.parent | tostring) == "")) | map(.id)) as $root_ids
              | [
                  $root_ids[] as $rid
                  | ($alive[] | select(.id == $rid)) as $root
                  | ($alive | map(select((.parent | tostring) == $rid))) as $children
                  | "root\t" + $root.status + "\t" + $root.id + "\t" +
                    (($children | map(select(.status == "completed")) | length) | tostring) + "/" +
                    ($children | length | tostring) + "\t" + ($root.subject | strip_claude_prefix),
                    ($children[] | "child\t" + .status + "\t" + .id + "\t" + (.subject | strip_claude_prefix))
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
                set -l color_start ""
                set -l color_end ""
                switch "$item_status"
                    case completed
                        set marker '✓'
                    case in_progress
                        # pane list の working 表示 (▶ + 緑) と統一
                        set marker '▶'
                        set color_start (set_color green)
                        set color_end (set_color normal)
                end
                set -l shortened
                if test "$count" = "0/0"
                    set shortened (string shorten -m $max_line_chars -- (printf '%s %s' "$marker" "$subject"))
                else
                    set shortened (string shorten -m $max_line_chars -- (printf '%s %s %s' "$marker" "$count" "$subject"))
                end
                printf '%s%s%s\n' "$color_start" "$shortened" "$color_end"
            case child
                set -l item_status $parts[2]
                set -l subject $parts[4]
                set -l marker -
                set -l color_start ""
                set -l color_end ""
                switch "$item_status"
                    case completed
                        set marker '✓'
                    case in_progress
                        set marker '▶'
                        set color_start (set_color green)
                        set color_end (set_color normal)
                end
                set -l shortened (string shorten -m $max_line_chars -- (printf '  %s %s' "$marker" "$subject"))
                printf '%s%s%s\n' "$color_start" "$shortened" "$color_end"
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
    end
    # Permission prompt (Do you want to ... / Would you like to proceed?) は単独行
    # ではコマンドエコーで誤検知しやすいため、__ai_claude_visible_state 側で
    # 「question 行 + 直下 5 行以内に `❯ 1. ` 選択肢行」のペアでのみ waiting と判定する。
end

function __ai_claude_visible_state
    set -l detected_state
    set -l prompt_question_line_no 0
    set -l line_no 0
    while read -l line
        set line_no (math $line_no + 1)

        # 直接シグナル (AskUserQuestion footer 等、context 不要)。
        set -l line_state (__ai_claude_signal_line_state "$line")
        test -n "$line_state"; and set detected_state "$line_state"

        # Permission prompt / ExitPlanMode 承認の question 行を記憶する。
        if string match -q '*Do you want to proceed?*' -- "$line"
            set prompt_question_line_no $line_no
        else if string match -q '*Do you want to make this edit*' -- "$line"
            set prompt_question_line_no $line_no
        else if string match -q '*Do you want to allow*' -- "$line"
            set prompt_question_line_no $line_no
        else if string match -q '*Would you like to proceed?*' -- "$line"
            set prompt_question_line_no $line_no
        end

        # `❯ 1. ` で始まる選択肢行が、直前 5 行以内の question とペアになっていれば
        # 真の Permission prompt と判定する (コマンドエコーで question 文字列だけが
        # 出た状態は選択肢を伴わないので誤検知しない)。
        if string match -qr '^\s*❯\s+[0-9]+\.\s+' -- "$line"
            if test "$prompt_question_line_no" -gt 0; and test (math $line_no - $prompt_question_line_no) -le 5
                set detected_state waiting
            end
        end
    end

    test -n "$detected_state"; and printf '%s\n' "$detected_state"
end

function __ai_notify_clean_detail --argument-names line
    set line (string replace -ar '[[:cntrl:]]' '' -- "$line")
    set line (string replace -ar '^\s*[•●]\s*' '' -- "$line")
    set line (string replace -ar '^\s*❯\s*[0-9]+\.\s*' '' -- "$line")
    set line (string replace -ar '\s+' ' ' -- "$line")
    set line (string trim -- "$line")
    test -n "$line"; and string shorten -m 120 -- "$line"
end

function __ai_codex_notify_detail --argument-names state
    set -l detail
    set -l last_worked
    for line in $argv[2..-1]
        set -l clean (__ai_notify_clean_detail "$line")
        test -n "$clean"; or continue

        if test "$state" = waiting
            if string match -q '*Would you like to run the following command?*' -- "$clean"
                set detail "コマンド実行の承認待ち"
            else if string match -q '*Press enter to confirm or esc to cancel*' -- "$clean"
                set detail "確認入力待ち"
            else if string match -q '*Conversation interrupted - tell the model what to do differently*' -- "$clean"
                set detail "中断後の指示待ち"
            else if string match -q '*To continue this session, run codex resume*' -- "$clean"
                set detail "セッション再開待ち"
            else if string match -qr '(承認してください|承認をお願いします|実行してよいですか|OK.*返してください|どう進めますか|どうしますか|どちらにしますか|ご指示ください)' -- "$clean"
                set detail "$clean"
            end
        else if test "$state" = idle
            if string match -qr '^Worked for ' -- "$clean"
                set last_worked "$clean"
            end
        end
    end

    if test "$state" = idle; and test -n "$last_worked"
        set detail "処理完了 ($last_worked)"
    end
    test -n "$detail"; and printf '%s\n' "$detail"
end

function __ai_claude_notify_detail --argument-names state
    set -l detail
    set -l prev_non_empty
    set -l prompt_question
    set -l line_no 0
    set -l prompt_question_line_no 0
    for line in $argv[2..-1]
        set line_no (math $line_no + 1)
        set -l clean (__ai_notify_clean_detail "$line")
        test -n "$clean"; or continue

        if test "$state" = waiting
            if string match -q '*Enter to select*↑/↓ to navigate*Esc to cancel*' -- "$clean"
                test -n "$prev_non_empty"; and set detail "$prev_non_empty"
            else if string match -q '*Do you want to proceed?*' -- "$clean"
                set prompt_question "$clean"
                set prompt_question_line_no $line_no
            else if string match -q '*Do you want to make this edit*' -- "$clean"
                set prompt_question "$clean"
                set prompt_question_line_no $line_no
            else if string match -q '*Do you want to allow*' -- "$clean"
                set prompt_question "$clean"
                set prompt_question_line_no $line_no
            else if string match -q '*Would you like to proceed?*' -- "$clean"
                set prompt_question "$clean"
                set prompt_question_line_no $line_no
            else if string match -qr '^\s*❯\s+[0-9]+\.\s+' -- "$line"
                if test "$prompt_question_line_no" -gt 0; and test (math $line_no - $prompt_question_line_no) -le 5
                    set detail "$prompt_question"
                end
            end
        end

        set prev_non_empty "$clean"
    end

    if test "$state" = idle
        set detail "作業が完了し入力待ち"
    end
    test -n "$detail"; and printf '%s\n' "$detail"
end

function __ai_notify_detail --argument-names state app display
    set -l input_lines $argv[4..-1]

    set -l detail
    switch "$app"
        case codex
            set detail (__ai_codex_notify_detail "$state" $input_lines)
        case claude
            set detail (__ai_claude_notify_detail "$state" $input_lines)
    end

    if test -z "$detail"
        switch "$state"
            case waiting
                set detail "確認待ち"
            case idle
                set detail "作業完了"
        end
    end

    set -l clean_display (__ai_notify_clean_detail "$display")
    if test -n "$clean_display"; and test "$detail" != "$clean_display"
        printf '%s · %s\n' "$detail" "$clean_display"
    else
        printf '%s\n' "$detail"
    end
end

# 状態遷移時にデスクトップ通知を鳴らす (sidebar の状態判定を通知の唯一の源にする統合通知)。
#   - waiting への遷移 = 確認ウィンドウ / 質問プロンプトが出た → 「確認待ち」通知
#   - working → idle への遷移 = 処理が完全に完了した → 「完了」通知
#   - それ以外の遷移 (working 入り等) は無音
# 通知をクリックすると該当 session/window/pane に switch + Ghostty を前面化する (-execute)。
# 自分が今その pane を見ている (terminal 前面 + active pane + current window + attached)
# 時は鳴らさない (旧 notify.sh のフォーカス抑制を踏襲)。
function __ai_notify_title --argument-names app
    switch "$app"
        case codex
            printf '%s\n' "Codex CLI"
        case claude
            printf '%s\n' "Claude Code"
        case '*'
            printf '%s\n' "AI Console"
    end
end

function __ai_notify_state_change --argument-names pane_id new_state old_state display app detail
    command -q terminal-notifier; or return 0

    set -l message
    set -l sound
    switch "$new_state"
        case waiting
            set message "確認待ち · $detail"
            set sound Tink
        case idle
            # 完了は「作業中からの遷移」に限定する (idle↔idle / waiting→idle では鳴らさない)。
            test "$old_state" = working; or return 0
            set message "完了 · $detail"
            set sound Purr
        case '*'
            return 0
    end

    # フォーカス抑制: active pane + current window + attached かつ terminal が前面なら skip。
    set -l foc (tmux display-message -p -t "$pane_id" '#{pane_active},#{window_active},#{session_attached}' 2>/dev/null)
    set -l fp (string split ',' -- "$foc")
    if test (count $fp) -ge 3; and test "$fp[1]" = 1; and test "$fp[2]" = 1; and test "$fp[3]" != 0
        set -l front (osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null)
        switch "$front"
            case Ghostty ghostty Terminal iTerm2 Alacritty WezTerm kitty Hyper
                return 0
        end
    end

    # クリック時アクション: 該当 session/window/pane を選択し Ghostty を前面化する。
    # pane_id (%N) は server 全体で一意なので select-window/-pane の target に使える。
    set -l tmux_bin (command -v tmux)
    set -l sess (tmux display-message -p -t "$pane_id" '#{session_name}' 2>/dev/null)
    set -l exec_cmd "$tmux_bin switch-client -t '$sess'; $tmux_bin select-window -t '$pane_id'; $tmux_bin select-pane -t '$pane_id'; open -a Ghostty"

    set -l title (__ai_notify_title "$app")
    terminal-notifier -title "$title" -message "$message" -sound "$sound" \
        -group "ai-sidebar-$pane_id" -execute "$exec_cmd" 2>/dev/null &
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
    # v8 以降は writer 自身が state_version をファイルから読んで自己 re-exec する。
    # v18: 状態遷移 (working→idle / →waiting) で統合デスクトップ通知を発火。
    # v19: window 単位で group 化、`-- window_name --` ヘッダを各 group の先頭に挿入。
    # v20: header の printf を `%s` ベースに修正 (fish printf の `--` options-terminator 問題)。
    # v21: window header を `-- name --` から `■ name` 形式に変更。
    # v22: window header を左付け window_name のみ + クリックで select-window 対応 (entries に window_id を追加)。
    # v23: is_writer 判定 bug 修正 (同 session の 2 つ目以降の sidebar pane が self-check skip されていた)。
    # v24: Goal 表示を「最初の goal 固定」→「最新 goal で上書き」に変更 (goal 切替を反映)。
    # v25: 通知 message に確認待ち理由 / 完了 detail を含める。
    # v26: 通知 detail 抽出を stdin 非依存にし、writer loop の read 待ち停止を防ぐ。
    # v27: Codex plan の Goal 行を native goal 有無で色分けする。
    # v28: Codex plan の Goal 行を `Goal:` / `目標:` 始まりの explanation のみに限定 (地の文を昇格させない)。
    set -l state_version 28
    while true
        # ===== Section 1: 初期化 (loop 毎の状態リセット) =====
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
        set -l active_claude_session_id
        set -l active_claude_cwd
        set -l now_hm (date +%H:%M)
        set -l sidebar_window_id (tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)

        # ===== Section 2: tmux pane 一覧の取得 =====
        # tmux list-panes で全 pane の option を 1 回でまとめて取得する (毎 pane に
        # show-option を打つより速い)。format string の field 数を変えたら、下の
        # `string split -m N` (parts 配列の総数 - 1) も合わせて更新すること。
        set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}	#{pane_title}	#{@fixed_title}	#{@ai_base_title}	#{@ai_sidebar}	#{pane_current_path}	#{window_index}	#{@ai_display_index}	#{pane_current_command}	#{pane_id}	#{@ai_state}	#{@ai_state_since}	#{@ai_state_version}	#{pane_active}	#{window_id}	#{@ai_codex_started_at}	#{@ai_codex_session_file}	#{@ai_codex_cwd}	#{@ai_app}	#{@ai_claude_session_id}	#{@ai_claude_cwd}	#{window_name}' 2>/dev/null)
        # 自分自身の @ai_sidebar を見て writer 判定する。
        # 旧: session 内最初の writer だけ writer 認定 → 2 つ目以降の sidebar pane
        # (window 2, 3, ... の writer) が is_writer=0 のまま動き、state_version self-check
        # が走らず古いコードに固定される問題があった。
        set -l is_writer 0
        test (tmux show-options -p -t "$TMUX_PANE" -v @ai_sidebar 2>/dev/null) = "1"; and set is_writer 1

        # ===== Section 3: pane ごとの状態判定 + entries 構築 + active pane 識別 =====
        # 各 pane を iterate して以下を実施:
        #   - app 種別判定 (Codex / Claude / その他)
        #   - 状態判定 (working / waiting / idle, title + capture-pane から)
        #   - 状態遷移時刻 (@ai_state_since) の維持
        #   - entries 配列に行データを push (後段の Section 4 で sort/format)
        #   - sidebar と同じ window で active な Codex/Claude pane を active_* 変数に記録
        set -l entries
        for line in $raw
            set -l parts (string split -m 21 \t -- $line)
            set -l loc $parts[1]
            set -l title $parts[2]
            set -l fixed_title $parts[3]
            set -l base_title $parts[4]
            set -l is_sidebar $parts[5]
            set -l path $parts[6]
            set -l window_index $parts[7]
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
            set -l claude_session_id $parts[20]
            set -l claude_cwd $parts[21]
            set -l window_name $parts[22]

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

            set -l visible
            set -l codex_user_waiting 0
            set -l codex_working 0
            if test "$is_codex_console" = 1
                set visible (tmux capture-pane -p -J -t "$pane_id" 2>/dev/null | tail -24)
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
                set visible (tmux capture-pane -p -J -t "$pane_id" 2>/dev/null | tail -24)
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
            # state_since を now にすべき初観測 / 再観測ケースをまとめて判定する。
            #   1. cached_state が空 (この pane を初めて見る)
            #   2. cached_version が writer の state_version と不一致 (writer 再起動後の初観測)
            #   3. is_writer かつ pane が seen_panes に無い (writer ループ起動後に新規追加された pane)
            # いずれにも該当しない場合のみ、後段の「state 変化検知」で必要時に now にする。
            set -l needs_fresh_state 0
            if test -z "$cached_state"
                set needs_fresh_state 1
            else if test "$cached_version" != "$state_version"
                set needs_fresh_state 1
            else if test "$is_writer" = 1; and not contains -- "$pane_id" $seen_panes
                set needs_fresh_state 1
            end
            if test "$needs_fresh_state" = 1
                set display_state $detected_state
                set state_since "$now_hm"
            end
            # 既知 pane で state が変化した場合は now に更新
            if test "$needs_fresh_state" = 0; and test -n "$cached_state"; and test "$detected_state" != "$cached_state"
                set display_state $detected_state
                set state_since "$now_hm"
                # 状態判定を唯一の源にした統合通知 (writer かつ LLM console のみ)。
                # この分岐は writer 再起動直後の再観測 (needs_fresh_state=1) を含まないため、
                # 真の遷移エッジでのみ鳴る。
                if test "$is_writer" = 1; and test "$is_llm_console" = 1
                    set -l notify_app other
                    test "$is_codex_console" = 1; and set notify_app codex
                    test "$is_claude_console" = 1; and set notify_app claude
                    set -l notify_detail (__ai_notify_detail "$detected_state" "$notify_app" "$display" $visible)
                    __ai_notify_state_change "$pane_id" "$detected_state" "$cached_state" "$display" "$notify_app" "$notify_detail"
                end
            end
            # 最終 fallback (上記いずれにも該当しないが state_since が未設定なら "--:--")
            if test -z "$display_state"
                set display_state $detected_state
            end
            if test -z "$state_since"
                set state_since "--:--"
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
                set -a entries (printf 'waiting\t%s\t%s\t%s\tyellow\t%s\t%s\t%s\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id" "$window_index" "$window_name" "$window_id")
            else if test "$display_state" = working
                set -l row (printf '%s ▶ %s' "$state_since" "$display")
                set -a entries (printf 'working\t%s\t%s\t%s\tgreen\t%s\t%s\t%s\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id" "$window_index" "$window_name" "$window_id")
            else if test "$is_llm_console" = 1
                set -a entries (printf 'idle\t%s\t%s\t%s\tnormal\t%s\t%s\t%s\t%s\t%s' "$kind_sort_key" "$state_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id" "$window_index" "$window_name" "$window_id")
            else
                set -a entries (printf 'idle\t%s\t%s\t%s\tgray\t%s\t%s\t%s\t%s\t%s' "$kind_sort_key" "$state_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id" "$window_index" "$window_name" "$window_id")
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
                    # Claude Code が内部で sidechain / subagent session を発行した時にも
                    # SessionStart hook が呼ばれて pane option が上書きされうる。
                    # pane の cwd と option の cwd が一致する時のみ採用することで、
                    # 「別 project の sidechain が pane に書いた」ケースを skip する。
                    if test -n "$claude_cwd"; and test "$claude_cwd" = "$path"
                        set active_claude_session_id "$claude_session_id"
                        set active_claude_cwd "$claude_cwd"
                    end
                end
            end
        end

        # ===== Section 4: window 単位 group 化 + bucket sort + 行レンダリング =====
        # entries を window_index 昇順でグルーピングし、各 window の先頭に
        # `-- window_name --` ヘッダ (時間表示なし) を挿入する。
        # window 内では従来の bucket (working → waiting → idle) × state_since 順を維持。
        # 全角文字を含むタイトルでも sidebar 内で折り返さないよう pane 幅に合わせて切る。
        set -l pane_width (tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null)
        set -l pane_height (tmux display-message -p -t "$TMUX_PANE" '#{pane_height}' 2>/dev/null)
        set -l max_line_chars (__ai_sidebar_max_line_chars "$pane_width")
        set -l llm_bg_color 2a2a44

        # entries から window_index の昇順 unique 一覧を得る
        set -l window_keys
        for item in $entries
            set -l row_parts (string split -m 9 \t -- "$item")
            test (count $row_parts) -ge 8; or continue
            set -a window_keys $row_parts[8]
        end
        set window_keys (printf '%s\n' $window_keys | sort -un)

        for window_index in $window_keys
            # この window の entries だけ集め、window_name と window_id を 1 件目から拾う
            set -l window_entries
            set -l window_name_local
            set -l window_id_local
            for item in $entries
                set -l row_parts (string split -m 9 \t -- "$item")
                test (count $row_parts) -ge 10; or continue
                test "$row_parts[8]" = "$window_index"; or continue
                set -a window_entries $item
                if test -z "$window_name_local"
                    set window_name_local $row_parts[9]
                    set window_id_local $row_parts[10]
                end
            end
            test (count $window_entries) -gt 0; or continue

            # window header (左付け、時間表示なし、クリックで対象 window に切替)
            set -l header_text "$window_name_local"
            set -l header_short (string shorten -m $max_line_chars -- "$header_text")
            set -a lines (set_color --bold)$header_short(set_color normal)
            set -a line_texts "$header_short"
            set -a line_targets "$window_id_local"

            for bucket in working waiting idle
                for item in (printf '%s\n' $window_entries | sort -r)
                    set -l row_parts (string split -m 9 \t -- "$item")
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
        end

        # ===== Section 5: active Codex pane の plan tree 描画 =====
        # Codex は session_id を hook で受け取る経路がまだないため、
        # mtime + cwd ヒューリスティックの __ai_codex_find_session_file で jsonl を解決する。
        # 解決した jsonl path は @ai_codex_session_file に cache する (次回 loop で再利用)。
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
                # pane 高さの範囲内で全 plan を表示 (上限 cap 撤廃、Claude 側と整合)。
                set -l max_plan_lines (math "$pane_height - $existing_lines - 2")
                if test "$max_plan_lines" -lt 5
                    set max_plan_lines 5
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

        # ===== Section 6: active Claude pane の task tree 描画 =====
        # Claude は SessionStart hook (base-repo: sidepane-session-start.sh) が
        # @ai_claude_session_id + @ai_claude_cwd を pane option に直接書くため、
        # ここでは session_id + cwd から jsonl path を決定論的に組み立てるだけ
        # (旧版は mtime + cwd ヒューリスティックの watcher 経由で race していた)。
        if test -n "$active_claude_pane"; and test -n "$active_claude_session_id"; and test -n "$active_claude_cwd"
            set -l active_claude_session_file (__ai_claude_session_path "$active_claude_cwd" "$active_claude_session_id")
            if test -n "$active_claude_session_file"; and test -f "$active_claude_session_file"
                if not string match -qr '^[0-9]+$' -- "$pane_height"
                    set pane_height 30
                end
                set -l existing_lines (count $lines)
                # pane 高さの範囲内で全 task を表示 (上限 cap 撤廃)。
                set -l max_task_lines (math "$pane_height - $existing_lines - 2")
                if test "$max_task_lines" -lt 5
                    set max_task_lines 5
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
        end

        # ===== Section 7: click target 登録 (行クリックで pane 切替) =====
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

        # ===== Section 8: 差分検知 + 出力 =====
        # 直前の出力と比較し、変化があれば画面 clear + 再 print する (flicker 抑制)。
        set -l output (printf '%s\n' $lines)
        if test "$output" != "$last_output"
            printf '\033[2J\033[H'
            printf '%s\n' $lines
            set last_output "$output"
        end

        # ===== Section 9: state_version self-check で自己 re-exec =====
        # state_version self-check: ファイル上の state_version が bump されたら自己 re-exec。
        # tmux event (after-new-session 等) を待たずに編集を反映するための fallback。
        # ensure-ai-sidebars.sh が次に走った時 (新 window 等) には @ai_sidebar_version が
        # 更新され整合する。
        if test "$is_writer" = 1
            set -l file_version (command awk '/^[[:space:]]*set -l state_version[[:space:]]+[0-9]+/ {print $4; exit}' $HOME/.config/fish/functions/ai-panes-sidebar.fish 2>/dev/null)
            if test -n "$file_version"; and test "$file_version" != "$state_version"
                exec fish -c ai-panes-sidebar
            end
        end

        sleep 2
    end
end
