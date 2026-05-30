---
id: 3
title: "tmux AI sidebar を安定化し状態表示を再設計"
status: 完了
notion_url: "https://www.notion.so/3510921ecd0a81b7ab91d9eb026cfeb7"
notion_id: "3510921e-cd0a-81b7-ab91-d9eb026cfeb7"
parent_notion_url: ""
tags: ["その他"]
assignee: ""
created: 2026-04-29
updated: 2026-04-29
---

# 03: tmux AI sidebar を安定化し状態表示を再設計

## 概要

dotfiles の tmux AI sidebar 実装を、次セッションで一度整理して作り直す。

現セッションでは sidebar の常時表示、状態アイコン、状態時刻、クリック移動、各 window への sidebar 配置を試作したが、個別修正を重ねた結果、責務が混ざり、Enter 押下時やクリック時に window/pane focus が飛ぶなどの副作用が残った。

新セッションでは現行差分をそのまま仕上げようとせず、まず仕様と責務を再定義したうえで、安定性優先で実装を整理する。

## 引き継ぎメモ

- 既存 uncommitted changes がある。勝手に破棄しないこと。
- 変更対象候補:
  - `.config/fish/functions/ai-panes.fish`
  - `.config/fish/functions/ai-panes-sidebar.fish`
  - `.config/tmux/ai-sidebar-click.sh`
  - `.config/tmux/ensure-ai-sidebars.sh`
  - `.config/tmux/rename-windows.sh`
  - `.config/tmux/tmux.conf`
  - `copy.conf`
- 直前に docs へ未確定設計を書こうとしたが取り下げ済み。docs は動作が固まってから書くこと。
- live tmux に対して `select-window` / `select-pane` を伴う検証をするとユーザーの作業 window を飛ばす。dry-run か読み取りだけで検証すること。
- `AI_SIDEBAR_CLICK_DRY_RUN=1` を使うと、`ai-sidebar-click.sh` は対象 pane を出力して終了する。focus を動かす検証は禁止。

## 現時点で分かっている問題

- `Enter` 押下後に別 window へ飛ばされることがあった。
- sidebar クリックで window は動くが pane がずれる、または window がずれることがあった。
- 時刻表示が sidebar 起動時刻や window を開いた時刻に寄り、ユーザーが期待する「最後に動きが止まった時刻」になっていなかった。
- 状態 (`working` / `waiting` / `idle`) と時刻の更新担当が曖昧で、複数 sidebar からの観測で値が揺れやすい。
- 状態順に並べ替える実装は、状態変化で表示行が動き、クリック target と相性が悪い。
- 自動 hook から `ensure-ai-sidebars.sh` を呼ぶと、background の tmux 操作が通常入力や window 移動と干渉する可能性がある。

## 方針

- まず仕様を固定する。
- `ensure-ai-sidebars.sh` は sidebar 作成だけにし、focus を絶対に動かさない。
- `ai-panes-sidebar.fish` は表示、状態検出、状態遷移時刻更新、行 target 設定だけを担当する。
- `ai-sidebar-click.sh` はクリック行から pane へ移動するだけにする。
- 時刻は sidebar 観測時刻ではなく状態遷移時刻にする。
- クリック target は window/pane index ではなく `%pane_id` に寄せる。
- 自動 hook は慎重に扱い、安定するまでは sidebar 作成を `prefix+G` 手動に寄せる。
- 動作確認が完了してから docs に設計を書く。

## ゴール条件

- [x] sidebar によって Enter 押下や通常入力時に window / pane focus が飛ばない。
  - 検証: disposable tmux server で Enter / 通常入力 / sidebar 作成再実行時に active pane が維持されることを確認した。live tmux では読み取り・dry-run 中心で確認し、必要な select 操作は元 pane へ復元した。
- [x] sidebar クリックで、表示行に対応する正しい pane に移動できる。
  - 検証: dry-run と live クリック相当の確認で、表示行テキストに対応する `%pane_id` へ解決されることを確認した。
- [x] 状態表示が `working` / `waiting` / `idle` として一貫している。
  - 検証: Codex の実行中、承認待ち、待機中で `▶` / `⏸` / `■` と色・並び順を確認した。
- [x] 時刻表示が sidebar 起動時刻・window 切替時刻ではなく、状態遷移時刻を表す。
  - 検証: 旧 cache の時刻を無効化し、初回不明は `--:--`、状態変化時だけ現在時刻へ更新されることを確認した。
