# Herdr の vendored libghostty-vt は Zig 0.15.2 固定。versioned formula は keg-only のため明示する。
fish_add_path /opt/homebrew/opt/zig@0.15/bin /opt/homebrew/bin ~/.local/bin

# SSH 経由では接続元の Ghostty TERM が渡るが、接続先に terminfo が無い場合がある。
# tmux は起動前の TERM を参照するため、未知なら広く入っている xterm-256color に落とす。
if test "$TERM" = xterm-ghostty; and begin; set -q SSH_CONNECTION; or set -q SSH_TTY; end
    if not command -q infocmp; or not infocmp "$TERM" >/dev/null 2>&1
        set -gx TERM xterm-256color
    end
end

# mkcert のルート CA を Node.js に信頼させる（ctxledger MCP 等の自己署名証明書用）
set -gx NODE_EXTRA_CA_CERTS "$HOME/Library/Application Support/mkcert/rootCA.pem"

# Codex / Playwright のブラウザバイナリ cache を host 側の固定場所に揃える。
set -gx PLAYWRIGHT_BROWSERS_PATH "$HOME/Library/Caches/ms-playwright"

if status is-interactive
    # ~/agent/projects 配下の repo は、任意の場所からディレクトリ名だけで cd できるようにする。
    # CDPATH は fish 標準の cd 補完にも使われる。
    set -l agent_projects "$HOME/agent/projects"
    if test -d "$agent_projects"; and not contains -- "$agent_projects" $CDPATH
        set -gx CDPATH $CDPATH "$agent_projects"
    end

    # bobthefish: git リポジトリ内ではプロジェクトルートより上の親パスを非表示
    set -g theme_show_project_parent no

    # bobthefish: SSH 接続時に既定で出る user@host (例: u1@u1mac) を抑止。
    # 以前は universal 変数で隠していたが fish 4.3 の universal→global 移行で失われたため、
    # config に明示してマシン非依存に固定する。
    set -g theme_display_hostname no
    set -g theme_display_user no

    # pane / 端末タイトル: bobthefish 既定の fish_title は prompt_pwd
    # (~/L/C/.../dotfiles のように親ディレクトリを 1 文字へ省略) を OSC タイトルに出すため、
    # tmux の window タブや端末タイトルに無駄な省略パスが並ぶ。カレントの basename のみを
    # 出して簡潔にする (window 名自体は tmux の rename-windows.sh が別途管理)。
    function fish_title
        if test "$PWD" = "$HOME"
            echo '~'
        else
            basename -- "$PWD"
        end
    end
end


# Git
alias g='git'
alias gb='git branch'
alias gc='git commit'
alias gco='git checkout'
alias ga='git add'
alias gp='git push'
alias gl='git log'
alias gs='git status'

# Fish
alias hs='history search'

# Directory
alias l='ll'

# Neovim
alias vi='nvim'
alias vim='nvim'
