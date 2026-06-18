# tmux サイドペイン (ai-panes-sidebar) のデバッグ手順

IMPORTANT: 「サイドペインの表示がおかしい」「最新タスクが出ない」等の症状を訴え
られた時は、推測せず**実物を直接見る**手順から入る。本 rule の存在意義は、過去に
agent が `~/.claude/tasks/`・progress JSON・Claude Code バイナリ等を回り道して
迷走したのを防ぐこと。

## 仕組みの正確な認識 (推測しない)

サイドペインは tmux pane に fish の関数 `ai-panes-sidebar`
(`.config/fish/functions/ai-panes-sidebar.fish`) が 2 秒間隔で書き込んでいる。

- **writer pane の識別**: tmux option `@ai_sidebar=1` を持つ pane
- **Claude セッションの識別情報**: tmux pane option (`@ai_claude_session_id` /
  `@ai_claude_cwd` / `@ai_claude_started_at` / `@ai_app`)。これらは base-repo の
  Claude Code SessionStart hook (`home/scripts/claude/sidepane-session-start.sh`)
  が直接書き込み、SessionEnd hook が clear する
- **Claude セッションの task 表示データソース**: **transcript JSONL**
  (`~/.claude/projects/<encoded-cwd>/<session_id>.jsonl`)。session_id + cwd から
  決定論的に組み立てる (mtime + cwd ヒューリスティック探索は廃止済)
- **encoded-cwd の規約**: 英数字とハイフン以外 (`/`, `@`, `.`, space 等すべて) を
  `-` に置換。連続 `-` は merge しない
- **描画ロジック**: `__ai_claude_task_lines` 関数。transcript から `TaskCreate` /
  `TaskUpdate` / `tool_result` を `rg` / `grep` で抽出し、`jq` でリプレイ →
  goal + root Task + 直接 child (= SubTask) を整形
- **Codex 側は別経路**: Codex は SessionStart hook を未登録のため、
  `__ai_pane_title_sync codex-watch` が mtime + cwd ヒューリスティックで
  `~/.codex/sessions/.../rollout-*-<uuid>.jsonl` を探索する経路を維持する

### 使われていないもの (混同しない)

- ❌ `~/.claude/tasks/<session>/*.json` (Claude Code 内部状態。サイドペインは読まない)
- ❌ `~/.claude/progress-<session>.json` (statusline 用。サイドペインは読まない)
- ❌ Claude Code app バイナリの内部状態 (サイドペインに無関係)
- ❌ `@ai_claude_session_file` / `@ai_claude_watcher_pids` (旧 watcher 機構の遺物。
  2026-05-16 撤廃済み。新コードからは読まない)

## 切り分け Step (必ずこの順)

### Step 1: 実際の表示内容を直接読む

`tmux capture-pane -p -t <writer_pane>` で writer pane の現在内容が読める。
SSH 環境でも screenshot 不要。

```bash
# 全 writer pane を列挙
tmux list-panes -a -F '#{pane_id}\t#{@ai_sidebar}\t#{window_index}' \
  | awk -F'\t' '$2 == "1"'

# 各 writer pane の表示を dump
for p in $(tmux list-panes -a -F '#{pane_id}\t#{@ai_sidebar}' \
           | awk -F'\t' '$2 == "1" {print $1}'); do
  echo "=== $p ==="
  tmux capture-pane -p -t "$p"
done
```

「キャッシュファイル = `~/.claude/tasks/` 等のディスク上 file」**ではない**。
writer pane の capture-pane 出力が "描画キャッシュ"。

### Step 2: pane option を確認 (session_id / cwd が正しいか)

```bash
# 該当 pane の Claude session option を dump
tmux show-option -pqv -t <pane_id> @ai_claude_session_id
tmux show-option -pqv -t <pane_id> @ai_claude_cwd
tmux show-option -pqv -t <pane_id> @ai_app
```

- `@ai_claude_session_id` が空 → SessionStart hook が走ってない可能性
  (claude を fish 関数経由で起動したか、hook が登録されてるか確認)
- `@ai_claude_cwd` が pane の `pane_current_path` と異なる → subagent / sidechain
  session が誤って書いた可能性 (hook の cwd mismatch skip が効いていれば起きない)

