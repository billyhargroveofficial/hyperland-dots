#!/bin/bash

# Файл для хранения состояния
STATE_FILE="/tmp/redsocks_toggle_state"
LOG_FILE="$HOME/.local/share/redsocks.log"

# Создаём директорию для логов
mkdir -p "$(dirname "$LOG_FILE")"

die() {
    command -v notify-send >/dev/null 2>&1 && notify-send "redsocks" "$1" -i dialog-error
    echo "$1" >&2
    exit 1
}

# Предполётная проверка. Скрипт висит на биндe Alt+I, у которого нет tty:
# без этих проверок sudo молча уходил ждать пароль в никуда, и нажатие
# выглядело как «ничего не произошло».
command -v redsocks >/dev/null 2>&1 || die "redsocks не установлен (pacman -S redsocks)"
[[ -f /etc/redsocks.conf ]]          || die "нет /etc/redsocks.conf"
# sudoers разрешает без пароля только nvidia-settings и sing-box; iptables и
# redsocks сюда не входят, поэтому проверяем заранее и не даём скрипту зависнуть.
sudo -n true 2>/dev/null || die "нужен sudo без пароля для iptables/redsocks"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

start_redsocks() {
    log "=== START REDSOCKS ==="

    log "Flushing iptables nat..."
    sudo iptables -t nat -F 2>&1 | tee -a "$LOG_FILE"

    log "Killing existing redsocks..."
    sudo pkill redsocks 2>&1 | tee -a "$LOG_FILE"

    log "Starting redsocks daemon..."
    sudo redsocks -c /etc/redsocks.conf &
    REDSOCKS_PID=$!
    log "Redsocks started with PID: $REDSOCKS_PID"

    sleep 1

    # Проверяем что redsocks запустился
    if pgrep -x redsocks > /dev/null; then
        log "Redsocks is running (PID: $(pgrep -x redsocks))"
    else
        log "ERROR: Redsocks failed to start!"
        echo 0 > "$STATE_FILE"
        return 1
    fi

    log "Setting up iptables rules..."
    sudo iptables -t nat -N REDSOCKS 2>/dev/null
    sudo iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
    sudo iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports 12345
    sudo iptables -t nat -A OUTPUT -p tcp -m owner ! --uid-owner 0 -j REDSOCKS

    log "iptables rules applied"
    echo 1 > "$STATE_FILE"
    log "State set to ON"
}

stop_redsocks() {
    log "=== STOP REDSOCKS ==="

    log "Flushing iptables nat..."
    sudo iptables -t nat -F 2>&1 | tee -a "$LOG_FILE"

    log "Killing redsocks..."
    sudo pkill redsocks 2>&1 | tee -a "$LOG_FILE"

    echo 0 > "$STATE_FILE"
    log "State set to OFF"
}

check_status() {
    log "--- STATUS CHECK ---"
    if pgrep -x redsocks > /dev/null; then
        log "Redsocks is running (PID: $(pgrep -x redsocks))"
    else
        log "Redsocks is NOT running"
        if [[ -f "$STATE_FILE" && $(cat "$STATE_FILE") == "1" ]]; then
            log "WARNING: State file says ON but redsocks is not running!"
        fi
    fi
}

# Проверяем состояние
if [[ -f "$STATE_FILE" && $(cat "$STATE_FILE") == "1" ]]; then
    stop_redsocks
else
    start_redsocks
fi

check_status

# Обновляем waybar
pkill -SIGRTMIN+8 waybar 2>/dev/null || true 
