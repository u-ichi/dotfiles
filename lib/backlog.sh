#!/usr/bin/env bash
# Backlog.mdを公式main、または管理patchの指定版からビルドして配置する

backlog_binary_is_valid() {
  local bin="$1"
  [ -x "$bin" ] && "$bin" --version >/dev/null 2>&1
}

cleanup_backlog_npm_shadow() {
  local bin="$1"
  local bin_dir="$2"
  local resolved_bin

  case ":$PATH:" in
    *":$bin_dir:"*) ;;
    *) PATH="${PATH:+$PATH:}$bin_dir" ;;
  esac

  if command -v npm &>/dev/null && npm ls -g backlog.md >/dev/null 2>&1; then
    echo "削除:     npm グローバル backlog.md"
    if ! npm uninstall -g backlog.md; then
      echo "エラー: npm グローバル backlog.md を削除できませんでした"
      return 1
    fi
  fi

  resolved_bin="$(command -v backlog 2>/dev/null || true)"
  if [ "$resolved_bin" != "$bin" ]; then
    echo "エラー: backlog の解決先が想定と異なります: ${resolved_bin:-未検出}"
    return 1
  fi

  echo "済み:     backlog → $resolved_bin"
}

backlog_use_existing_binary() {
  local bin="$1"
  local bin_dir="$2"
  local reason="$3"

  if backlog_binary_is_valid "$bin"; then
    echo "警告: ${reason}。既存バイナリを使用します"
    cleanup_backlog_npm_shadow "$bin" "$bin_dir"
    return $?
  fi

  echo "エラー: ${reason}、利用可能な既存バイナリもありません"
  return 1
}

backlog_read_manifest() {
  local manifest="$1"

  bun -e '
    const manifest = JSON.parse(await Bun.file(process.argv[1]).text());
    const validBase = typeof manifest.base_commit === "string" && /^[0-9a-fA-F]{40}$/.test(manifest.base_commit);
    const validPatches = Array.isArray(manifest.patches) && manifest.patches.every((patch) => {
      if (typeof patch !== "string" || patch.length === 0 || /[\t\r\n]/.test(patch) || patch.startsWith("/")) {
        return false;
      }
      return patch.split("/").every((part) => part !== "" && part !== "." && part !== "..");
    });
    if (!validBase || !validPatches) {
      process.exit(1);
    }
    process.stdout.write([manifest.base_commit, ...manifest.patches].join("\n"));
  ' "$manifest"
}

backlog_manifest_digest() {
  git hash-object -- "$1"
}

backlog_patch_digest() (
  local patch_dir="$1"
  shift
  local patch_name

  for patch_name in "$@"; do
    printf '%s\n' "$patch_name"
    git hash-object -- "$patch_dir/$patch_name"
  done | git hash-object --stdin
)

