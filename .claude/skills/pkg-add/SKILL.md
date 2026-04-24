---
name: pkg-add
description: >
  パッケージやツールのインストール依頼を受けて、このリポジトリの管理ファイルに追加し
  update.sh で適用する。直接インストールは行わず、必ずコード管理を経由する。
  TRIGGER when: ユーザーが「〇〇をインストールして」「〇〇を追加して」
  「〇〇入れて」「brew install 〇〇」「npm install -g 〇〇」
  「fisher install 〇〇」と依頼した時。
  DO NOT TRIGGER when: 管理ファイルの閲覧のみ、パッケージの検索・情報確認のみ。
argument-hint: "<package-name> [package-name...]"
allowed-tools: Bash(brew *) Bash(npm *) Bash(fisher *) Bash(fish *) Bash(bash *) Read Edit Write
---

# Package Add スキル

パッケージやツールを**このリポジトリの管理ファイルに追加**し、update.sh で適用する。

## 大原則

**直接インストールしない。** `brew install` / `npm install -g` / `fisher install` を
直接実行するのではなく、必ず対応する管理ファイルに追記してから update.sh で適用する。
これにより環境の再現性を保証する。

## パッケージ種別と管理ファイル

| 種別 | 管理ファイル | 形式 | 適用方法 |
|------|------------|------|---------|
| Homebrew CLI | `Brewfile` | `brew '<name>'` | `update.sh` → `brew bundle` |
| Homebrew cask (GUI) | `Brewfile` | `cask '<name>'` | `update.sh` → `brew bundle` |
| Homebrew cask (フォント) | `Brewfile` | `cask 'font-<name>'` | `update.sh` → `brew bundle` |
| Homebrew 非公式 cask (個人 tap) | `projects/homebrew-tap/Casks/<name>.rb` + `Brewfile` | Cask Ruby DSL + `cask 'u-ichi/tap/<name>'` | tap に push → `update.sh` → `brew bundle` |
| npm グローバル | `Npmfile` | 1行1パッケージ名 | `update.sh` → `npm install -g` |
| Fisher プラグイン | `.config/fish/fish_plugins` | 1行1リポジトリパス | `fisher install` 後に自動更新 |

### 種別の判定基準

ユーザーの依頼から種別を判定する:

1. **明示的に指定がある場合**: そのまま従う（「brew で」「npm で」等）
2. **ツール名のみの場合**: 以下の順で判定する
   - `brew info <name>` で存在確認 → Homebrew 公式 (CLI or cask) → Brewfile に追加
   - Homebrew 公式に無く、GitHub Release で `.dmg` / `.app.tar.gz` を配布する macOS アプリ
     → **非公式 tap 経路** (後述「Homebrew 公式に無い macOS アプリ」節)
   - Node.js ツールなら → npm グローバル
   - Fish プラグインなら → Fisher
   - 判断できない場合 → ユーザーに確認する

## 手順

### 1. パッケージ情報の確認

```bash
# Homebrew の場合
brew info <package-name>

# npm の場合
npm info <package-name> --json 2>/dev/null | head -20

# Fisher の場合: リポジトリの存在確認
```

確認事項:
- パッケージが存在するか
- cask か formula か（Homebrew の場合）
- 既に管理ファイルに含まれていないか

既に含まれている場合は報告して終了する。

### 2. 配置先の決定

#### Brewfile のセクション

| パッケージの用途 | セクション |
|---|---|
| クラウド・インフラ (AWS, GCP, Terraform, セキュリティスキャン等) | `# === CLI: クラウド・インフラ ===` |
| 開発ツール (言語, ビルド, リンタ, VCS等) | `# === CLI: 開発ツール ===` |
| システム・ユーティリティ (モニタリング, ネットワーク等) | `# === CLI: システム・ユーティリティ ===` |
| GUI: 開発 | `# === GUI: 開発 ===` |
| GUI: ブラウザ・コミュニケーション | `# === GUI: ブラウザ・コミュニケーション ===` |
| GUI: AI | `# === GUI: AI ===` |
| GUI: 生産性 | `# === GUI: 生産性 ===` |
| GUI: システム・ユーティリティ | `# === GUI: システム・ユーティリティ ===` |
| GUI: その他 | `# === GUI: その他 ===` |
| フォント | `# === フォント ===` |

セクション内はアルファベット順を維持する。

#### Npmfile

- 1行1パッケージ名、アルファベット順
- `#` で始まる行はコメント
- ファイルが存在しない場合は新規作成する

#### fish_plugins

- 1行1リポジトリパス（例: `oh-my-fish/theme-bobthefish`）
- 末尾に追加

### 3. ユーザーへの確認

```
## パッケージ追加

| パッケージ | 種別 | 配置先 | 説明 |
|-----------|------|--------|------|
| infracost | brew (CLI) | CLI: クラウド・インフラ | Terraform のコスト見積もりツール |

追加してよいですか？
```

### 4. 管理ファイルの編集

Edit ツールで管理ファイルにパッケージを追加する。
新規ファイル（Npmfile 等）が必要な場合は Write で作成する。

### 5. 適用

#### Homebrew / npm の場合

```bash
bash <dotfiles ディレクトリ>/update.sh
```

#### Fisher プラグインの場合

fish_plugins はこのリポジトリで管理し、symlink 経由で `~/.config/fish/fish_plugins` に反映される。
プラグインのインストール自体は Fisher が行う:

```bash
fish -c "fisher update"
```

### 6. インストール確認

