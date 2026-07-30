# Hermes Agent

Telegram-гейтвей на базе [Hermes Agent](https://github.com/NousResearch/hermes-agent)
(Nous Research), поднят как systemd user-сервис. Клон — в
`~/.local/share/hermes-agent`, профиль — в `~/.hermes/`.

В репозитории версионируются только юнит
(`.config/systemd/user/hermes-agent.service`) и обёртка (`.local/bin/hermes`).
`~/.hermes/config.yaml` сюда не кладётся: там chat_id и user_id Telegram, а
репозиторий публичный. Секреты — в `~/.hermes/.env`, тоже вне репозитория.
Общий bootstrap устанавливает юнит и обёртку, но код Hermes и приватный
профиль восстанавливаются этим ручным шагом.

## Установка

```sh
git clone https://github.com/NousResearch/hermes-agent ~/.local/share/hermes-agent
cd ~/.local/share/hermes-agent
uv sync --extra mcp --extra cli --inexact
systemctl --user enable --now hermes-agent.service
```

`--inexact` обязателен: без него `uv sync` сносит лениво доустановленные
пакеты вроде `python-telegram-bot`.

## Грабли, на которые ушло время

### MCP выключается молча

`mcp` — **опциональный extra** в `pyproject.toml`. Без него
`tools/mcp_tool.py` ставит `_MCP_AVAILABLE = False`, и вся MCP-подсистема
отключается без единой ошибки: `discover_mcp_tools()` возвращает пустой
список, серверы навсегда висят в статусе `configured`, в логе только
`DEBUG: mcp package not installed`. Агент при этом отвечает «у меня нет
инструментов», а `hermes doctor` на это не ругается.

Поэтому и юнит, и обёртка запускают `uv run` с `--extra mcp --extra cli`.

### systemd не наследует PATH

stdio-MCP (`chrome-devtools-mcp`, `gemini-search-mcp`) лежат в
`~/.local/bin`, которого нет в PATH юнита — серверы падают с
`FileNotFoundError`, и гейтвей уходит в Telegram без браузера и поиска.
Лечится строкой `Environment=PATH=...` в юните. HTTP-MCP (github, telegram)
этим не задеты.

`mcp_discovery_timeout` по умолчанию 1.5 с — мало на пять серверов, первый
промпт уходит без инструментов. В конфиге выставлено 20 с; join возвращается
по факту готовности, так что это только потолок.

Проверка живого состояния: `hermes mcp test <name>` по каждому серверу; под
гейтвеем должен висеть `mcp_stdio_watchdog.py` на каждый stdio-MCP.

### Провайдер и контекст

Модель `qwen3.8-max-preview` идёт через Alibaba Token Plan: провайдер —
**встроенный** `alibaba`, а endpoint переопределяется переменной
`DASHSCOPE_BASE_URL` на
`https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`.
Обычный `dashscope.aliyuncs.com` отдаёт 401. Тот же endpoint используют Qwen
Code и OpenCode.

Hermes **не разворачивает `${VAR}`** в `config.yaml` — где нужен секрет, туда
идёт значение или переменная окружения из `~/.hermes/.env`.

Контекст 1M сам не подхватывается: `/v1/models` у token-plan не отдаёт
`context_length`, а во встроенной таблице `agent/model_metadata.py` записи для
этой модели нет — резолвер сваливается на catch-all `qwen: 131072`. Нужны
`model.context_length` и per-model override в `custom_providers`.

Серверный веб-поиск DashScope (`enable_search`) на этом endpoint **не
работает** — проверено curl'ом, ответ приходит без `search_info`. Веб-поиск
идёт через `gemini-search` только в ручном конфиге Hermes; из rulesync
остальных харнессов он удалён 2026-07-30.

### Ложный варнинг про TERMINAL_CWD

Строка «`TERMINAL_CWD=… found in .env` — deprecated» при каждом старте — это
ложное срабатывание апстрима: `cli.py` сам пишет эту переменную в окружение
при восстановлении рабочего каталога сессии, а проверка затем принимает её за
запись из `.env`. В конфиге чинить нечего.

### Комментарии в config.yaml не живут

Любая команда, которая пишет конфиг программно (`hermes skin use`, `/model` и
подобные), переписывает `~/.hermes/config.yaml` целиком и вычищает все
комментарии. Значения при этом сохраняются.

## Состояние в tmux

Хуки Hermes для индикатора агентов — в `harness-hooks/` (события
`pre_llm_call` / `post_llm_call` / `pre_approval_request`, мост
`~/.config/tmux/hermes-agent-state.sh` и обязательный allowlist).
