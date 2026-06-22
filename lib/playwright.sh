#!/usr/bin/env bash
# Playwright browser binary setup for Codex/browser verification.

playwright_browser_cache_dir() {
  case "$(uname -s 2>/dev/null || printf unknown)" in
    Darwin)
      printf '%s\n' "$HOME/Library/Caches/ms-playwright"
      ;;
    *)
      printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/ms-playwright"
      ;;
  esac
}

ensure_playwright_chromium() {
  echo "--- Playwright Chromium ---"

  if ! command -v playwright &>/dev/null; then
    echo "エラー: playwright CLI が見つかりません。先に ./install.sh npm を実行してください"
    return 1
  fi

  local cache_dir
  cache_dir="$(playwright_browser_cache_dir)"
  mkdir -p "$cache_dir"

  echo "導入:     Chromium browser binary"
  PLAYWRIGHT_BROWSERS_PATH="$cache_dir" playwright install chromium
  echo "保存先:   $cache_dir"
  echo ""
}
