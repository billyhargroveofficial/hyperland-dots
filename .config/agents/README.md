# Единая система AI-харнессов

`~/.config/agents/` — пользовательский control plane для правил, MCP, skills,
общей курируемой памяти и секретов. Генератор — Rulesync, а `mcp-sync` остаётся
стабильной пользовательской командой.

Версионируемый источник находится в `~/hyperland-dots/.config/agents/`.
Установка или обновление без полного восстановления системы:

```bash
cd ~/hyperland-dots
./scripts/install-ai-harnesses.sh
```

## Источники

- `.rulesync/rules/*.md` — общие инструкции и курируемая память.
- `.rulesync/mcp.jsonc` — общие и tool-scoped MCP-серверы.
- `.rulesync/skills/<name>/SKILL.md` — переносимые skills.
- `rulesync.jsonc` — список харнессов и включённых возможностей.
- `secrets.env` — локальные runtime-секреты, права `600`, не хранится в Git.
- `qwen-service.env` — генерируемое окружение user-systemd сервисов Qwen.
- `telegram-service.env` — генерируемое окружение общего Telegram MCP.

Совместимые пути `AGENTS.md`, `mcp.json` и `skills/` являются ссылками на
источники в `.rulesync/`.

## Генерируемые харнессы

| Target Rulesync | Нативные правила | MCP | Skills |
| --- | --- | --- | --- |
| `claudecode` | `~/.claude/CLAUDE.md` | `~/.claude.json` | `~/.claude/skills/` |
| `codexcli` | `~/.codex/AGENTS.md` | `~/.codex/config.toml` | `~/.agents/skills/` |
| `qwencode` | `~/.qwen/QWEN.md` | `~/.qwen/settings.json` | `~/.qwen/skills/` |
| `kimi-code` | `~/.kimi-code/AGENTS.md` | `~/.kimi-code/mcp.json` | `~/.kimi-code/skills/` |
| `opencode` | `~/.config/opencode/AGENTS.md` | OpenCode config | `~/.config/opencode/skills/` |
| `grokcli` | `~/.grok/AGENTS.md` | `~/.grok/config.toml` | `~/.grok/skills/` |
| `cline` | `~/.agents/AGENTS.md` | — | — |

Общий стандартный файл находится в `~/.agents/AGENTS.md`. `~/AGENTS.md`
намеренно не создаётся: в домашнем каталоге он дублирует нативные user-scope
правила Codex и Grok. Старый `~/.kimi/AGENTS.md` указывает на актуальный Kimi
Code файл.

## Повседневное использование

```bash
mcp-sync --dry-run
mcp-sync
mcp-sync --check
mcp-sync --list-targets
```

- `--skip-mcp` — генерировать только rules и skills.
- `--skip-links` — генерировать только MCP.
- `--servers` удалён: частные серверы задаются tool-scoped блоками.

Перед каждой записью создаётся снимок затрагиваемых файлов в
`~/.local/state/agents-sync/backups/`; сохраняются последние десять.

## Backup и rollback

- Путь к последнему ротационному снимку:
  `~/.local/state/agents-sync/latest-backup`.
- Полный снимок до первой миграции на исходной машине:
  `~/.local/state/agents-sync/migration-backups/20260726-152335/home-state.tar`.
- Перед полным откатом остановить активные харнессы и проверить архив через
  `tar -tf <archive>`.

## MCP

Общий сервер добавляется в `mcpServers`. Сервер только для конкретного харнесса
добавляется в `<target>.mcpServers`:

```jsonc
{
  "mcpServers": {
    "shared": {
      "type": "http",
      "url": "https://example.com/mcp"
    }
  },
  "qwencode": {
    "mcpServers": {
      "qwen-only": {
        "type": "stdio",
        "command": "example-mcp"
      },
      "shared": null
    }
  }
}
```

`${VAR}` остаётся runtime-ссылкой. Qwen, Grok, Claude и OpenCode разворачивают
её нативно; Codex и Kimi получают свои нативные поля для bearer token.

Локальный `searxng` подключён tool-scoped только к Qwen и Grok. Команда
`mcp-searxng` ожидает backend на `http://127.0.0.1:8888`; его установка лежит в
`~/hyperland-dots/system/searxng/`.

`mcp-sync` атомарно создаёт отдельные `qwen-service.env` и
`telegram-service.env` с минимальным набором переменных. После изменения
секретов выполни:

```bash
mcp-sync
systemctl --user restart qwen-serve.service qwen-channel-telegram.service telegram-mcp.service
```

## Skills и память

Skill хранится каталогом:

```text
.rulesync/skills/my-skill/
└── SKILL.md
```

В `SKILL.md` обязательны frontmatter-поля `name` и `description`. Rulesync
адаптирует один источник под нативные каталоги выбранных харнессов.

Общая долговременная память — раздел в корневом правиле
`.rulesync/rules/overview.md`. Один root-файл выбран намеренно: Kimi Code и Grok
Build игнорируют дополнительные user-scope rule-файлы. Нативная автоматическая
память, sessions, OAuth cache и история остаются runtime-состоянием.

## Новый сторонний харнесс

1. Найти target в документации Rulesync.
2. Добавить target и поддерживаемые features в `rulesync.jsonc`.
3. При необходимости добавить tool-scoped MCP или target во frontmatter.
4. Запустить `mcp-sync --dry-run`, затем `mcp-sync`.
5. Проверить результат нативной командой харнесса.

Если Rulesync ещё не знает инструмент, временный post-generation adapter можно
добавить рядом с `mcp-sync`, не возвращаясь к монолитному преобразователю.

## Grok Build

В `~/.grok/config.toml` настроены:

- `kimi-k3` и `kimi-k3-256k` через Kimi Coding Plan;
- `qwen-token-plan` и `qwen-max-token-plan` через Alibaba/Qwen Token Plan;
- GitHub, Telegram, Chrome DevTools и SearXNG MCP;
- постоянный `ui.yolo = true`.

Ключи берутся из `KIMI_CODING_API_KEY` и
`BAILIAN_TOKEN_PLAN_API_KEY` в `secrets.env`; токены в TOML не записываются.

## Обновление

Проверенные версии фиксируются в `scripts/install-ai-harnesses.sh`. После
изменения версии запусти bootstrap и полный `mcp-sync --check`.
