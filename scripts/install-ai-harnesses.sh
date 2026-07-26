#!/usr/bin/env bash

set -euo pipefail

export PATH="$HOME/.local/bin:$HOME/.kimi-code/bin:$HOME/.opencode/bin:$PATH"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_SOURCE="$REPO_ROOT/.config/agents"
AGENTS_HOME="$HOME/.config/agents"
RULESYNC_VERSION="15.1.0"
CHROME_MCP_VERSION="1.6.0"
SEARXNG_MCP_VERSION="1.11.1"
TELEGRAM_MCP_COMMIT="78923cc736617b152ce8afa1c4089bf7c8ed56a9"
NO_NETWORK=false

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

install_sources() {
    info "Устанавливаю канонические rules, MCP и документацию"

    rm -rf "$AGENTS_HOME/.rulesync"
    mkdir -p "$AGENTS_HOME"
    cp -a "$AGENTS_SOURCE/.rulesync" "$AGENTS_HOME/.rulesync"
    install -m 644 "$AGENTS_SOURCE/rulesync.jsonc" "$AGENTS_HOME/rulesync.jsonc"
    install -m 644 "$AGENTS_SOURCE/README.md" "$AGENTS_HOME/README.md"
    install -m 644 \
        "$AGENTS_SOURCE/AUDIT-2026-07-26.md" \
        "$AGENTS_HOME/AUDIT-2026-07-26.md"

    install -Dm755 "$REPO_ROOT/.local/bin/mcp-sync" "$HOME/.local/bin/mcp-sync"
    install -Dm600 "$REPO_ROOT/.grok/config.toml" "$HOME/.grok/config.toml"

    local unit
    for unit in qwen-serve qwen-channel-telegram telegram-mcp; do
        install -Dm644 \
            "$REPO_ROOT/.config/systemd/user/$unit.service" \
            "$HOME/.config/systemd/user/$unit.service"
    done

    local chrome_flags
    chrome_flags="$(mktemp)"
    sed "s|@HOME@|$HOME|g" \
        "$REPO_ROOT/.config/chrome-flags.conf.template" > "$chrome_flags"
    install -Dm644 "$chrome_flags" "$HOME/.config/chrome-flags.conf"
    rm -f "$chrome_flags"
}

initialize_secrets() {
    local secrets_file="$AGENTS_HOME/secrets.env"
    local legacy_telegram_env="$HOME/.config/telegram-mcp.env"

    if [[ ! -f "$secrets_file" ]]; then
        install -m600 "$AGENTS_SOURCE/secrets.env.example" "$secrets_file"
        info "Создан локальный secrets.env"
    fi

    python3 - "$secrets_file" "$legacy_telegram_env" <<'PY'
import re
import secrets
import shlex
import sys
from pathlib import Path

target = Path(sys.argv[1])
legacy = Path(sys.argv[2])
names = {
    "TELEGRAM_API_ID",
    "TELEGRAM_API_HASH",
    "TELEGRAM_SESSION_STRING",
    "QWEN_SERVER_TOKEN",
}


def parse(path):
    values = {}
    if not path.exists():
        return values
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("export "):
            line = line[7:].lstrip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        name, raw_value = line.split("=", 1)
        try:
            parsed = shlex.split(raw_value, comments=True, posix=True)
        except ValueError:
            parsed = [raw_value.strip().strip("\"'")]
        values[name.strip()] = " ".join(parsed)
    return values


values = parse(target)
legacy_values = parse(legacy)
for name in names:
    if not values.get(name) and legacy_values.get(name):
        values[name] = legacy_values[name]
if not values.get("QWEN_SERVER_TOKEN"):
    values["QWEN_SERVER_TOKEN"] = secrets.token_urlsafe(48)

lines = target.read_text(encoding="utf-8").splitlines()
seen = set()
for index, line in enumerate(lines):
    match = re.match(r"^(\s*export\s+)?([A-Za-z_][A-Za-z0-9_]*)=", line)
    if not match:
        continue
    name = match.group(2)
    if name in values:
        lines[index] = f"export {name}={shlex.quote(values[name])}"
        seen.add(name)
for name in sorted(names - seen):
    lines.append(f"export {name}={shlex.quote(values.get(name, ''))}")

target.write_text("\n".join(lines) + "\n", encoding="utf-8")
target.chmod(0o600)
PY

    rm -f "$legacy_telegram_env"
}

install_dependencies() {
    if $NO_NETWORK; then
        info "Пропускаю сетевую установку зависимостей"
        return
    fi

    info "Устанавливаю Rulesync и stdio MCP в пользовательский npm-prefix"
    npm install --global --prefix "$HOME/.local" --ignore-scripts \
        "rulesync@$RULESYNC_VERSION"
    npm install --global --prefix "$HOME/.local" \
        "chrome-devtools-mcp@$CHROME_MCP_VERSION" \
        "mcp-searxng@$SEARXNG_MCP_VERSION"

    local telegram_dir="$HOME/.local/share/telegram-mcp"
    if [[ ! -d "$telegram_dir/.git" ]]; then
        if [[ -e "$telegram_dir" ]]; then
            warn "$telegram_dir существует, но это не Git checkout; Telegram MCP пропущен"
            return
        fi
        git clone https://github.com/chigwell/telegram-mcp.git "$telegram_dir"
    fi

    if [[ -z "$(git -C "$telegram_dir" status --porcelain)" ]]; then
        git -C "$telegram_dir" fetch origin "$TELEGRAM_MCP_COMMIT"
        git -C "$telegram_dir" checkout --detach "$TELEGRAM_MCP_COMMIT"
    else
        warn "Telegram MCP имеет локальные изменения; checkout сохранён как есть"
    fi

    if command -v uv >/dev/null 2>&1; then
        (cd "$telegram_dir" && uv sync --frozen --no-dev)
    else
        warn "uv не найден: Telegram MCP не синхронизирован"
    fi
}

generate_native_configs() {
    if ! command -v rulesync >/dev/null 2>&1; then
        echo "rulesync не найден в PATH; проверь ~/.local/bin" >&2
        exit 1
    fi

    info "Генерирую нативные конфиги харнессов"
    "$HOME/.local/bin/mcp-sync"

    systemctl --user daemon-reload
    systemctl --user try-restart \
        telegram-mcp.service \
        qwen-serve.service \
        qwen-channel-telegram.service || true
}

report() {
    local missing=()
    local command_name
    for command_name in claude codex qwen kimi opencode grok; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    if (( ${#missing[@]} )); then
        warn "Не установлены vendor CLI: ${missing[*]}"
    fi

    if curl -fsS --max-time 3 http://127.0.0.1:8888/healthz >/dev/null 2>&1; then
        info "SearXNG backend доступен на 127.0.0.1:8888"
    else
        warn "SearXNG backend не отвечает; установи system/searxng"
    fi

    info "Готово. Заполни $AGENTS_HOME/secrets.env и снова выполни mcp-sync"
    printf '%s\n' \
        "Для автозапуска:" \
        "  systemctl --user enable --now telegram-mcp.service qwen-serve.service" \
        "  systemctl --user enable --now qwen-channel-telegram.service"
}

install_sources
initialize_secrets
install_dependencies
generate_native_configs
report