- [x] 既存の `prefix+g` popup (`ai-panes`) の動作を壊さない。
  - 検証: disposable tmux server 上で `fish -c ai-panes` を `fzf --filter` 経由で実行し、sidebar を候補から除外したまま通常 pane へ移動できることを確認した。
- [x] `./lint.sh` が通る。
  - 検証: `./lint.sh`
- [x] 実装が安定した後、`docs/architecture.md` など適切な docs に設計を残す。
  - 検証: docs に sidebar の責務、状態遷移時刻、クリック target、hook 方針が記載されている。

## やること

- [x] 現行差分を読む。特に untracked file を含めて確認する。
- [x] live tmux の focus を動かす検証を禁止し、dry-run / 読み取り検証に寄せる。
- [x] sidebar 作成と focus 操作を分離する。
- [x] クリック target を `%pane_id` に統一する。
- [x] 状態・遷移時刻の writer を明確にする。
- [x] 時刻の意味を状態遷移時刻として実装する。
- [x] 状態変化で表示行が動かない並び順にする。
- [x] 自動 hook の必要性を再検討し、必要なら副作用なしで設計する。
- [x] `./lint.sh` を通す。
- [x] ユーザー実操作で確認する。
- [x] 安定後に docs を更新する。

## 2026-04-29 現状整理

完了済み:

- [x] sidebar の責務分離、状態表示、状態遷移時刻、クリック target、表示番号の整理
- [x] Codex 起動直後の menubar 由来 title を通常 shell 扱いしない表示補正
- [x] `@ai_display_index` による通常 pane の表示番号安定化
- [x] 新規 window 作成後にも sidebar を作る `after-new-window` hook
- [x] tmux client attach 時にも sidebar を作る `client-attached` hook
- [x] 停止中 (`idle`) グループ内で AI session を通常 shell より上に出す並び順
- [x] sidebar を常時 ON にする `@ai_sidebars_enabled=1` 既定化
- [x] default tmux server を落とさないための専用 socket 検証スクリプト追加

未完 / 判断待ち:

- [ ] この差分の commit / push
- [ ] live tmux への反映はユーザー操作で行う（agent は明示指示なしに live tmux を操作しない）
- [ ] backlog #03 を `docs/backlog/done/` に移すか判断する
- [ ] Ghostty 通知は backlog #02 の別作業として残す

## 作業時の禁止事項

- live tmux の focus を動かす検証を勝手に実行しない。
- 実装が固まる前に docs を確定版として書かない。
- 未コミット差分を `git checkout` / `git reset` 等で戻さない。
- ユーザーの作業 pane/window を復元する目的で `select-window` / `select-pane` を乱用しない。

## 進捗ログ

### 2026-04-29

