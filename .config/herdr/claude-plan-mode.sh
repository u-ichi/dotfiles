#!/usr/bin/env bash
# Claude Code の plan mode 突入 / 復帰時に model と effort を明示注入する。
#
# 背景: Claude Code の "opusplan" 設定は plan mode 突入時に model を自動で
# 上位へ切り替えるが、context 使用量が 200k を超えると切替が発動しない。
# session 途中で plan へ入る運用では resting model のまま plan に入ってしまう。
# また effort は session 全体で 1 値しか持てず、plan 中だけ下げる設定も存在しない。
#
# そのため model / effort を自動切替に任せず、herdr の `agent prompt` で
# slash command を直接注入して確定させる。slash command は Claude Code 側で
# local 処理されるため、API turn を消費しない。
#
# 使い方 (herdr の [[keys.command]] から呼ぶ):
#   claude-plan-mode.sh plan    → fable + effort high にして plan mode へ入る
#   claude-plan-mode.sh normal  → sonnet 枠 + effort max へ戻す

set -euo pipefail

mode="${1:-plan}"

case "$mode" in
  plan)
    # plan 用の model / effort (fable + high) は worker 側が決める。
    enter_plan=1
    ;;
  normal)
    # 通常作業用の model / effort (sonnet 枠 + max) は worker 側が決める。
    enter_plan=0
    ;;
  *)
    printf 'usage: claude-plan-mode.sh [plan|normal]\n' >&2
    exit 2
    ;;
esac

command -v herdr > /dev/null 2>&1 || exit 0
command -v jq > /dev/null 2>&1 || exit 0

# フォーカス中の pane を取得する。claude 以外を動かしている pane では何もしない
# (codex / grok の pane で誤爆すると、その agent へ無意味な入力が入るため)。
pane_json="$(herdr pane current 2> /dev/null)" || exit 0

pane_id="$(printf '%s' "$pane_json" | jq -r '.result.pane.pane_id // empty')"
pane_agent="$(printf '%s' "$pane_json" | jq -r '.result.pane.agent // empty')"

[[ -n "$pane_id" ]] || exit 0
[[ "$pane_agent" == "claude" ]] || exit 0

# model / effort を session 途中で変えると Claude Code が確認を挟む
# (Switch model? / Change effort level?)。累積 output tokens が 0 でない限り必ず出る。
# 以前はここで固定 0.5 秒待って enter を送っていたが、選択肢が出るまでの実際の間隔と
# 無関係な待ちだったため一度も確定できず、選択肢が出たまま止まっていた。
#
# 注入と確定は claude-code-base-repository 側の worker へ委ねる。worker は herdr の
# 状態遷移 (blocked = 承認待ち) を待ってから enter を送る。state ファイルの記録と
# /plan の注入も worker が行う (パス規約を補正側と揃えるため)。
worker="$HOME/.claude/scripts/plan-effort-apply.sh"
[[ -x "$worker" ]] || exit 0

worker_args=("$pane_id" "$mode")
if [[ "$enter_plan" -eq 1 ]]; then
  worker_args+=("enter-plan")
fi

# キーバインドのハンドラを塞がないよう切り離して起動する。
nohup "$worker" "${worker_args[@]}" > /dev/null 2>&1 &
disown 2> /dev/null || true
