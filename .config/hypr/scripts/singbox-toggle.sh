#!/bin/bash

# sing-box VPN toggle script
LOG_FILE="$HOME/.local/share/singbox.log"
STATE_FILE="/tmp/singbox_state"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

if pgrep -x sing-box > /dev/null; then
    # Выключаем
    sudo pkill sing-box
    rm -f "$STATE_FILE"
    log "sing-box stopped"
    notify-send "sing-box" "VPN выключен" -i network-offline
else
    # Включаем
    log "Starting sing-box..."
    sudo sing-box run -D ~/.config/sing-box -c ~/.config/sing-box/config.json >> "$LOG_FILE" 2>&1 &
    sleep 2

    if pgrep -x sing-box > /dev/null; then
        echo "1" > "$STATE_FILE"
        log "sing-box started successfully"
        notify-send "sing-box" "VPN включён" -i network-vpn
    else
        log "ERROR: Failed to start sing-box"
        notify-send "sing-box" "Ошибка запуска!" -i dialog-error
    fi
fi