```bash
# Homebrew
brew list <package-name>

# npm
npm list -g <package-name>

# Fisher
fish -c "fisher list"
```

成功を確認してユーザーに報告する。

### 7. 複数パッケージの場合

手順 1-2 を全パッケージ分まとめて実施し、手順 3 で一覧を提示する。
手順 4 で一括編集、手順 5 の適用は 1 回のみ。

## Homebrew 公式に無い macOS アプリ (非公式 tap 経路)

Homebrew 公式に無いが `cask` で管理したい macOS アプリ (GitHub Release で dmg /
app.tar.gz を直配布するタイプ) は、個人 tap `u-ichi/homebrew-tap`
(`projects/homebrew-tap/`) に cask ファイルを登録する。通常の Brewfile 経路と
違い、**先に tap リポジトリへの commit + push が必要**。

### 手順

#### N1. 情報収集

- upstream の GitHub リポジトリを特定 (`owner/repo`)
- `gh api repos/<owner>/<repo>/releases/latest` で最新 release と assets を取得
- 対象アセット (aarch64 dmg 優先、なければ tar.gz) の URL と GitHub API `size` を控える

#### N2. アセットダウンロード + sha256

```bash
curl -sL -o /tmp/<name>.dmg "<asset url>"
# ダウンロードサイズが GitHub API の assets[].size と一致するか確認
shasum -a 256 /tmp/<name>.dmg
```

サイズ不一致なら sha256 は信用できないので再試行。

#### N3. Cask ファイルを projects/homebrew-tap/Casks/<name>.rb に新規作成

最小テンプレート (zap は手順 N5 で追記するので、この時点では含めない):

```ruby
cask "<name>" do
  version "<version>"
  sha256 "<sha256>"

  url "<asset url with #{version} interpolation>",
      verified: "github.com/<owner>/<repo>/"
  name "<Display Name>"
  desc "<one line description>"
  homepage "https://github.com/<owner>/<repo>"

  livecheck do
    url :url
    strategy :github_latest
    regex(/^<tag prefix>(\d+(?:\.\d+)+)$/i)
  end

  depends_on arch: :arm64         # Intel 版もあれば削除
  depends_on macos: ">= :big_sur" # upstream README を参照して調整

  app "<App Bundle Name>.app"
end
```

#### N4. ユーザー承認 + 初回インストール

通常の「手順 3. ユーザーへの確認」サマリーに以下を含めて提示:

- cask 名 / version / upstream owner/repo / アセット URL / sha256
- tap へ push する commit メッセージ案
- dotfiles 側で Brewfile に追加する行

承認後、以下を実行:

```bash
# tap リポジトリに cask ファイルを push
# Hook (pre-bash-guardrail) は HEREDOC signature を allow するのでこのパスで通る
git -C "<projects base>/homebrew-tap" add Casks/<name>.rb
git -C "<projects base>/homebrew-tap" commit -m "$(cat <<'EOF'
追加: <name> cask を登録

upstream: <owner>/<repo> v<version>
<一行補足>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "<projects base>/homebrew-tap" push

# dotfiles の Brewfile に cask 行追加 (適切なセクション内、アルファベット順)
# Edit で `cask 'u-ichi/tap/<name>'` を追記

# 適用
bash <dotfiles ディレクトリ>/update.sh
```

#### N5. bundle ID を実測して zap を追記

IMPORTANT: zap の bundle ID は推測しない。organization 名やドメインからの
推測は誤りやすい (例: `refactoringhq` → 実際は `club.refactoring.tolaria`)。
インストール後に必ず `defaults read` で実測する。

```bash
defaults read "/Applications/<App Bundle Name>.app/Contents/Info" CFBundleIdentifier
```

得られた bundle ID を使って zap ブロックを `Casks/<name>.rb` に追記:

```ruby
  zap trash: [
    "~/Library/Application Support/<App Display Name>",
    "~/Library/Caches/<bundle id>",
    "~/Library/Preferences/<bundle id>.plist",
    "~/Library/Saved Application State/<bundle id>.savedState",
  ]
```

tap リポジトリに追加 commit + push:

```bash
git -C "<projects base>/homebrew-tap" add Casks/<name>.rb
git -C "<projects base>/homebrew-tap" commit -m "$(cat <<'EOF'
fix: <name> の zap bundle ID を <bundle id> に設定

Info.plist 実測値。brew uninstall --zap で設定ファイルが掃除される。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
git -C "<projects base>/homebrew-tap" push
```

### 以降の version 更新

`cask-update` skill が担当する。本 skill は新規追加のみ。

## 新しい種別の追加

上記以外のパッケージマネージャ（pip, cargo, go install 等）が必要になった場合:

1. 管理ファイルの形式を決める（例: `Pipfile.global`, `Cargofile` 等）
2. `update.sh` にインストールセクションを追加する
3. このスキルの「パッケージ種別と管理ファイル」テーブルを更新する
4. 上記の変更をユーザーに提案し、承認を得てから実施する

**直接インストールで済ませない。** 管理ファイル + update.sh のパターンを維持する。

## エラー時の対応

- **パッケージが見つからない**: `brew search` / `npm search` で候補を検索して提示する
- **update.sh が失敗**: エラー出力を表示してユーザーに報告する
- **PATH の問題**: Fish の場合 `config.fish` への `fish_add_path` 追記が必要な場合がある。その場合は `.config/fish/config.fish` を編集する（直接ではなくリポジトリ内のファイルを編集する）