### Step 3: データソース (transcript) の状態を再構築

writer pane の表示と「あるべき表示」を比較するため、同じ jq reducer を直接実行。
reducer は `.config/fish/functions/ai-panes-sidebar.fish` の `__ai_claude_task_lines`
内にあるので、そこからコピーする (重複定義しない)。

該当セッションの transcript path 組み立て:

```
~/.claude/projects/<encoded-cwd>/<session_id>.jsonl
```

encoded-cwd は cwd の英数字とハイフン以外を `-` に置換した形式 (例:
`/Users/u1@example.com/My Drive/foo` →
`-Users-u1-example-com-My-Drive-foo`)。fish 関数では `__ai_encode_cwd` を使う。

### Step 4: 表示 vs 再構築の差分を見て切り分け

| 観察 | 解釈 |
|------|------|
| 表示と再構築が一致 | データの想定通り。「最新が出ない」と訴えられたら**ユーザーの認識のズレ**か、深い階層問題 |
| 表示が古い・再構築は最新 | writer の poll 遅延 or jq race failure (transcript 追記中の partial line) |
| 再構築自体が壊れている | jq reducer のバグ (型不一致 / フィルタ漏れ / 順序問題) |
| 表示が空、再構築は中身あり | writer ループの異常終了 or 出力切替時の clear screen |
| 一部しか表示されない | `max_task_lines` cap (pane height 依存)、または親子階層が深い (renderer は 1 段下のみ取る) |

## よくある罠 (推測駆動を避ける)

### 罠 1: 「キャッシュファイル」の誤解

ユーザーが「キャッシュファイル」と言った時、それは `~/.claude/tasks/` のような
disk file **ではない**ことが多い。tmux pane に書き出された描画結果のことを
指している可能性が高い。`tmux capture-pane` を最優先で試す。

### 罠 2: progress JSON を編集してもサイドペインは変わらない

progress JSON (statusline 用、claude-code-base-repository 側 hook が書く) と
サイドペインは別系統。サイドペインを直したい時、progress JSON / hook を触っても
効かない。

### 罠 3: jq の `==` は型厳密

過去の実例: `id` (string `"16"`) と `parent` (number `16`) を比較して全 child が
silent drop。比較時は `(.field | tostring)` で正規化されているか確認する。

### 罠 4: writer pane は fish autoload で旧版を memory に抱える

**前提（配置はコピー方式）**: この repo は symlink ではなく**コピー方式**
(`copy.conf` / `docs/architecture.md` §同期方式)。repo の
`.config/fish/functions/ai-panes-sidebar.fish` を編集しても、live writer が読むのは
コピー先 `$HOME/.config/fish/functions/ai-panes-sidebar.fish` であり、**再コピーするまで
何をしても反映されない**。self-version-check (下記) も `$HOME/.config/...` を読む。

`ai-panes-sidebar.fish` を編集しても、live writer pane は古いコードを実行し続ける。
反映には:

0. **先に `$HOME` へ再コピー**: `./install.sh fish`（または該当ファイルだけ `cp`）。
   このコピーを飛ばすと以降の step は全て無意味になる。
1. `state_version` 変数 (`set -l state_version <N>`, `ai-panes-sidebar` 関数内) を bump
2. `.config/tmux/ensure-ai-sidebars.sh` を実行 (writer pane を respawn)

または、step 0 + bump 後は writer 内蔵の self-version-check (v8 以降) が、コピー先ファイルの
`state_version` と memory 上の値の差を検知して自動 re-exec する。

### 罠 5: subagent / sidechain の hook が pane option を上書き

Claude Code は subagent / sidechain session を内部で発行する時にも SessionStart
hook を発火する。これらは親 pane の `$TMUX_PANE` を継承するため、メイン session の
pane option を一時的に上書きする race を起こしうる。

対策は 2 層で実装済み:

1. **hook 側 (sidepane-session-start.sh)**: stdin の `cwd` と pane の
   `pane_current_path` を比較して、不一致なら no-op で exit。subagent は通常
   別 cwd で動くので skip される
