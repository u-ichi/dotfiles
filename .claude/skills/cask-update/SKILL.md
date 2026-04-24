---
name: cask-update
description: >
  u-ichi/homebrew-tap 配下のローカル cask (Tolaria 等) の version / sha256 /
  zap bundle ID を最新 GitHub Release に合わせて更新する。Homebrew 公式に無い非公式
  cask を Claude が再現性をもって bump するためのスキル。
  MANDATORY TRIGGERS: /cask-update, cask 更新して, cask bump, tolaria 更新, tolaria bump,
  tap 更新, homebrew-tap 更新, <cask名> の version 上げて (<cask名> が u-ichi/tap 内のもの)。
  DO NOT TRIGGER when: Homebrew 公式 cask の更新 (brew upgrade --cask で済む),
  CLI (formula) の更新, 新規 cask の追加 (pkg-add の責務)。
argument-hint: "[cask-name]"
---

# Cask Update スキル

個人 tap `u-ichi/homebrew-tap` 配下のローカル cask を GitHub Release の最新版に
bump する。version / sha256 / livecheck / zap bundle ID の更新まで担う。

## 前提

- tap リポジトリは `projects/homebrew-tap/` に clone 済み (`origin: git@github.com:u-ichi/homebrew-tap`)
- 各 cask は `Casks/<name>.rb` に配置され、GitHub Release の dmg / app.tar.gz を参照
- dotfiles の Brewfile は `tap "u-ichi/tap"` + `cask "u-ichi/tap/<name>"` で参照

## この skill が `/commit` skill を使わない理由

cross-project-context.md により `/commit` skill もクロスプロジェクト commit 可能だが、
cask bump は差分が定型的 (version / sha256 / zap の機械的置換) で、本 skill 内で
完結した承認サマリー提示で十分。`/commit` skill のフルフォーマット (設計資料検出 /
対象リポジトリ明示 / PR 作成等) は tap リポジトリの単純な bump には冗長。

dotfiles 側の変更 (Brewfile 編集等) は本 skill の対象外で、それは通常通り
`/commit` skill で commit する。

## 手順

### 1. 対象 cask の特定

引数または会話から対象 cask 名 (例: `tolaria`) を特定する。

```bash
ls "<projects base>/homebrew-tap/Casks/"
```

複数候補がある場合はユーザーに確認する。

### 2. 現行の version / sha256 / upstream URL を読み取る

```
Read: projects/homebrew-tap/Casks/<name>.rb
```

`url` 行から upstream の GitHub owner/repo を抽出する (例: `refactoringhq/tolaria`)。
`livecheck` の regex と tag prefix も控えておく (手順 3 でバージョン抽出に使う)。

### 3. 最新リリース情報を取得

```bash
gh api repos/<owner>/<repo>/releases/latest
```

取得すべき情報:

- `tag_name` から新 version を抽出 (livecheck の regex と整合するか確認)
- `assets[].browser_download_url` から dmg / tar.gz の直リンク
- `assets[].size` (ダウンロード時の整合確認に使う)
- 新 version が現行と同じなら「更新不要」として終了

### 4. 新アセットをダウンロードして sha256 計算

```bash
curl -sL -o /tmp/<name>-<version>.dmg "<asset url>"
shasum -a 256 /tmp/<name>-<version>.dmg
```

ダウンロードしたファイルサイズが GitHub API の `assets[].size` と一致することを
必ず確認する (リダイレクトミスで HTML ページを取ってしまうのを防ぐ)。
サイズ不一致なら sha256 は信用できないので手順 3 からやり直し。

### 5. bundle ID の再検証 (zap 更新)

IMPORTANT: zap の bundle ID は推測せず、**インストール済みアプリの Info.plist から
実測**する。cask 初期登録時や upstream で bundle ID が変わった時に誤推測を防ぐ。

```bash
defaults read "/Applications/<Name>.app/Contents/Info" CFBundleIdentifier
```

アプリがローカルに無い (初回 bump 等) 場合:

