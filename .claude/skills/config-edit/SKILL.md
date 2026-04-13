---
name: config-edit
description: >
  ツールの設定変更依頼を受けて、このリポジトリ内の設定ファイルを編集する。
  ホームディレクトリのファイルを直接編集せず、必ずリポジトリ経由で管理する。
  TRIGGER when: ユーザーが「〇〇の設定を変えて」「〇〇を設定して」
  「gitの設定」「fishのalias追加」「ghosttyのフォント変えて」
  「tmuxのキーバインド」「karabinerの設定」と依頼した時。
  DO NOT TRIGGER when: 設定ファイルの閲覧のみ、パッケージの追加（→ pkg-add）。
argument-hint: "<tool> <what-to-change>"
allowed-tools: Bash(bash *) Bash(git *) Bash(fish *) Read Edit Write
---

# Config Edit スキル

ツールの設定変更を**このリポジトリ内のファイルを編集**して行う。

## 大原則

**ホームディレクトリのファイルを直接編集しない。**
このリポジトリの `.config/` 配下を編集すれば、symlink 経由で即座に反映される。
リポジトリにないファイルを新規追加する場合は、`links.conf` への登録が必要。

## 管理対象と編集先

| ツール | リポジトリ内のパス | symlink 先 | 反映方法 |
|--------|-------------------|-----------|---------|
| Git | `.config/git/config` | `~/.gitconfig` | 即時（symlink） |
| Fish (メイン) | `.config/fish/config.fish` | `~/.config/fish/config.fish` | 即時（symlink） |
| Fish (関数) | `.config/fish/functions/<name>.fish` | `~/.config/fish/functions/<name>.fish` | 個別 symlink 要 |
| Fish (補完) | `.config/fish/completions/` | `~/.config/fish/completions/` | 即時（ディレクトリ symlink） |
| Fish (プラグイン) | `.config/fish/fish_plugins` | `~/.config/fish/fish_plugins` | `fisher update` で適用 |
| Ghostty | `.config/ghostty/config` | `~/Library/Application Support/com.mitchellh.ghostty/config` | 即時（symlink）、`Cmd+Shift+,` でリロード |
| tmux | `.config/tmux/tmux.conf` | `~/.config/tmux/tmux.conf` | 即時（symlink）、`prefix r` でリロード |
| Karabiner | `.config/karabiner/` | `~/.config/karabiner/` | 即時（ディレクトリ symlink、Karabiner が自動検出） |
| Codex CLI | `.config/codex/config.toml` | `~/.codex/config.toml` | `update.sh` の `ensure_codex_config` で展開 |

## 手順

### 1. 対象ツールと編集ファイルの特定

ユーザーの依頼から:
- どのツールの設定か
- リポジトリ内のどのファイルを編集すべきか

を特定する。不明な場合はユーザーに確認する。

### 2. 現在の設定を確認

該当ファイルを Read で読み取り、現在の設定を把握する。
ユーザーの依頼と関連する既存設定があればその周辺を理解する。

### 3. 変更内容の提示

変更箇所をユーザーに提示して承認を待つ:

```
## 設定変更

**対象**: Ghostty (`config-ghostty/config`)
**変更**: フォントサイズを 14 → 16 に変更

```diff
-font-size = 14
+font-size = 16
```

適用してよいですか？
```

### 4. 編集の実行

Edit ツールでリポジトリ内のファイルを編集する。

### 5. 新規ファイルの場合の追加手順

リポジトリに存在しないファイルを新規追加する場合は、追加の手順が必要:

#### 5a. ファイルの作成

Write ツールでリポジトリ内の適切な場所にファイルを作成する。

#### 5b. links.conf への登録

新規ファイルの symlink を `links.conf` に追加する:

```
# 形式: リポジトリ相対パス : リンク先
.config/<tool>/<file>  : $HOME/.config/<tool>/<file>
```

- 既存の同ツールのエントリ付近に配置する
- コメントでセクション分けされている場合はそのセクションに従う

#### 5c. symlink の作成

```bash
bash <dotfiles ディレクトリ>/update.sh
```

または `install.sh` で symlink を作成する。

### 6. 反映の確認

ツールごとの確認方法:

| ツール | 確認方法 |
|--------|---------|
| Git | `git config --list` で該当設定を確認 |
| Fish | `fish -c "<command>"` で動作確認、または新しいシェルで確認 |
| Ghostty | 設定リロード後の動作確認（自動または `Cmd+Shift+,`） |
| tmux | `tmux source-file ~/.config/tmux/tmux.conf` または `prefix r` |
| Karabiner | Karabiner が自動検出して即反映 |

## 注意事項

### Git の個人情報

`.config/git/config` には個人情報（name, email）を直接書かない。
`[include] path = config.local` で分離されており、個人情報は `config.local`（リポジトリ外）に書く。

### Fish の functions/

Fish の `functions/` は個別ファイル単位で symlink する方式。
新しい関数ファイルを追加する場合は `links.conf` にエントリが必要。
テーマ系ファイル（bobthefish, fisher 自動生成）は `.gitignore` で除外済み。

### Karabiner

`karabiner.json` は Karabiner-Elements が自動的に書き換えるため、
手動編集時は JSON の構造を壊さないよう注意する。
`automatic_backups/` は Karabiner が自動生成するバックアップ。

## エラー時の対応

- **symlink が壊れている**: `update.sh` を実行して再作成する
- **設定構文エラー**: ツール固有のバリデーションで確認する
  - Fish: `fish --no-execute <file>`
  - JSON (Karabiner): `python3 -m json.tool <file>`
  - TOML (Codex): `taplo check <file>`
- **変更が反映されない**: symlink が正しいか `ls -la <link先>` で確認する
