fish_add_path /opt/homebrew/bin ~/.local/bin

# SSH 経由では接続元の Ghostty TERM が渡るが、接続先に terminfo が無い場合がある。
# tmux は起動前の TERM を参照するため、未知なら広く入っている xterm-256color に落とす。
if test "$TERM" = xterm-ghostty; and begin; set -q SSH_CONNECTION; or set -q SSH_TTY; end
    if not command -q infocmp; or not infocmp "$TERM" >/dev/null 2>&1
        set -gx TERM xterm-256color
    end
end

# mkcert のルート CA を Node.js に信頼させる（ctxledger MCP 等の自己署名証明書用）
set -gx NODE_EXTRA_CA_CERTS "$HOME/Library/Application Support/mkcert/rootCA.pem"

if status is-interactive
    # bobthefish: git リポジトリ内ではプロジェクトルートより上の親パスを非表示
    set -g theme_show_project_parent no
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
