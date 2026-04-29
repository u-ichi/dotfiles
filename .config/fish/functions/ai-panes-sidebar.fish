function ai-panes-sidebar --description 'Show AI CLI panes in a tmux sidebar'
    if not set -q TMUX
        echo "ai-panes-sidebar: not inside tmux" >&2
        return 1
    end

    set -l last_output
    set -l last_target_count 0
    set -l seen_panes
    set -l has_loaded_once 0
    set -l state_version 2
    while true
        set -l lines
        set -l line_targets
        set -l line_texts
        set -l current_panes
        set -l now_hm (date +%H:%M)
        set -l raw (tmux list-panes -s -F '#{window_index}.#{pane_index}	#{pane_title}	#{@fixed_title}	#{window_name}	#{@ai_sidebar}	#{pane_current_path}	#{window_index}	#{@ai_display_index}	#{pane_current_command}	#{pane_id}	#{@ai_state}	#{@ai_state_since}	#{@ai_state_version}' 2>/dev/null)
        set -l writer_pane (tmux list-panes -s -F '#{pane_id}	#{@ai_sidebar}' 2>/dev/null | awk -F '\t' '$2 == "1" {print $1; exit}')
        set -l is_writer 0
        test "$TMUX_PANE" = "$writer_pane"; and set is_writer 1

        set -l entries
        for line in $raw
            set -l parts (string split -m 12 \t -- $line)
            set -l loc $parts[1]
            set -l title $parts[2]
            set -l fixed_title $parts[3]
            set -l window_name (string lower -- $parts[4])
            set -l is_sidebar $parts[5]
            set -l path $parts[6]
            set -l command_name (string lower -- $parts[9])
            set -l pane_id $parts[10]
            set -l cached_state $parts[11]
            set -l state_since $parts[12]
            set -l cached_version $parts[13]

            test "$loc" = (tmux display-message -p -t "$TMUX_PANE" '#{window_index}.#{pane_index}' 2>/dev/null); and continue
            test "$is_sidebar" = 1; and continue
            set -a current_panes "$pane_id"

            set -l display
            set -l is_codex_console 0
            if string match -q '*codex*' -- $command_name
                set is_codex_console 1
            else if string match -q '*codex*' -- $window_name
                set is_codex_console 1
            else if string match -q '*Context *% used*' -- $title
                set is_codex_console 1
            end

            if test -n "$fixed_title"
                set display $fixed_title
            else if test "$is_codex_console" = 1; and test "$title" = (basename "$path")
                set display (string replace "$HOME" "~" -- "$path")
            else
                set display $title
            end

            set -l codex_approval_waiting 0
            set -l codex_working 0
            if test "$is_codex_console" = 1
                set -l visible (tmux capture-pane -p -J -t "$pane_id" 2>/dev/null | tail -8)
                if string match -q '*Press enter to confirm or esc to cancel*' -- $visible
                    set codex_approval_waiting 1
                else if string match -q '*Working (*' -- $visible
                    set codex_working 1
                else if string match -q '*background terminal running*' -- $visible
                    set codex_working 1
                end
            end

            set -l is_llm_console 0
            if test "$is_codex_console" = 1
                set is_llm_console 1
            else if string match -q '*claude*' -- $command_name
                set is_llm_console 1
            end
            set -l console_kind other
            test "$is_llm_console" = 1; and set console_kind llm

            set -l detected_state idle
            if test "$codex_approval_waiting" = 1
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
            if test "$is_writer" = 1; and test -n "$cached_state"; and test "$detected_state" != "$cached_state"
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
                set -l row (printf '%s ⏸ %s' "$state_since" "$display")
                set -a entries (printf 'waiting\t%s\t%s\t%s\tyellow\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id")
            else if test "$display_state" = working
                set -l row (printf '%s ▶ %s' "$state_since" "$display")
                set -a entries (printf 'working\t%s\t%s\t%s\tgreen\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" "$row" "$pane_id")
            else if test "$is_llm_console" = 1
                set -a entries (printf 'idle\t%s\t%s\t%s\tnormal\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id")
            else
                set -a entries (printf 'idle\t%s\t%s\t%s\tgray\t%s\t%s' "$state_sort_key" "$kind_sort_key" "$console_kind" (printf '%s ■ %s' "$state_since" "$display") "$pane_id")
            end
        end

        # 全角文字を含むタイトルでも sidebar 内で折り返さないよう pane 幅に合わせて切る。
        set -l pane_width (tmux display-message -p -t "$TMUX_PANE" '#{pane_width}' 2>/dev/null)
        if not string match -qr '^[0-9]+$' -- "$pane_width"
            set pane_width 26
        end
        set -l max_line_chars (math "max(20, $pane_width - 1)")
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
                set -l color_prefix
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