2. **renderer 側 (ai-panes-sidebar.fish)**: pane option の `@ai_claude_cwd` と
   pane の `pane_current_path` を比較して、一致しない時は task tree 描画を skip
   (option が誤って書かれた場合の最後の防護)

「task tree が一瞬出たり消えたりする」「pane option がチカチカ変わる」と訴え
られたら、まず hook 側の cwd skip が効いてるかを確認する。

### 罠 6: 親子階層は Goal/Task/SubTask の 3 レベル固定

renderer は root → 直接 child の 1 段下までしか描画しない。深い階層の task は
表示されない。詳細は claude-code-base-repository 側の
`home/rules/claude/task-progress.md` §4.3 参照。

「最新タスクが見えない」と言われたら、まず該当 task の `parentTaskId` を確認し、
**孫以下になっていないか** (= 3 階層 rule 違反になっていないか) を確認する。

## pane の working / idle / waiting 状態判定 (▶ / ■ / ?)

サイドバーの pane 一覧行頭マーカー (▶ working / ■ idle / ? waiting) は、task tree
とは別系統。各 pane の `capture-pane` 末尾を `__ai_claude_signal_line_state` /
`__ai_claude_visible_state` が解析し、caller (`ai-panes-sidebar.fish` の
`set -l detected_state` 周辺) で marker を決める。`@ai_state` pane option に最後の
判定結果が入るので、`tmux show-option -pqv -t <pane> @ai_state` で writer の判定を
直接確認できる。

### Claude の working 判定は capture-pane が唯一の源 (title を信じない)

IMPORTANT: Claude pane の title は **idle 中も background monitor が動いていれば
braille スピナーで animate し続ける**。よって「title が braille だから working」とは
判定できない (`tmux display-message -p -t <pane> '#{pane_title}'` で確認可)。Claude の
working/idle は footer/recap 行 (`capture-pane`) を唯一の源にする:

- **active turn (処理中)**: spinner 行 `✻ … (12m 38s · ↑ 34.3k tokens)` のように
  **括弧付き live elapsed**、または `esc to interrupt` → working。idle 完了行
  `Brewed for 23m 14s · …` は括弧が無いので区別できる。
- **background shell**: `N shell … still running` / `· N shell …·` が 1 本でも
  あれば working (run_in_background Bash 等の実作業)。
- **monitor**: sidebar 等の常駐分が走ることがあるため、
  `N monitor` が **2 本以上のときだけ** working。1 本だけなら idle。
- **sub-agent (Agent tool)**: footer の agent 進捗行
  `◯ <name> ... Nm Ns · ↓ Nk tokens` が 1 本でもあれば working。
  active turn の括弧付き elapsed が消えた後も agent が動き続ける状態を捕捉する。

caller の title-braille fallback (`^[⠀-⣿]` → working) は **Claude console では無効**
(`is_claude_console != 1` で gate)。Codex 等は従来どおり title で補う。

### 症状別の見方

- 「完了したのに ▶ のまま」→ footer の monitor 数を確認。常駐 1 本だけなら idle が
  正。▶ のままなら title-braille fallback が効いていないか (= live writer が旧版を
  抱えていないか、罠 4) を疑う。
- 「shell が動いてるのに ■」→ footer に `N shell still running` が出ているか確認。
  shell 検出漏れ。
- 「sub-agent が動いてるのに ■」→ capture-pane 末尾に `◯ ... · ↓` 行があるか確認。
  なければ pane height が小さく footer がスクロールアウトした可能性。
  あるのに ■ なら writer が旧版 (v51 以前) を抱えていないか確認 (罠 4)。

## 関連

- `.config/fish/functions/ai-panes-sidebar.fish` — writer 本体 + `__ai_claude_task_lines`
  + `__ai_claude_signal_line_state` / `__ai_claude_visible_state` (working/idle/waiting 判定)
- `.config/tmux/ensure-ai-sidebars.sh` — writer respawn
- claude-code-base-repository: `home/rules/claude/task-progress.md` §4.3 — Goal/Task/SubTask 3 階層制約
- claude-code-base-repository: `home/hooks/claude/statusline.sh` — statusline (別系統、混同しない)
