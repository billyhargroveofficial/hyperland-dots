---
root: true
targets: ["*"]
description: "Общие пользовательские инструкции для AI-харнессов"
---

# Общие инструкции

Это единый набор пользовательских правил для Claude Code, Codex CLI, Kimi Code,
OpenCode и Qwen Code.

Канонические источники находятся в `~/.config/agents/.rulesync/`. Нативные
`AGENTS.md`, `CLAUDE.md`, MCP-конфиги и каталоги skills генерирует
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

## Общая память харнессов

- Общая кросс-харнесс память: `~/.agents/memory/` — индекс `MEMORY.md` и записи
  `entries/<ГГГГ-ММ>-<слаг>.md`.
- Читать индекс, когда задача касается этой машины, харнессов, их конфигов или
  ранее принятых решений; открывать саму запись только по релевантности.
- Писать туда только устойчивые проверенные факты, полезные любому харнессу.
  Секреты, токены и эфемерный контекст сессии — нельзя.
- Новая запись — файл в `entries/` плюс одна строка в `MEMORY.md`. Ошибочную
  запись исправлять или удалять, а не дублировать.
- Раздел «Общая долговременная память» этого файла — для немногих фактов,
  которые должны быть в контексте всегда. Всё, что растёт в объёме, идёт в
  `~/.agents/memory/`.
- Нативные памяти харнессов (`~/.claude/projects/*/memory`, `~/.qwen/memories`
  и подобные) в общую память не сливать: форматы несовместимы.

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
  `~/.config/opencode/AGENTS.md`, `~/.agents/AGENTS.md`,
  `telegram-service.env` и управляемые MCP-блоки: следующий sync их заменит.
- Общий MCP добавлять в `mcpServers`; исключение или сервер одного клиента —
  в `<rulesync-target>.mcpServers`.
- Новый поддерживаемый харнесс добавлять target-ом в `rulesync.jsonc`, а не
  новым hardcoded преобразователем внутри `mcp-sync`.
- `${VAR}` в generated configs — намеренная runtime-ссылка. Значения брать из
  `secrets.env`; не подставлять токены вручную в vendor-конфиги.
- После изменения `secrets.env` выполнить `mcp-sync`; для общего Telegram MCP
  перезапустить `telegram-mcp.service`.
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
- Активные харнессы (все пять под управлением канона): Claude Code, Codex CLI,
  Kimi Code, OpenCode, Qwen Code. Codex CLI и Kimi Code возвращены в систему
  2026-07-28; Grok Build и Qwen-демоны остаются выведенными с 2026-07-26.
- Общая память харнессов: `~/.agents/memory/`, поднята 2026-07-28.
- Веб-поиск для всех харнессов: MCP-сервер `gemini-search`
  (`mcp-gemini-google-search`) через Vertex AI grounding, модель
  `gemini-3.6-flash`, локация обязательно `global`. Авторизация — ADC, без
  JSON-ключей. Подробности — в `~/.agents/memory/`.
- Веб-поиск ровно один на все харнессы — `gemini-search`. Ни SearXNG, ни
  `open-websearch` больше не используются и обратно не заводятся.
- В общую память попадают только устойчивые, проверенные факты.
