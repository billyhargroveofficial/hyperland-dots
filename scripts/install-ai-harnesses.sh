#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_SOURCE="$REPO_ROOT/.config/agents"
INSTALL_HOME="${AI_INSTALL_HOME:-$HOME}"
AGENTS_HOME="${AGENTS_HOME:-$INSTALL_HOME/.config/agents}"
RULESYNC_VERSION="15.1.0"
NO_NETWORK=false

export PATH="$INSTALL_HOME/.local/bin:$PATH"

if [[ "${1:-}" == "--no-network" ]]; then
    NO_NETWORK=true
elif [[ $# -gt 0 ]]; then
    echo "Использование: $0 [--no-network]" >&2
    exit 2
fi

info() { printf '\033[0;32m[AI]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[AI WARN]\033[0m %s\n' "$*" >&2; }

if [[ $EUID -eq 0 ]]; then
    echo "Не запускай этот скрипт от root." >&2
    exit 1
fi

install_file_if_missing() {
    local source="$1" target="$2" mode="$3"
    if [[ -e "$target" || -L "$target" ]]; then
        info "Сохраняю существующий $target"
        return
    fi
    install -Dm"$mode" "$source" "$target"
    info "Создан $target"
}

install_template() {
    info "Инициализирую нейтральный AI control plane"
    mkdir -p "$AGENTS_HOME/.rulesync/rules" "$AGENTS_HOME/.rulesync/skills"

    install_file_if_missing \
        "$AGENTS_SOURCE/rulesync.jsonc" "$AGENTS_HOME/rulesync.jsonc" 644
    install_file_if_missing \
        "$AGENTS_SOURCE/README.md" "$AGENTS_HOME/README.md" 644
    install_file_if_missing \
        "$AGENTS_SOURCE/.rulesync/mcp.jsonc" \
        "$AGENTS_HOME/.rulesync/mcp.jsonc" 644
    install_file_if_missing \
        "$AGENTS_SOURCE/.rulesync/rules/overview.md" \
        "$AGENTS_HOME/.rulesync/rules/overview.md" 644
    install_file_if_missing \
        "$AGENTS_SOURCE/secrets.env.example" "$AGENTS_HOME/secrets.env" 600
    install_file_if_missing \
        "$REPO_ROOT/.local/bin/mcp-sync" "$INSTALL_HOME/.local/bin/mcp-sync" 755
}

install_rulesync() {
    if command -v rulesync >/dev/null 2>&1; then
        info "Rulesync уже установлен"
    elif $NO_NETWORK; then
        warn "Rulesync не найден; с --no-network установка пропущена"
    else
        info "Устанавливаю Rulesync в пользовательский npm-prefix"
        npm install --global --prefix "$INSTALL_HOME/.local" --ignore-scripts \
            "rulesync@$RULESYNC_VERSION"
    fi
}

report() {
    info "Шаблон готов; локальные харнессы и их конфиги не изменялись"
    if [[ -x "$INSTALL_HOME/.local/bin/mcp-sync" ]]; then
        printf 'Локальные targets:\n'
        AGENTS_HOME="$AGENTS_HOME" \
            "$INSTALL_HOME/.local/bin/mcp-sync" --list-targets \
            || warn "Не удалось прочитать локальный rulesync.jsonc"
    fi
    printf '%s\n' \
        "Дальше настрой локальные targets и MCP в $AGENTS_HOME," \
        "затем выполни: mcp-sync --dry-run && mcp-sync && mcp-sync --check"
}

install_template
install_rulesync
report