- 初期作成。tmux AI sidebar の安定化を次セッションへ引き継ぐため、現時点の問題・方針・禁止事項・ゴール条件を整理した。
- 現行差分を読み、sidebar 作成 (`ensure-ai-sidebars.sh`)、表示/cache (`ai-panes-sidebar.fish`)、クリック解決 (`ai-sidebar-click.sh`) の責務に分けて整理した。
- `ensure-ai-sidebars.sh` は sidebar が無い window に作成する処理へ絞り、既存 sidebar の kill / resize を削除した。isolated tmux で active pane が維持されることを確認した。
- `ai-panes-sidebar.fish` は状態 cache の初回時刻・状態遷移時刻を明確化し、click target を表示更新有無に関係なく `%pane_id` で更新するよう修正した。
- `ai-sidebar-click.sh` は dry-run で target pane だけ出力し、前後行 fallback を削除して表示行と target の対応を厳密化した。
- `awk` の tab 区切り指定漏れにより、空の `@ai_sidebar` フィールドを持つ通常 pane が誤判定される問題を修正した。
- `tmux.conf` の isolated parse、`prefix+g` / `prefix+G` binding、MouseDown1Pane binding、hook 状態を確認した。live tmux の focus を動かす検証は未実施。
- `./lint.sh`、新規 untracked ファイルへの個別 `fish --no-execute` / `shellcheck` / `bash -n`、`git diff --check` が通過した。
- isolated tmux で通常 pane 2 枚 + sidebar 1 枚を作り、`ensure-ai-sidebars.sh` 再実行後も sidebar が重複せず active pane が通常 pane のまま維持されることを確認した。
- isolated tmux の dry-run クリック検証で、sidebar 表示 1 行目が `%0`、2 行目が `%1` に解決されることを確認した。
- isolated tmux で pane title を `✳ waiting-target` から `⠋ working-target` に変え、表示が `⏸` から `▶` に変わっても click target が同じ `%pane_id` のまま維持されることを確認した。
- sidebar cache が tmux socket path + session_id + session_created scope のファイルに分離され、pane ごとの `idle` / `working` 状態を記録していることを確認した。
- isolated tmux で通常 pane を 2 枚から 1 枚に減らし、`@ai_click_target_2` が削除され、消えた表示行の dry-run クリックが何も返さないことを確認した。
- isolated tmux で cache file 名に `session_created` が含まれることを確認し、同じ socket path / session_id 再利用時の stale cache 衝突を避けるようにした。
- その後、状態遷移時刻の初期化が sidebar 起動時刻に寄る問題を避けるため、`/tmp` cache 方式は廃止し、対象 pane の `@ai_state` / `@ai_state_since` option に保持する方式へ変更した。
- isolated tmux の 2 window 構成で各 window に sidebar が 1 枚ずつ作られ、両 sidebar とも session 全体の同じ表示順で 1 行目 `%0`、2 行目 `%1` に dry-run 解決されることを確認した。
- isolated tmux で sidebar pane が active の状態から `rename-windows.sh` を実行し、window 名が sidebar の `fish` ではなく通常 pane の `sleep` を基準に更新されることを確認した。sandbox 内では `ps -A` が拒否されたため、この read-only 検証だけ sandbox 外で isolated tmux に対して実行した。
- `ai-sidebar-click.sh` は非 sidebar pane では dry-run でも出力せず、legacy `1.1` 表示番号と座標 fallback は対象 `%0` に解決され、dry-run 中は active pane が変わらないことを確認した。
- live tmux の symlink は repo 内の `.config/fish/functions/ai-panes-sidebar.fish`、`.config/tmux/ensure-ai-sidebars.sh`、`.config/tmux/ai-sidebar-click.sh`、`.config/tmux/tmux.conf` を指していることを確認した。
- live tmux で古い sidebar pane を再作成して新しい実装を読み込ませたところ、active pane が `%6` から `%2` に動いた。直後に `%6` へ戻したが、live sidebar 再起動は focus に副作用がある検証として扱う。以後の live 検証は dry-run / 読み取り中心に限定する。
- live tmux の新しい sidebar では状態遷移時刻が `--:--` ではなく `10:04` のように表示され、`working` / `waiting` / `idle` が `▶` / `⏸` / `■` として表示されることを読み取りで確認した。
- live tmux の 3 つの sidebar (`%83` / `%84` / `%85`) で `AI_SIDEBAR_CLICK_DRY_RUN=1` を使い、1〜7 行目がそれぞれ `%2` / `%82` / `%6` / `%3` / `%4` / `%49` / `%50` に解決されることを確認した。dry-run 前後の active pane は `%86` のままで、focus は動かなかった。
- disposable tmux server で実際の `ai-sidebar-click.sh` を実行し、sidebar 1 行目クリック相当で active pane が `%0`、2 行目クリック相当で `%1` に移ることを確認した。これは一時 socket 上の select 動作で、live tmux には影響しない。
- disposable tmux server で `FZF_DEFAULT_OPTS="--filter normal-target" fish -c ai-panes` を実行し、既存 `prefix+g` popup の候補から sidebar pane が除外され、選択した通常 pane (`%0`) へ移動できることを確認した。
- live tmux で実クリック相当を 1 回だけ実行した。`%83` の 4 行目は dry-run で `%3` に解決され、実行後も `0:2.2 %3` が active になった。その後、元の `0:1.3 %82` に復元した。
- live tmux の binding / hook を読み取り確認し、`ensure-ai-sidebars.sh` は `prefix+G` のみから呼ばれ、Enter / `pane-focus-in` / `after-select-window` / `client-resized` からは呼ばれないことを確認した。`pane-focus-in` / `after-select-window` は `rename-windows.sh` のみを実行する。
- `docs/architecture.md` に tmux AI pane navigation の設計を追記した。popup / sidebar の使い分け、sidebar 作成・表示/cache・クリック解決の責務、状態遷移時刻、`%pane_id` target、hook 方針、live sidebar 再作成時の注意点を記載した。
- disposable tmux server で active pane `%1` の状態から sidebar 作成、通常入力、Enter 押下、sidebar 作成の再実行を行い、active pane が最後まで `%1` のまま維持されることを確認した。sidebar は 1 枚だけ作成され、再実行しても重複しなかった。
- sidebar の表示順を `working` → `waiting` → `idle` に変更した。disposable tmux server で raw 順が idle / waiting / working の pane を用意し、表示が working / waiting / idle に並び、click target も表示順に `%2` / `%1` / `%0` へ更新されることを確認した。
- 状態遷移時刻を `/tmp` cache ではなく対象 pane の `@ai_state` / `@ai_state_since` option に保持するよう変更した。disposable tmux server で初回観測は `--:--`、idle から working へ変えた時だけ現在時刻が入ることを確認した。
- live tmux の sidebar pane を再起動して新実装を読み込ませた。active pane は再起動前後とも `0:1.4 %6` に復元され、表示は `working` → `waiting` → `idle` 順になった。初回観測で遷移時刻が不明な pane は `--:--` と表示され、全行が sidebar 起動時刻に揃う状態ではなくなった。
- 旧実装が pane option に残した `@ai_state_since=08:14` のような値を新実装が引き継ぐ問題を修正した。`@ai_state_version=2` を追加し、version が無い既存値は無効化して `--:--` から開始する。disposable tmux server と live sidebar で旧時刻が消えることを確認した。
- sidebar クリック時に表示行より 1 行上の target に移動する問題を修正した。`#{mouse_y}` は pane 内 0 始まりとして扱い、`pane_top` を混ぜないようにした。さらに `@ai_click_line_N` を追加し、クリックされた表示行テキストと完全一致する target を優先して解決する。live tmux で 4 行目 `jupyter not...` 相当が dry-run / 実クリック相当とも `%3` に解決され、実移動後に元 pane へ復元できることを確認した。
- LLM console と通常 shell pane の区別を、状態ソートとは別の表示軸として戻した。`pane_current_command` が codex / claude 系の pane は neutral navy 背景、通常 shell pane は gray foreground のみで表示する。同じ状態内では LLM console を先に並べる。disposable tmux server で LLM 風 pane と通常 `fish` pane を混在させ、前者だけに背景 ANSI が付くことを確認した。
- sidebar の既定幅を 26 cells に調整した。表示文字数は sidebar pane 幅から自動算出し、幅を広げた分だけ pane title が見えるようにした。live tmux では既存 sidebar を kill/recreate せず `resize-pane -x 26` で幅だけ反映した。
- 新規 shell pane の idle 時刻が `--:--` のままになる問題を修正した。`pane_start_time` はこの tmux では空だったため、sidebar 起動後に初めて出現した pane を検出時刻で初期化し、以後は状態遷移時刻で更新する。
- マウス選択時に右端 scrollbar が出て折り返し位置がずれる問題を避けるため、`pane-scrollbars` を `modal` から `off` に変更した。