ensure_backlog_head() (
  local src_dir="${BACKLOG_MD_SRC_DIR:-$HOME/.local/share/backlog.md}"
  local bin_dir="${BACKLOG_MD_BIN_DIR:-$HOME/.local/bin}"
  local bin="$bin_dir/backlog"
  local marker="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backlog/installed-commit"
  local patch_dir="${BACKLOG_MD_PATCH_DIR:-$HOME/.config/backlog-md/managed}"
  local manifest_path="$patch_dir/manifest.json"
  local recipe="1"
  local marker_dir lock_file lock_pid
  local origin_url remote_sha marker_value marker_expected
  local pkg_version short_sha src_dir_real repo_root_real
  local manifest_data base_commit manifest_digest patches_digest
  local build_dir="" build_src_dir build_sha
  local patch_name patch_path
  local managed_manifest=0
  local tmp_bin tmp_marker
  local -a patch_names=()

  if ! command -v git &>/dev/null; then
    echo "エラー: git が見つかりません。Brewfile を反映してから再実行してください"
    return 1
  fi
  if ! command -v bun &>/dev/null; then
    echo "エラー: bun が見つかりません。Brewfile を反映してから再実行してください"
    return 1
  fi

  echo "=== Backlog.md ==="
  marker_dir="$(dirname "$marker")"
  if ! mkdir -p "$marker_dir"; then
    echo "エラー: Backlog.md の状態ディレクトリを作成できません: $marker_dir"
    return 1
  fi
  lock_file="$marker_dir/backlog.lock"
  lock_pid="${BASHPID:-$$}"
  if ! /usr/bin/shlock -p "$lock_pid" -f "$lock_file"; then
    if backlog_binary_is_valid "$bin"; then
      echo "警告: Backlog.md の更新は別の実行が処理中のため、既存バイナリを使用します"
      cleanup_backlog_npm_shadow "$bin" "$bin_dir"
      return $?
    fi
    echo "エラー: Backlog.md の更新は別の実行が処理中で、利用可能な既存バイナリもありません"
    return 1
  fi
  trap '
    if [ -n "$build_dir" ]; then
      rm -rf "$build_dir"
    fi
    if [ "$(cat "$lock_file" 2>/dev/null)" = "'"$lock_pid"'" ]; then
      rm -f "$lock_file"
    fi
  ' EXIT

  if [ -e "$manifest_path" ]; then
    managed_manifest=1
    if [ ! -f "$manifest_path" ]; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed manifest が通常ファイルではありません: $manifest_path"
      return $?
    fi
    if ! manifest_data="$(backlog_read_manifest "$manifest_path")"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed manifest を読み取れませんでした: $manifest_path"
      return $?
    fi
    base_commit="$(printf '%s\n' "$manifest_data" | sed -n '1p')"
    while IFS= read -r patch_name; do
      [ -n "$patch_name" ] || continue
      patch_names[${#patch_names[@]}]="$patch_name"
    done < <(printf '%s\n' "$manifest_data" | sed '1d')
    for patch_name in "${patch_names[@]}"; do
      patch_path="$patch_dir/$patch_name"
      if [ ! -f "$patch_path" ]; then
        backlog_use_existing_binary "$bin" "$bin_dir" \
          "Backlog.md の managed patch が見つかりません: $patch_path"
        return $?
      fi
    done
    if ! manifest_digest="$(backlog_manifest_digest "$manifest_path")"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed manifest の digest を計算できませんでした"
      return $?
    fi
    if ! patches_digest="$(backlog_patch_digest "$patch_dir" "${patch_names[@]}")"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed patch の digest を計算できませんでした"
      return $?
    fi
  fi

  if [ ! -e "$src_dir" ]; then
    echo "取得:     Backlog.md"
    if ! git clone https://github.com/MrLesk/Backlog.md "$src_dir"; then
      echo "エラー: Backlog.md の取得に失敗しました"
      return 1
    fi
  fi

  if ! git -C "$src_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "エラー: Backlog.md の管理先が git リポジトリではありません: $src_dir"
    return 1
  fi
  src_dir_real="$(cd "$src_dir" && pwd -P)"
  repo_root_real="$(git -C "$src_dir" rev-parse --show-toplevel 2>/dev/null || true)"
  if ! repo_root_real="$(cd "$repo_root_real" 2>/dev/null && pwd -P)"; then
    repo_root_real=""
  fi
  if [ "$src_dir_real" != "$repo_root_real" ]; then
    echo "エラー: Backlog.md の管理先はリポジトリの先頭ディレクトリを指定してください: $src_dir"
    return 1
  fi
  origin_url="$(git -C "$src_dir" remote get-url origin 2>/dev/null || true)"
  case "$origin_url" in
    git@github.com:MrLesk/Backlog.md|git@github.com:MrLesk/Backlog.md.git|https://github.com/MrLesk/Backlog.md|https://github.com/MrLesk/Backlog.md.git|https://github.com/MrLesk/Backlog.md/|https://github.com/MrLesk/Backlog.md.git/)
      ;;
    *)
      echo "エラー: Backlog.md の origin が想定と異なります: $src_dir"
      return 1
      ;;
  esac

  if ! git -C "$src_dir" fetch origin main; then
    if backlog_binary_is_valid "$bin"; then
      echo "警告: Backlog.md の取得に失敗したため、既存バイナリを使用します"
      cleanup_backlog_npm_shadow "$bin" "$bin_dir"
      return $?
    fi
    echo "エラー: Backlog.md の取得に失敗し、利用可能な既存バイナリもありません"
    return 1
  fi

  remote_sha="$(git -C "$src_dir" rev-parse origin/main)"
  if [ "$managed_manifest" -eq 1 ]; then
    if ! build_sha="$(git -C "$src_dir" rev-parse "${base_commit}^{commit}" 2>/dev/null)"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed base commit が source clone にありません: $base_commit"
      return $?
    fi
    base_commit="$build_sha"
    marker_expected="$base_commit recipe=$recipe manifest_digest=$manifest_digest patches_digest=$patches_digest"
  else
    build_sha="$remote_sha"
    marker_expected="$remote_sha recipe=$recipe"
  fi
  marker_value="$(cat "$marker" 2>/dev/null || true)"
  if [ "$marker_value" = "$marker_expected" ] && backlog_binary_is_valid "$bin"; then
    echo "済み:     Backlog.md ($build_sha)"
    cleanup_backlog_npm_shadow "$bin" "$bin_dir"
    return $?
  fi

  build_src_dir="$src_dir"
  if [ "$managed_manifest" -eq 1 ]; then
    if ! build_dir="$(mktemp -d "${TMPDIR:-/tmp}/backlog-md-build.XXXXXX")"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed build directory を作成できませんでした"
      return $?
    fi
    if ! git -C "$src_dir" archive --format=tar "$build_sha" | tar -xf - -C "$build_dir"; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed base commit を一時 build directory へ展開できませんでした"
      return $?
    fi
    for patch_name in "${patch_names[@]}"; do
      patch_path="$patch_dir/$patch_name"
      if ! git -C "$build_dir" apply -- "$patch_path"; then
        backlog_use_existing_binary "$bin" "$bin_dir" \
          "Backlog.md の managed patch を適用できませんでした: $patch_name"
        return $?
      fi
    done
    build_src_dir="$build_dir"
  else
    if ! git -C "$src_dir" reset --hard origin/main; then
      echo "エラー: Backlog.md を origin/main へ揃えられませんでした"
      return 1
    fi
  fi

  pkg_version="$(bun -e 'process.stdout.write(require(process.argv[1]).version)' "$build_src_dir/package.json" 2>/dev/null || true)"
  if [ -z "$pkg_version" ]; then
    if [ "$managed_manifest" -eq 1 ]; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed source から package.json の version を取得できませんでした"
      return $?
    fi
    echo "エラー: Backlog.md の package.json から version を取得できません"
    return 1
  fi
  short_sha="$(git -C "$src_dir" rev-parse --short "$build_sha")"
  if ! (
    cd "$build_src_dir" || exit 1
    bun install --frozen-lockfile || exit 1
    # Bun 1.3.14 では trustedDependencies に含まれる bun の postinstall が
    # 実行されず、node_modules/.bin/bun が失敗用のプレースホルダのままになる場合がある。
    # 上流が信頼済みにしている bun だけを、必要な時に補正する。
    if grep -q "postinstall script was not run" node_modules/bun/bin/bun.exe; then
      bun node_modules/bun/install.js || exit 1
    fi
    BACKLOG_BUILD_VERSION="${pkg_version}+g${short_sha}" bun run build
  ); then
    if backlog_binary_is_valid "$bin"; then
      echo "警告: Backlog.md のビルドに失敗したため、既存バイナリを使用します"
      cleanup_backlog_npm_shadow "$bin" "$bin_dir"
      return $?
    fi
    echo "エラー: Backlog.md のビルドに失敗しました"
    return 1
  fi

  if [ ! -f "$build_src_dir/dist/backlog" ]; then
    if [ "$managed_manifest" -eq 1 ]; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed build 成果物が見つかりません"
      return $?
    fi
    echo "エラー: Backlog.md のビルド成果物が見つかりません"
    return 1
  fi

  mkdir -p "$bin_dir"
  tmp_bin="$(mktemp "$bin_dir/.backlog.XXXXXX")"
  if ! cp "$build_src_dir/dist/backlog" "$tmp_bin" || ! chmod 755 "$tmp_bin" || ! "$tmp_bin" --version >/dev/null 2>&1; then
    rm -f "$tmp_bin"
    if [ "$managed_manifest" -eq 1 ]; then
      backlog_use_existing_binary "$bin" "$bin_dir" \
        "Backlog.md の managed build 成果物を検証できませんでした"
      return $?
    fi
    echo "エラー: Backlog.md バイナリの検証に失敗しました"
    return 1
  fi
  mv "$tmp_bin" "$bin"

  tmp_marker="$(mktemp "$(dirname "$marker")/.installed-commit.XXXXXX")"
  printf '%s\n' "$marker_expected" > "$tmp_marker"
  mv "$tmp_marker" "$marker"
  echo "更新:     Backlog.md ($build_sha)"

  cleanup_backlog_npm_shadow "$bin" "$bin_dir"
)
