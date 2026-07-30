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
      ~/.kimi-code/AGENTS.md ~/.config/opencode/AGENTS.md

# MCP-серверы у каждого — пути РАЗНЫЕ, легко проверить не тот файл
#   claude    ~/.claude.json               kimi   ~/.kimi-code/mcp.json
#   codex     ~/.codex/config.toml         opencode ~/.config/opencode/opencode.json
#   qwen      ~/.qwen/settings.json

# нативные проверки подключения (единственное, что доказывает живость)
claude mcp list ; qwen mcp list ; codex mcp list ; opencode mcp list ; kimi doctor

systemctl --user is-active telegram-mcp

curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8765/mcp \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"c","version":"1"}}}'

curl -s http://127.0.0.1:9222/json/version | head -3                                        # Chrome CDP
```

Состояние на 2026-07-30: пять нативных MCP-клиентов получают четыре сервера
`github`, `telegram`, `chrome-devtools`, `brave-devtools`; Pi читает тот же
набор через адаптер. Старые Qwen user-демоны не нужны и удалены. Telegram MCP
отвечает локально по HTTP.

## Pi: MCP приходит расширением, а не каноном

У Pi нативного MCP нет — авторы отказались от него намеренно. Его добавляет
расширение `pi-mcp-adapter`, и оно же снимает главную боль: агент видит **один**
прокси-инструмент (~200 токенов) вместо 223 определений, а сервер подключается
лениво, при первом вызове. Поиск по инструментам — `mcp({ search: "..." })`.

Адаптер читает стандартный `mcpServers` и сам разворачивает `${VAR}`, поэтому
`~/.pi/agent/mcp.json` — симлинк прямо на канон
(`~/.config/agents/.rulesync/mcp.jsonc`). Никакой генерации: правки канона
видны Pi сразу. В `rulesync.jsonc` у target `pi` только `rules` и `skills` —
фичи `mcp` там не существует, и это не недосмотр.

Проверка: `pi -p 'вызови mcp с {"search":"telegram"}'`.

Модели Pi берёт из `~/.pi/agent/models.json`. Для Alibaba Token Plan нужны два
compat-флага, иначе endpoint отвечает 400: `supportsDeveloperRole: false`
(роль `developer` он не знает) и `supportsReasoningEffort: false`; мышление
включается через `thinkingFormat: "qwen"`, у glm-5.2 — `"zai"`.

Команда `pi` конфликтовала с алиасом `poetry install` — тот переименован в
`poi`.

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
zsh -ic 'test -n "$GITHUB_PERSONAL_ACCESS_TOKEN" && echo present'
```

У Claude, Qwen и OpenCode токен приезжает как `${GITHUB_PERSONAL_ACCESS_TOKEN}`
внутри заголовка `Authorization` — это намеренная runtime-ссылка, подставлять
значение руками нельзя.

## Codex не отдаёт MCP-серверу родительское окружение

Самая дорогая грабля этой системы. Codex запускает stdio MCP-сервер **только с
тем окружением, что перечислено в `[mcp_servers.<имя>.env]`** — ничего из шелла
не наследуется. Проверено прямо: сервер падал с

```text
Error: VERTEX_PROJECT_ID environment variable is required when using Vertex AI
```

при том что переменная в шелле была. Kimi вдобавок не разворачивает `${VAR}`.
Диагностика — только через лог, снаружи это выглядит как «инструмента нет»:

```bash
RUST_LOG=info codex exec --skip-git-repo-check "привет" 2>&1 | grep 'MCP server stderr'
```

Вывод: **на наследование окружения полагаться нельзя**. Если серверу нужна
переменная, а нативного поля вроде `bearer_token_env_var` нет — заворачивать
запуск в скрипт. Сохранённый только для ручного конфига Hermes
[`gemini-search-mcp`](../.local/bin/gemini-search-mcp) собирает окружение сам.
В rulesync основных харнессов его больше нет. Проверять обёртку надо с пустым
окружением, иначе тест ничего не доказывает:

