if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git fzf z docker history)
source $ZSH/oh-my-zsh.sh
# Arch plugins (НЕ oh-my-zsh)
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
# Basic exports
export PATH="$HOME/.local/bin:$PATH"
# OpenCode намеренно доступен через ~/.local/bin/opencode; не фильтровать.
# Удаляем устаревшие каталоги выведенных AI-харнессов из унаследованного PATH.
path=(${path:#$HOME/.grok/bin})
path=(${path:#$HOME/.kimi-code/bin})
export EDITOR='nvim'
export VISUAL='nvim'

# Tool replacements
alias cat='bat'
alias ls='eza --icons --group-directories-first'
alias l='eza --icons --group-directories-first'

# Basic functions
c() { clear }
f() { fd . | fzf }
fa() { fd . --no-ignore --hidden | fzf }
v() { nvim $(fd . | fzf) }
va() { nvim $(fd . --no-ignore --hidden | fzf) }
yy() { yazi }
cdf() { cd $(fd --type d | fzf) }
cdfa() { cd $(fd --type d --no-ignore --hidden | fzf) }
cdh() { cd $HOME }
hh() { fc -ln 1 | fzf --tac | sh }

# FZF integration
pf() { ps -ef | fzf }
rgp() { rg --line-number . | fzf --delimiter ':' --preview 'bat --color=always --highlight-line {2} {1}' }
gfzf() { git log --oneline | fzf }
gbf() { git checkout $(git branch | fzf | sed 's/^[ *]*//') }
ef() { env | fzf }
myip() { curl ipinfo.io }

# Git aliases
alias gs='git status'
gadd() { git add "$@" }
gcom() { git commit -m "$@" }
alias gp='git push'
alias gl='git pull'
alias gd='git diff'

# NPM
ni() { npm install "$@" }
nid() { npm install --save-dev "$@" }
nr() { npm run "$@" }
alias nrs='npm run start'
alias nrd='npm run dev'
alias nrb='npm run build'

# Poetry
alias pl='poetry lock'
# `poi` — короткий алиас для poetry install.
alias poi='poetry install'
pr() { poetry run "$@" }
alias pm='poetry run python main.py'

# Clipboard
alias clip='wl-paste'
copy() { echo "$@" | wl-copy }

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
~() { cd $HOME }

# Cleanup
clean-node() { rm -rf node_modules }
clean-logs() { rm -f *.log }
clean-temp() {
  local tmpdir="${TMPDIR:-/tmp}"
  # Только собственные обычные файлы старше недели. Каталоги, сокеты и чужое
  # runtime-состояние не трогаем: прежний `rm -rf /tmp/*` ломал живые процессы.
  find "$tmpdir" -mindepth 1 -maxdepth 1 -user "$USER" -type f -mtime +7 -print -delete
}

# Disk space
alias df='df -h'
alias du='du -h'
alias disk='df -h | grep -E "^/dev|Filesystem"'
alias space='du -sh * 2>/dev/null | sort -hr | head -20'

# Sing-box traffic monitor
alias vpn-log='tail -f ~/.local/share/singbox-traffic.log'
alias vpn-traffic='tail -f ~/.local/share/singbox-traffic.log | grep -E "proxy|direct" --color=auto'

# History with fzf insertion
hhf() { 
  local cmd=$(fc -ln 1 | fzf --tac --no-sort)
  [[ -n "$cmd" ]] && print -z "$cmd"
}

# Key bindings
bindkey -s '^e' 'nvim .\n'
bindkey -s '^g' 'lazygit\n'

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# bun completions
[ -s "$HOME/.bun/_bun" ] && source "$HOME/.bun/_bun"

# bun
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Lazy conda - загружается только при первом вызове
conda() {
  if [[ ! -r /opt/miniconda3/etc/profile.d/conda.sh ]]; then
    print -u2 "conda: /opt/miniconda3 не установлен"
    return 127
  fi
  unfunction conda
  source /opt/miniconda3/etc/profile.d/conda.sh
  conda "$@"
}


# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

# Яркость внешних мониторов по DDC/CI (см. ~/.config/hypr/scripts/brightness.sh)
# Значение выставляется сразу на все подключённые экраны.
#   bright 50   выставить 50%      bright up / bright down   шаг 5%
#   bright      показать текущую
bright() {
    local s=~/.config/hypr/scripts/brightness.sh d
    case "${1:-}" in
        # command cat, а не cat: он заалиасен на bat, а тот спотыкается о
        # симлинк /sys/class/backlight/ddcciN и печатает ошибку вместо числа
        ""|show)
            # (N) — nullglob: без подсветок молчим, а не ругаемся на no matches
            for d in /sys/class/backlight/ddcci*(N); do
                print -r -- "${d:t}: $(command cat $d/brightness 2>/dev/null)%"
            done ;;
        up|down) "$s" "$1" ;;
        *)       "$s" set "$1" ;;
    esac
}

# Секреты Codex и Telegram (файл не входит в dotfiles).
[ -f "$HOME/.config/codex/secrets.env" ] && source "$HOME/.config/codex/secrets.env"

# billytelega использует другие имена тех же Telegram API credentials.
# Значения остаются только в secrets.env и никогда не попадают в Git.
export TG_API_ID="${TELEGRAM_API_ID:-}"
export TG_API_HASH="${TELEGRAM_API_HASH:-}"
