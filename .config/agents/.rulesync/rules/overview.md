---
root: true
targets: ["*"]
description: "Общие пользовательские инструкции для AI-харнессов"
---

# Общие инструкции

Это единый набор пользовательских правил для Claude Code, Codex CLI, Qwen Code,
Kimi Code, OpenCode, Grok Build и совместимых сторонних харнессов.

Канонические источники находятся в `~/.config/agents/.rulesync/`. Нативные
`AGENTS.md`, `CLAUDE.md`, `QWEN.md`, MCP-конфиги и каталоги skills генерирует
`mcp-sync`; их не следует редактировать вручную.

## Обо мне

- ОС: Arch Linux, Hyprland, zsh.
- Язык общения: русский.

## Соглашения

- Постоянные общие правила добавлять в этот файл или отдельным файлом в
  `~/.config/agents/.rulesync/rules/`.
- Проверенные долговременные факты, полезные всем харнессам, добавлять в раздел
  «Общая долговременная память» этого файла; автоматическую runtime-memory
  каждого харнесса не синхронизировать.

## Система AI-харнессов

- Control plane находится в `~/.config/agents/`.
- Единственные канонические источники:
  - `.rulesync/rules/` — общие инструкции;
  - `.rulesync/mcp.jsonc` — shared и tool-scoped MCP;
  - `.rulesync/skills/` — общие Agent Skills;
  - `rulesync.jsonc` — список харнессов и включённых features;
  - `secrets.env` — секреты и API keys.
- `mcp-sync` — единственная команда применения. Перед изменением использовать
  `mcp-sync --dry-run`, после изменения — `mcp-sync`, для проверки —
  `mcp-sync --check`.
- Не редактировать сгенерированные `~/.claude/CLAUDE.md`,
  `~/.codex/AGENTS.md`, `~/.qwen/QWEN.md`, `~/.kimi-code/AGENTS.md`,
  `~/.config/opencode/AGENTS.md`, `~/.grok/AGENTS.md`,
  `~/.agents/AGENTS.md`, `qwen-service.env`, `telegram-service.env` и
  управляемые MCP-блоки: следующий sync их заменит.
- Общий MCP добавлять в `mcpServers`; исключение или сервер одного клиента —
  в `<rulesync-target>.mcpServers`. Для Qwen streamable HTTP обязательно
  использовать `httpUrl` в `qwencode.mcpServers`, а не `url` (это SSE).
- Новый поддерживаемый харнесс добавлять target-ом в `rulesync.jsonc`, а не
  новым hardcoded преобразователем внутри `mcp-sync`.
- `${VAR}` в generated configs — намеренная runtime-ссылка. Значения брать из
  `secrets.env`; не подставлять токены вручную в vendor-конфиги.
- После изменения `secrets.env` выполнить `mcp-sync`; для уже запущенных Qwen
  daemon/channel затем перезапустить `qwen-serve.service` и
  `qwen-channel-telegram.service`, а для общего Telegram MCP —
  `telegram-mcp.service`.
- Общие skills хранить только как
  `.rulesync/skills/<name>/SKILL.md`.
- Нативная auto-memory, sessions, OAuth cache и история каждого харнесса —
  runtime-состояние; их нельзя зеркалить между клиентами как dotfiles.
- Полная эксплуатационная документация: `~/.config/agents/README.md`.
- Аудит и принятые решения:
  `~/.config/agents/AUDIT-2026-07-26.md`.

## Общая долговременная память

- Единый источник правил, MCP и skills: `~/.config/agents/.rulesync/`.
- Версионируемый источник и bootstrap: `~/hyperland-dots/.config/agents/` и
  `~/hyperland-dots/scripts/install-ai-harnesses.sh`.
- Синхронизация выполняется командой `mcp-sync`.
- Telegram MCP работает одним общим systemd user-сервисом
  `telegram-mcp.service` на `http://127.0.0.1:8765/mcp`; не переводить его
  обратно в отдельные stdio-процессы.
- SearXNG на `http://127.0.0.1:8888` подключён только к Qwen и Grok.
- В Grok постоянно включены `ui.yolo = true` и
  `permission_mode = "always-approve"` по явному решению владельца.
- В общую память попадают только устойчивые, проверенные факты.
