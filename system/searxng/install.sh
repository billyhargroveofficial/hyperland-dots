#!/usr/bin/env bash

set -euo pipefail

STAGE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARXNG_COMMIT="${SEARXNG_COMMIT:-0909dbc9efb2c6e93e2ad51e60e66417ab291710}"
PYTHON_VERSION="${SEARXNG_PYTHON_VERSION:-3.13}"
SOURCE_DIR="/opt/searxng/searxng-src"
VENV_DIR="/opt/searxng/venv"
CALLER_USER="${SUDO_USER:-}"
CALLER_HOME=""

say() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ $(id -u) -ne 0 ]]; then
    echo "Нужен root: sudo bash $0" >&2
    exit 1
fi

if [[ -n "$CALLER_USER" ]]; then
    CALLER_HOME="$(getent passwd "$CALLER_USER" | cut -d: -f6)"
fi

UV="$(command -v uv 2>/dev/null || true)"
if [[ -z "$UV" && -n "$CALLER_HOME" && -x "$CALLER_HOME/.local/bin/uv" ]]; then
    UV="$CALLER_HOME/.local/bin/uv"
fi
if [[ -z "$UV" ]]; then
    echo "uv не найден; установи пакет uv или пользовательский бинарь" >&2
    exit 1
fi

if [[ ! -f "$STAGE/searxng.service" || ! -f "$STAGE/settings.yml" ]]; then
    echo "Рядом со скриптом нужны searxng.service и settings.yml" >&2
    exit 1
fi

say "Отключаю старый user-scope SearXNG"
if [[ -n "$CALLER_USER" && -d "/run/user/$(id -u "$CALLER_USER")" ]]; then
    caller_uid="$(id -u "$CALLER_USER")"
    runuser -u "$CALLER_USER" -- \
        env XDG_RUNTIME_DIR="/run/user/$caller_uid" \
        systemctl --user disable --now searxng.service 2>/dev/null || true
    rm -f "$CALLER_HOME/.config/systemd/user/searxng.service"
    runuser -u "$CALLER_USER" -- \
        env XDG_RUNTIME_DIR="/run/user/$caller_uid" \
        systemctl --user daemon-reload 2>/dev/null || true
fi
systemctl stop searxng.service 2>/dev/null || true

say "Создаю системного пользователя searxng"
if ! getent passwd searxng >/dev/null; then
    useradd --system --no-create-home --home-dir /opt/searxng \
        --shell /usr/bin/nologin \
        --comment "SearXNG metasearch daemon" searxng
fi

say "Устанавливаю pinned SearXNG $SEARXNG_COMMIT"
mkdir -p /opt/searxng
if [[ ! -d "$SOURCE_DIR/.git" ]]; then
    rm -rf "$SOURCE_DIR"
    git clone https://github.com/searxng/searxng "$SOURCE_DIR"
fi
git -c "safe.directory=$SOURCE_DIR" -C "$SOURCE_DIR" \
    fetch --depth 1 origin "$SEARXNG_COMMIT"
git -c "safe.directory=$SOURCE_DIR" -C "$SOURCE_DIR" \
    checkout --detach --force "$SEARXNG_COMMIT"

say "Создаю самодостаточный Python $PYTHON_VERSION и venv"
export HOME=/root
export UV_PYTHON_INSTALL_DIR=/opt/searxng/python
export UV_CACHE_DIR=/tmp/uv-cache-searxng
"$UV" python install "$PYTHON_VERSION"
"$UV" venv --clear --python "$PYTHON_VERSION" "$VENV_DIR"

say "Устанавливаю зависимости"
cd "$SOURCE_DIR"
"$UV" pip install --python "$VENV_DIR/bin/python" \
    -r requirements.txt -r requirements-server.txt setuptools wheel
"$UV" pip install --python "$VENV_DIR/bin/python" \
    --no-build-isolation -e "$SOURCE_DIR"
"$VENV_DIR/bin/python" -m compileall -q "$SOURCE_DIR/searx" \
    >/dev/null 2>&1 || true
rm -rf "$UV_CACHE_DIR"

chown -R searxng:searxng /opt/searxng
chmod 755 /opt/searxng

say "Устанавливаю конфигурацию"
mkdir -p /etc/searxng
install -o root -g searxng -m640 \
    "$STAGE/settings.yml" /etc/searxng/settings.yml
if [[ ! -f /etc/searxng/secret.env ]]; then
    printf 'SEARXNG_SECRET=%s\n' "$(openssl rand -hex 32)" \
        > /etc/searxng/secret.env
fi
chown root:root /etc/searxng/secret.env
chmod 600 /etc/searxng/secret.env

install -o root -g root -m644 \
    "$STAGE/searxng.service" /etc/systemd/system/searxng.service
systemd-analyze verify /etc/systemd/system/searxng.service
systemctl daemon-reload
systemctl enable --now searxng.service

say "Проверяю backend"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    if curl -fsS --max-time 5 http://127.0.0.1:8888/healthz \
        >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
curl -fsS --max-time 5 http://127.0.0.1:8888/healthz >/dev/null
curl -fsS --max-time 30 \
    "http://127.0.0.1:8888/search?q=test&format=json" \
    | python3 -c \
        'import json, sys; print(len(json.load(sys.stdin).get("results", [])), "результатов")'
systemctl --no-pager --lines=0 status searxng.service