1. 先に現行 version を一時的にインストール (`brew install --cask u-ichi/tap/<name>`)
2. bundle ID を実測
3. アンインストール不要 (そのまま次の bump で上書きされる)

現行 cask の zap と実測値がずれている場合は、version bump と同じ commit で zap
bundle ID も訂正する (commit メッセージ本文に訂正理由を 1 行追加)。

### 6. Casks/<name>.rb を更新

Edit で以下を更新:

- `version "<new_version>"`
- `sha256 "<new_sha256>"`
- zap bundle ID (ずれていた場合のみ)

他の行 (url / livecheck / depends_on / app) は upstream のファイル名フォーマットが
変わらない限り触らない。upstream 側で url pattern が変わっていたら本 skill では
対処せず、ユーザーに手動調整を依頼する。

### 7. 承認サマリー提示

以下をユーザーに提示して承認を得る (approval-gates.md の承認ゲート対象):

- cask 名 / old version → new version
- old sha256 → new sha256 (短縮表示可)
- zap 変更の有無 (bundle ID 訂正があれば差分も)
- upstream release URL (`gh browse <owner>/<repo> -- releases/tag/<tag>`)
- tap リポジトリと dotfiles 側の追加作業予定 (通常は手順 8 の commit/push + 手順 9 の brew upgrade のみ)

「はい」「OK」等の明示的肯定のみ承認とみなす (沈黙は承認にしない)。

### 8. tap リポジトリに commit + push

承認後、`git -C "<projects base>/homebrew-tap" ...` 形式で tap リポジトリに対して
直接操作する。Hook (pre-bash-guardrail) は `git -C <path> commit -m "$(cat <<'EOF'...EOF)"`
HEREDOC signature を allow しているのでこのパスで通る。

```bash
git -C "<projects base>/homebrew-tap" add Casks/<name>.rb
git -C "<projects base>/homebrew-tap" commit -m "$(cat <<'EOF'
bump: <name> <old_version> → <new_version>

sha256 を <new_sha256> に更新。
<zap 変更があれば 1 行で説明>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "<projects base>/homebrew-tap" push
```

push 後、`gh api repos/u-ichi/homebrew-tap/contents/Casks/<name>.rb` で GitHub 側に
反映されたことを確認する。

### 9. ローカル環境への反映

```bash
brew update
brew upgrade --cask <name>
```

インストール後、`/Applications/<Name>.app` の `CFBundleShortVersionString` が新
version と一致することを確認する。

```bash
defaults read "/Applications/<Name>.app/Contents/Info" CFBundleShortVersionString
```

### 10. ユーザーへの報告

更新サマリー:

- cask 名 / old version → new version
- sha256 (新値)
- zap bundle ID 変更の有無
- tap リポジトリの commit URL
- ローカルインストール確認結果 (CFBundleShortVersionString 一致)

## エラー時の対応

- **upstream 無反応**: GitHub API rate limit を疑い `gh auth status` を確認
- **sha256 不一致**: ダウンロード失敗を疑い再試行。2 回失敗したら asset URL を
  ブラウザで直接開いて手動確認
- **brew upgrade 失敗**: `brew --repository u-ichi/tap` で local tap の git 状態確認、
  `git pull` で最新化してから再試行
- **depends_on 不一致 (macos version 等)**: upstream の README / Info.plist で要件が
  変わった可能性。手動で cask 本文の depends_on を更新
- **url pattern が変わった**: 本 skill では対処せず、ユーザーに手動調整を依頼

## 関連

- `pkg-add` skill — 新規 cask の tap への初期登録
- `cross-project-context.md` — 別リポジトリへの commit は承認ゲート通過後であれば
  同セッション内で正常運用 (旧ルールの「別セッション必須」は誤り)
- `skill-priority.md` の hook allow 条件 — `git -C <path> commit -m "$(cat <<'EOF'...EOF)"`
  HEREDOC signature は pre-bash-guardrail が通す
- `approval-gates.md` — 手順 7 の承認ゲートの canonical 定義
