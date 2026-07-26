# Общий control plane AI-харнессов

Один источник правды — `~/.config/agents/.rulesync/` — раскатывается во все
харнессы командой `mcp-sync`. Устройство описано в
[../CLAUDE.md](../CLAUDE.md) и `~/.config/agents/README.md`; здесь — как
убедиться, что оно **действительно** работает, и что при этом легко упустить.

## `mcp-sync --check` проверяет не всё

`--check` говорит только «файлы совпадают с тем, что сгенерировал бы sync». Он
не проверяет, что харнесс эти файлы читает, что сервис жив и что токен
подставится в рантайме. Полная проверка — ниже.

## Чек-лист живой системы

```bash
mcp-sync --check                       # дрейфа нет

# правила доехали во все харнессы (все файлы одного размера, кроме QWEN.md —
# у него свой заголовок)
ls -l ~/.claude/CLAUDE.md ~/.codex/AGENTS.md ~/.qwen/QWEN.md \
      ~/.kimi-code/AGENTS.md ~/.config/opencode/AGENTS.md ~/.grok/AGENTS.md

# MCP-серверы у каждого — пути РАЗНЫЕ, легко проверить не тот файл
#   claude    ~/.claude.json               kimi   ~/.kimi-code/mcp.json
#   codex     ~/.codex/config.toml         grok   ~/.grok/config.toml
#   qwen      ~/.qwen/settings.json        opencode ~/.config/opencode/opencode.json

systemctl --user is-active telegram-mcp qwen-serve qwen-channel-telegram

curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8765/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}'

curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1:8888/search?q=test&format=json'  # searxng
curl -s http://127.0.0.1:9222/json/version | head -3                                        # Chrome CDP
```

Состояние на 2026-07-26: всё перечисленное отвечает, Telegram MCP — 200 за 13 мс.

## Токен github берётся из ОКРУЖЕНИЯ, а не из конфига

Codex и Kimi получают его не значением, а именем переменной:

```toml
bearer_token_env_var = "GITHUB_PERSONAL_ACCESS_TOKEN"   # codex
```
```json
"bearerTokenEnvVar": "GITHUB_PERSONAL_ACCESS_TOKEN"     // kimi
```

Работает это ровно потому, что `.zshrc` подтягивает секреты:

```bash
[ -f "$HOME/.config/agents/secrets.env" ] && source "$HOME/.config/agents/secrets.env"
```

**Уберёшь эту строку — github MCP у codex и kimi молча перестанет
авторизовываться**, при том что `mcp-sync --check` останется зелёным. Проверка:

```bash
zsh -ic 'echo ${#GITHUB_PERSONAL_ACCESS_TOKEN}'   # должно быть 93
```

У Claude и Grok токен приезжает как `${GITHUB_PERSONAL_ACCESS_TOKEN}` внутри
заголовка `Authorization` — это намеренная runtime-ссылка, подставлять значение
руками нельзя.

## Кто какие серверы получает

| Сервер | Кому |
|---|---|
| `github`, `telegram`, `chrome-devtools` | всем шести |
| `searxng` | только `qwen` и `grok` (tool-scoped блоки в `mcp.jsonc`) |

Проверено: у claude/codex/kimi/opencode ровно три сервера, у qwen/grok — четыре.

## Qwen: только `httpUrl`, никогда `url`

Для streamable HTTP в `qwencode.mcpServers` обязателен ключ `httpUrl`. `url`
означает SSE, и подключение к Telegram MCP не поднимется.

## Target `cline` ничего не генерирует

В `rulesync.jsonc` есть `"cline": ["rules"]`, и rulesync на него отвечает
`✓ All files are up to date (rules)`. При этом файла правил в системе нет:
у cline правила project-scope (`.clinerules` в корне проекта), в global-режиме
ему писать некуда. Сам cline в системе не установлен.

Target безвреден, но пустой — не принимай его зелёный статус за доказательство,
что правила куда-то доехали. Появится cline — правила надо будет класть в
проект, а не в `$HOME`.

## Skills пока пусты

`~/.config/agents/.rulesync/skills/` содержит только `.gitkeep`, поэтому в
харнессах никаких общих skills нет — это ожидаемо, а не поломка. Появятся —
класть как `skills/<name>/SKILL.md`, дальше `mcp-sync` разложит сам.

## Права и утечки

`mcp-sync` в конце ставит `0600` на все чувствительные файлы
(`~/.claude.json`, `~/.codex/config.toml`, `~/.qwen/settings.json`,
`~/.kimi-code/mcp.json`, `~/.grok/config.toml`, `opencode.json`, `secrets.env`,
`*-service.env`). Проверено: реальных токенов в открытом виде в
сгенерированных конфигах нет — только имена переменных и `${...}`.

Перед коммитом стоит убедиться самому:

```bash
grep -lE 'gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}' \
  ~/.claude.json ~/.codex/config.toml ~/.qwen/settings.json \
  ~/.kimi-code/mcp.json ~/.grok/config.toml
```

## Бэкапы

Каждый прогон `mcp-sync` (кроме `--dry-run`/`--check`) складывает копии всех
нативных файлов в `~/.local/state/agents-sync/backups/<timestamp>/`, хранится
последние 10. Путь к последнему — в `~/.local/state/agents-sync/latest-backup`.
