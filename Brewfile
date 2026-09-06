cask_args appdir: "/Applications"

# === 非公式 tap ===
# Homebrew 公式に無い macOS アプリ用の tap
# cask の追加・更新は dotfiles 側の pkg-add / cask-update skill で行う
tap 'u-ichi/tap'
tap 'manaflow-ai/cmux'
tap 'terraform-linters/tap'

# === CLI: クラウド・インフラ ===
brew 'awscli'
brew 'aws-sam-cli'
brew 'cloudflared'
brew 'gitleaks'
brew 'infracost'
brew 'tfenv'
brew 'trivy'

# === CLI: 開発ツール ===
brew 'bash'
brew 'bun'
brew 'cargo-nextest'
brew 'direnv'
brew 'docker-compose'
brew 'fish'
brew 'fzf'
brew 'ffmpeg'
brew 'gh'
brew 'git'
brew 'git-lfs'
brew 'googleworkspace-cli'
brew 'gradle'
brew 'just'
brew 'kotlin'
brew 'mkcert'
brew 'neovim'
# Playwright の import 可能な Node.js package は Npmfile で管理する。
# Homebrew 側は実行基盤の node を管理する（`playwright` formula は存在しない）。
brew 'node'
brew 'nodenv'
brew 'pnpm'
brew 'poppler'
brew 'ripgrep'
brew 'rust'
brew 'shellcheck'
brew 'shfmt'
brew 'sqlite'
brew 'taplo'
brew 'uv'
brew 'yq'
brew 'zig@0.15'

# === CLI: システム・ユーティリティ ===
brew 'blueutil'
brew 'glow'
brew 'gtop'
# herdr は公式 installer 管理 (install.sh 参照)。Homebrew formula は
# `herdr update --handoff` (live handoff 更新) の対象外のため brew では入れない。
brew 'htop'
brew 'ollama'
brew 'pstree'
brew 'terminal-notifier'
brew 'tmux'
brew 'wget'

# === GUI: 開発 ===
cask 'codex'
cask 'codex-app'
cask 'cursor'
cask 'docker-desktop'
cask 'ghostty'
cask 'github'
cask 'session-manager-plugin'
cask 'visual-studio-code'
cask 'gcloud-cli'
cask 'terraform-linters/tap/tflint'

# === GUI: ブラウザ・コミュニケーション ===
cask 'google-chrome'
cask 'discord'
cask 'microsoft-teams'
cask 'slack'
cask 'zoom'

# === GUI: AI ===
cask 'claude'
cask 'chatgpt'
cask 'cmux'
cask 'hermes-desktop'

# === GUI: 生産性 ===
cask 'google-drive'
cask 'libreoffice'
cask 'microsoft-office'
cask 'notion'
cask 'notion-calendar'
cask 'notion-mail'
cask 'obsidian'
cask 'raycast'

# === GUI: システム・ユーティリティ ===
cask '1password'
cask 'alt-tab'
cask 'aws-vpn-client'
cask 'atok'
cask 'applite'
# betterdisplaycli は cask が同梱するバイナリを配置する
cask 'betterdisplay'
cask 'bitwarden'
cask 'caffeine'
cask 'istat-menus'
cask 'karabiner-elements'
# 通知バナー位置変更アプリ。公式 1.4.0 は macOS 26.4.1 必須のため、現行 26.3 で動く
# sk0gen フォーク (個人 tap で管理) を使用。非 notarize のため初回起動時に
# システム設定 > プライバシーとセキュリティで「このまま開く」が必要
cask 'u-ichi/tap/pingplace'
cask 'tailscale-app'

# === GUI: その他 ===
cask 'bambu-studio'
cask 'u-ichi/tap/tolaria'

# === フォント ===
cask 'font-hackgen'
cask 'font-hackgen-nerd'
cask 'font-moralerspace'
cask 'font-moralerspace-hw'
cask 'font-noto-sans-jp'
