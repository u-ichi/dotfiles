fish_add_path /opt/homebrew/bin ~/.local/bin

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
