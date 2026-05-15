# tmux サイドペイン (ai-panes-sidebar) のデバッグ手順

IMPORTANT: 「サイドペインの表示がおかしい」「最新タスクが出ない」等の症状を訴え
られた時は、推測せず**実物を直接見る**手順から入る。本 rule の存在意義は、過去に
agent が `~/.claude/tasks/`・progress JSON・Claude Code バイナリ等を回り道して
迷走したのを防ぐこと。

## 仕組みの正確な認識 (推測しない)

サイドペインは tmux pane に fish の関数 `ai-panes-sidebar`
(`.config/fish/functions/ai-panes-sidebar.fish`) が 2 秒間隔で書き込んでいる。

- **writer pane の識別**: tmux option `@ai_sidebar=1` を持つ pane
- **Claude セッションの task 表示データソース**: **transcript JSONL**
  (`~/.claude/projects/<encoded-path>/<session_id>.jsonl`)
- **描画ロジック**: `__ai_claude_task_lines` 関数。transcript から `TaskCreate` /
  `TaskUpdate` / `tool_result` を `rg` / `grep` で抽出し、`jq` でリプレイ →
  goal + root Task + 直接 child (= SubTask) を整形

### 使われていないもの (混同しない)

- ❌ `~/.claude/tasks/<session>/*.json` (Claude Code 内部状態。サイドペインは読まない)
- ❌ `~/.claude/progress-<session>.json` (statusline 用。サイドペインは読まない)
- ❌ Claude Code app バイナリの内部状態 (サイドペインに無関係)

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

### Step 2: データソース (transcript) の状態を再構築

writer pane の表示と「あるべき表示」を比較するため、同じ jq reducer を直接実行。
reducer は `.config/fish/functions/ai-panes-sidebar.fish` の `__ai_claude_task_lines`
内にあるので、そこからコピーする (重複定義しない)。

該当セッションの transcript:

```
~/.claude/projects/<encoded-cwd>/<session_id>.jsonl
```

encoded-cwd は cwd のスラッシュを `-` に置き換えたもの (例:
`/Users/u1/foo/bar` → `-Users-u1-foo-bar`)。

### Step 3: 表示 vs 再構築の差分を見て切り分け

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

`ai-panes-sidebar.fish` を編集しても、live writer pane は古いコードを実行し続ける。
反映には:

1. `state_version` 変数を bump
2. `.config/tmux/ensure-ai-sidebars.sh` を実行 (writer pane を respawn)

または、writer 内蔵の self-version-check (v8 以降) が自動 re-exec する。

### 罠 5: 親子階層は Goal/Task/SubTask の 3 レベル固定

renderer は root → 直接 child の 1 段下までしか描画しない。深い階層の task は
表示されない。詳細は claude-code-base-repository 側の
`home/rules/claude/task-progress.md` §4.3 参照。

「最新タスクが見えない」と言われたら、まず該当 task の `parentTaskId` を確認し、
**孫以下になっていないか** (= 3 階層 rule 違反になっていないか) を確認する。

## 関連

- `.config/fish/functions/ai-panes-sidebar.fish` — writer 本体 + `__ai_claude_task_lines`
- `.config/tmux/ensure-ai-sidebars.sh` — writer respawn
- claude-code-base-repository: `home/rules/claude/task-progress.md` §4.3 — Goal/Task/SubTask 3 階層制約
- claude-code-base-repository: `home/hooks/claude/statusline.sh` — statusline (別系統、混同しない)