```bash
env -i HOME="$HOME" gemini-search-mcp </dev/null    # должен написать "running on stdio"
```

## Codex прячет MCP-инструменты за tool_search

У codex 0.146 MCP-инструменты отложенные: в списке у модели их нет, пока она не
вызовет `tool_search`. Модель при этом охотно врёт, что инструмент недоступен, и
даже выдумывает текст ошибки. Не принимай её слова за диагностику — смотри
`codex mcp list` и лог. В `codex exec` вызов ещё и упрётся в апрув: для разовой
проверки нужен `--dangerously-bypass-approvals-and-sandbox`.

## gemini-search остался только у Hermes

С 2026-07-30 сервер удалён из rulesync шести основных харнессов. Ручной конфиг
Hermes продолжает использовать Vertex AI grounding. Авторизация — Application
Default Credentials, локация `global`.

```bash
gcloud auth application-default print-access-token | cut -c1-10   # ya29.…
```

В rulesync его не восстанавливать без явного решения владельца.

## Кто какие серверы получает

| Сервер | Кому |
|---|---|
| `github`, `telegram`, `chrome-devtools`, `brave-devtools` | пяти нативным MCP-клиентам и Pi через адаптер |
| `gemini-search` | только Hermes, ручной конфиг вне Rulesync |

Проверено 2026-07-30: у основных харнессов ровно четыре shared-сервера.
`open-websearch`, SearXNG и `gemini-search` обратно в rulesync не заводить.

## Qwen: только `httpUrl`, никогда `url`

Для streamable HTTP в `qwencode.mcpServers` обязателен ключ `httpUrl`. `url`
означает SSE, и подключение к Telegram MCP не поднимется.

## Зелёный статус target-а ещё не значит, что файл появился

Rulesync отвечает `✓ All files are up to date` и на target, которому в
global-режиме писать некуда. Так было с `cline` (правила у него project-scope) и
так же ведёт себя `agentsmd`: он умеет только project scope и в user-режиме
честно пишет `Target 'agentsmd' supports the feature 'rules' only in project
scope. Skipping.` Поэтому вендор-нейтральный `~/.agents/AGENTS.md` — не
генерируемый файл, а симлинк на `~/.codex/AGENTS.md`, который ставит `mcp-sync`
(список `COMPAT_LINKS`).

Итог: не принимай зелёный статус за доказательство, что правила куда-то доехали.
Смотри сами файлы.

## Skills пока пусты

`~/.config/agents/.rulesync/skills/` содержит только `.gitkeep`, поэтому в
харнессах никаких общих skills нет — это ожидаемо, а не поломка. Появятся —
класть как `skills/<name>/SKILL.md`, дальше `mcp-sync` разложит сам.

## Права и утечки

`mcp-sync` в конце ставит `0600` на все чувствительные файлы
(`~/.claude.json`, `~/.codex/config.toml`, `~/.qwen/settings.json`,
`~/.kimi-code/mcp.json`, `opencode.json`, `secrets.env`,
`telegram-service.env`).
Проверено: реальных токенов в открытом виде в сгенерированных конфигах нет —
только имена переменных и `${...}`.

Отдельно помни, что **`hyperland-dots` — публичный репозиторий**, а
`.config/agents/**` в него коммитится. Значение секрета в канон не пишется
никогда: только `${VAR}`, нативное поле с именем переменной или обёртка.

Перед коммитом стоит убедиться самому:

```bash
grep -lE 'gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}' \
  ~/.claude.json ~/.codex/config.toml ~/.qwen/settings.json \
  ~/.kimi-code/mcp.json

# ⚠ legacy от старого kimi-cli, живой PAT открытым текстом, под mcp-sync не ходит
grep -c 'github_pat_' ~/.kimi/mcp.json 2>/dev/null
```

## Бэкапы

Каждый прогон `mcp-sync` (кроме `--dry-run`/`--check`) складывает копии всех
нативных файлов в `~/.local/state/agents-sync/backups/<timestamp>/`, хранится
последние 10. Путь к последнему — в `~/.local/state/agents-sync/latest-backup`.
