# Хуки харнессов для индикатора агентов в tmux

Фрагменты конфигов, благодаря которым вкладка tmux показывает **состояние**
агента, а не только факт запуска. Рисует их `~/.config/tmux/agent-win.sh`,
состояние принимает плагин
[`accessd/tmux-agent-indicator`](https://github.com/accessd/tmux-agent-indicator).

Сами конфиги харнессов целиком не версионируются (там ключи, OAuth и
сгенерированные каноном секции), поэтому здесь лежат только вставки.

## Кто откуда получает хуки

| Харнесс | Куда | Как ставится |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `install.sh` плагина |
| Codex | `~/.codex/hooks.json` | `install.sh` плагина |
| OpenCode | `~/.config/opencode/plugins/opencode-tmux-agent-indicator.js` | `install.sh` плагина |
| Qwen Code | `~/.qwen/settings.json` | вручную — `qwen-hooks.json` |
| Kimi Code | `~/.kimi-code/config.toml` | вручную — `kimi-hooks.toml` |
| Hermes | `~/.hermes/config.yaml` | вручную — `hermes-hooks.yaml` |

Первые три ставятся так (из каталога плагина, обязательно из **другой**
директории — установщик копирует сам себя в целевую и падает, если это одно и
то же место):

```sh
cp -a ~/.tmux/plugins/tmux-agent-indicator /tmp/tai-src
cd /tmp/tai-src && TMUX_AGENT_INSTALL_DIR="$HOME/.tmux/plugins/tmux-agent-indicator" ./install.sh
```

**Осторожно:** установщик заодно подменяет `statusLine` в
`~/.claude/settings.json` своей обёрткой ради `#{agent_limits}`. Если он не
нужен — вернуть команду обратно на `cship-wrap` (старая сохраняется в base64
внутри новой). Проверять после каждого обновления плагина.

## Ручные вставки

- **Qwen** — влить объект `hooks` из `qwen-hooks.json` в
  `~/.qwen/settings.json` (верхний уровень). `mcp-sync` эту секцию не трогает:
  канон замещает только `mcpServers`.
- **Kimi** — дописать `kimi-hooks.toml` в конец `~/.kimi-code/config.toml`
  (`[[hooks]]` — массив таблиц, в конце файла безопасно). Проверить:
  `kimi doctor`.
- **Hermes** — дописать `hermes-hooks.yaml` в конец `~/.hermes/config.yaml` и
  положить `hermes-shell-hooks-allowlist.json` как
  `~/.hermes/shell-hooks-allowlist.json`. Без allowlist хуки молча
  пропускаются; статус видно в `hermes hooks list` (должно быть `✓ allowed`).
  Мост `~/.config/tmux/hermes-agent-state.sh` обязателен: Hermes запускает
  команду через `shlex.split` без shell и читает stdout как JSON.

## Проверка

```sh
hermes hooks list                 # все пять должны быть "✓ allowed"
kimi doctor                       # config.toml valid
```

Дальше — запустить агента в панели tmux и отправить промпт: вкладка должна
пройти `○` → зелёная `●` (работает) → синяя `✓` (готово), а на запросе
подтверждения показать жёлтый `▲`.
