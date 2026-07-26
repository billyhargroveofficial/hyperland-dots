# SearXNG

Локальный backend для `mcp-searxng`, используемого Qwen Code и Grok Build.
Сервис слушает только `127.0.0.1:8888`, работает от системного пользователя
`searxng` и хранит код/venv в `/opt/searxng`.

```bash
sudo bash system/searxng/install.sh
curl -fsS http://127.0.0.1:8888/healthz
curl -fsS 'http://127.0.0.1:8888/search?q=test&format=json'
```

По умолчанию устанавливается проверенный commit, заданный в `install.sh`.
Осознанное обновление:

```bash
sudo SEARXNG_COMMIT=<commit> bash system/searxng/install.sh
```

Секрет генерируется локально в `/etc/searxng/secret.env` с правами `600` и в
Git не попадает.