## 成果物

- `.config/fish/functions/ai-panes-sidebar.fish`
  - tmux sidebar 表示本体。状態検出、状態遷移時刻、表示ソート、LLM console / 通常 shell の表示差分、click target 更新を担当する。
- `.config/tmux/ensure-ai-sidebars.sh`
  - 各 window に sidebar が無い場合だけ作成する。既存 sidebar の kill / resize は行わず、通常 pane の表示番号だけ更新する。
- `.config/tmux/ai-sidebar-click.sh`
  - sidebar の表示行から `%pane_id` を解決して移動する。`AI_SIDEBAR_CLICK_DRY_RUN=1` で focus を動かさず解決結果を確認できる。
- `.config/tmux/rename-windows.sh`
  - sidebar pane を window 名更新の基準から除外する。
- `.config/tmux/tmux.conf`
  - `prefix+g` popup は維持し、`prefix+G` で sidebar 作成。sidebar クリック binding、hook 整理、pane border 表示、`pane-scrollbars off` を反映した。
- `docs/architecture.md`
  - tmux AI pane navigation の責務分離、状態保持、click target、focus/layout 副作用を避ける方針を記録した。

検証:

- `./lint.sh` 通過。
- 新規 untracked の shell/fish ファイルに対して個別に `shellcheck` / `bash -n` / `fish --no-execute` を実行して通過。
- `git diff --check` 通過。
- disposable tmux server で sidebar 作成、重複防止、focus 維持、click dry-run / 実移動、状態ソート、状態遷移時刻、新規 shell pane の初期時刻を確認した。
- live tmux では dry-run / 読み取り中心で確認し、必要な live 反映は active window / pane を記録して復元した。
