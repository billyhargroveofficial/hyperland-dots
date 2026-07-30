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
- `telegram-service.env` — генерируемое окружение общего Telegram MCP.

Совместимые пути `AGENTS.md`, `mcp.json` и `skills/` являются ссылками на
источники в `.rulesync/`.

## Генерируемые харнессы

Под управлением шесть харнессов:

| Target Rulesync | Нативные правила | MCP | Skills |
| --- | --- | --- | --- |
| `claudecode` | `~/.claude/CLAUDE.md` | `~/.claude.json` | `~/.claude/skills/` |
| `codexcli` | `~/.codex/AGENTS.md` | `~/.codex/config.toml` | `~/.agents/skills/` |
| `qwencode` | `~/.qwen/QWEN.md` | `~/.qwen/settings.json` | `~/.qwen/skills/` |
| `kimi-code` | `~/.kimi-code/AGENTS.md` | `~/.kimi-code/mcp.json` | `~/.kimi-code/skills/` |
| `opencode` | `~/.config/opencode/AGENTS.md` | OpenCode config | `~/.config/opencode/skills/` |
| `pi` | `~/.pi/agent/AGENTS.md` | через `pi-mcp-adapter` | `~/.pi/agent/skills/` |

Общий стандартный файл находится в `~/.agents/AGENTS.md`. `~/AGENTS.md`
намеренно не создаётся: в домашнем каталоге он дублирует нативные user-scope
правила Codex. Старый `~/.kimi/AGENTS.md` указывает на актуальный Kimi
Code файл; всё остальное в `~/.kimi/` — legacy от kimi-cli, живой конфиг лежит
в `~/.kimi-code/`.

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

### Подстановка секретов

`${VAR}` остаётся runtime-ссылкой: Rulesync записывает её в конфиги как есть,
значение подставляет сам харнесс. Разворачивают нативно только Claude, Qwen и
OpenCode. **Codex и Kimi подстановки не разворачивают, а Codex вдобавок вообще
не отдаёт stdio MCP-серверу родительское окружение** — проверено, сервер
падает с `VERTEX_PROJECT_ID environment variable is required`. Наследование из
шелла для них не работает, рассчитывать на него нельзя.

Отсюда два рабочих приёма — значение секрета в канон не пишется никогда, канон
уезжает в публичный репозиторий:

- **Нативное поле для имени переменной**, если харнесс его поддерживает:
  `bearer_token_env_var` (Codex) и `bearerTokenEnvVar` (Kimi) вместо заголовка
  `Authorization` у GitHub. Задаётся tool-scoped блоками.
- **Обёртка-скрипт**, если поля нет. Так устроен сохранённый для Hermes
  `gemini-search-mcp`: он сам подтягивает `secrets.env` и экспортирует нужное.
  В rulesync шести основных харнессов этот сервер с 2026-07-30 отключён.

Обёртка предпочтительнее tool-scoped костылей: один файл вместо блока на
каждый харнесс, и канон остаётся читаемым.

### Qwen и remote-серверы

Qwen Code трактует `url` как устаревший SSE, а streamable HTTP берёт только из
`httpUrl`. Rulesync 15.1.0 пишет ему `url` — upstream-баг, симптом узнаваемый:
все remote-серверы disconnected, все stdio connected. Обход — блок
`qwencode.mcpServers` с `httpUrl`. Если Rulesync это починит, блок можно убрать.

### Веб-поиск

`gemini-search` отключён в rulesync шести основных харнессов 2026-07-30.
Обёртка и зависимость сохранены только для отдельного ручного конфига Hermes.
Авторизация там — ADC, без JSON-ключей:

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project "$VERTEX_PROJECT_ID"
gcloud auth application-default print-access-token   # проверка
```

В rulesync не восстанавливать его без явного решения владельца.

`mcp-sync` атомарно создаёт `telegram-service.env` с минимальным набором
переменных. Qwen Code остаётся активным CLI-харнессом, но его старые
`qwen-serve`/`qwen-channel-telegram` user-демоны выведены из эксплуатации.
После изменения секретов выполни:

```bash
mcp-sync
systemctl --user restart telegram-mcp.service
```

## Skills и память

Skill хранится каталогом:

```text
.rulesync/skills/my-skill/
└── SKILL.md
```

В `SKILL.md` обязательны frontmatter-поля `name` и `description`. Rulesync
адаптирует один источник под нативные каталоги выбранных харнессов.

Память разделена на два уровня.

Первый — раздел «Общая долговременная память» в корневом правиле
`.rulesync/rules/overview.md`: он всегда в контексте у всех харнессов, поэтому
туда идут только те несколько фактов, которые нужны постоянно. Один root-файл
выбран намеренно: Kimi Code игнорирует дополнительные user-scope rule-файлы.

Второй — общая кросс-харнесс память `~/.agents/memory/`: индекс `MEMORY.md` и
записи `entries/<ГГГГ-ММ>-<слаг>.md`. Читается по релевантности, а не всегда,
поэтому растёт без раздувания контекста. Протокол работы с ней описан в том же
корневом правиле, так что его видит каждый харнесс. Каталог не версионируется:
это личная накопленная память машины, как и `secrets.env`.

Нативная автоматическая память харнессов, sessions, OAuth cache и история
остаются runtime-состоянием и между клиентами не зеркалятся.

Для Codex CLI `mcp-sync` после генерации постоянно обеспечивает YOLO mode:
`approval_policy = "never"` и `sandbox_mode = "danger-full-access"`. Это
осознанное решение владельца; Codex запускает команды без подтверждений и без
sandbox.

## Новый сторонний харнесс

1. Найти target в документации Rulesync.
2. Добавить target и поддерживаемые features в `rulesync.jsonc`.
3. При необходимости добавить tool-scoped MCP или target во frontmatter.
4. Запустить `mcp-sync --dry-run`, затем `mcp-sync`.
5. Проверить результат нативной командой харнесса.

Если Rulesync ещё не знает инструмент, временный post-generation adapter можно
добавить рядом с `mcp-sync`, не возвращаясь к монолитному преобразователю.

## Grok Build — вне системы

Grok выведен из эксплуатации 2026-07-26 и не является target-ом Rulesync:
канон до него не доезжает, bootstrap его не устанавливает. Версионируемый
`.grok/config.toml` оставлен только как заготовка на случай явного возврата.

В заготовке настроены:

- `kimi-k3` и `kimi-k3-256k` через Kimi Coding Plan;
- `qwen-token-plan` и `qwen-max-token-plan` через Alibaba/Qwen Token Plan;
- GitHub, Telegram, Chrome DevTools и SearXNG MCP;
- постоянный `ui.yolo = true`.

Ключи берутся из `KIMI_CODING_API_KEY` и
`BAILIAN_TOKEN_PLAN_API_KEY` в `secrets.env`; токены в TOML не записываются.

## Обновление

Проверенные версии фиксируются в `scripts/install-ai-harnesses.sh`. После
изменения версии запусти bootstrap и полный `mcp-sync --check`.
