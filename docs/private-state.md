# Приватное и runtime-состояние

Репозиторий публичный и намеренно не является полным бэкапом домашнего
каталога. После восстановления dotfiles отдельно нужны секреты, ключи и
состояние программ.

## Что бэкапить отдельно

- `~/.config/agents/secrets.env` — токены MCP и Telegram API credentials;
- `~/.ssh/` — приватные ключи, `known_hosts` и параметры хостов;
- `~/.hermes/` — профиль, сессии и приватный runtime Hermes;
- `~/.agents/memory/` — общая долговременная память AI-харнессов;
- `~/.config/sing-box/config.json` — рабочая конфигурация VPN;
- `~/wallpapers/` — коллекция обоев и файл, на который ссылается
  `~/.cache/current_wallpaper`;
- vendor OAuth/session caches Claude, Codex, Kimi, OpenCode, Pi и Qwen;
- Telegram session string и локальные сессии клиентов.

Хранить это следует в зашифрованном бэкапе вне машины. В Git не добавлять даже
в приватную ветку этого репозитория: история и форки переживают последующее
удаление файла.

## После восстановления

1. Вернуть `~/.ssh/` с правами `0700` на каталог и `0600` на приватные ключи.
2. Вернуть `~/.config/agents/secrets.env` с правами `0600`.
3. Выполнить `mcp-sync --dry-run`, `mcp-sync`, затем `mcp-sync --check`.
4. Вернуть `~/.hermes/` и код Hermes по инструкции
   [`hermes-agent.md`](hermes-agent.md).
5. Проверить `telegram-mcp.service`, `hermes-agent.service` и
   `mujik-ssh-tunnel.service`.

Обратный туннель использует публичный ключ к `root@nareshka.ru` и удалённый
loopback-порт `2223`. Если порт уже держит старая живая сессия, локальный
wrapper не перезапускается в цикле: ждёт освобождения порта и подключается
самостоятельно.
