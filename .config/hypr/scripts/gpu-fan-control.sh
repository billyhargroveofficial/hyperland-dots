#!/bin/bash

# GPU Fan Control Script with Dynamic Fan Curve
# Использует XWayland для управления вентиляторами в Hyprland

LOG_FILE="$HOME/.local/share/gpu-fan.log"
INTERVAL=5  # Интервал проверки температуры (секунды)

# Кривая вентилятора: температура -> скорость
TEMP_MIN=35   # При этой температуре и ниже - минимальная скорость
TEMP_MAX=85   # При этой температуре и выше - максимальная скорость
FAN_MIN=40    # Минимальная скорость вентилятора (%)
FAN_MAX=100   # Максимальная скорость вентилятора (%)

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Дисплей XWayland НЕ прибит к :0 — Hyprland поднимает его на первом свободном
# номере, здесь это :1. Раньше тут стояло DISPLAY=:0 и nvidia-settings молча
# падал каждые 5 секунд ("Failed to set fan speed" в логе). Ищем реальный сокет.
XDISPLAY=""
detect_display() {
    local d
    for d in "$DISPLAY" $(ls /tmp/.X11-unix/X* 2>/dev/null | sed 's|.*/X|:|'); do
        [[ -n "$d" ]] || continue
        if DISPLAY="$d" xhost > /dev/null 2>&1; then
            XDISPLAY="$d"
            return 0
        fi
    done
    return 1
}

set_fan_speed() {
    local speed=$1
    [[ -n "$XDISPLAY" ]] || detect_display || { log "ERROR: XWayland display not found"; return 1; }

    DISPLAY="$XDISPLAY" xhost si:localuser:root > /dev/null 2>&1
    DISPLAY="$XDISPLAY" sudo -n /usr/bin/nvidia-settings -a "[gpu:0]/GPUFanControlState=1" \
        -a "[fan:0]/GPUTargetFanSpeed=$speed" \
        -a "[fan:1]/GPUTargetFanSpeed=$speed" > /dev/null 2>&1
    local result=$?
    DISPLAY="$XDISPLAY" xhost -si:localuser:root > /dev/null 2>&1

    # Дисплей мог смениться (перезапуск XWayland) — сбросим кэш и попробуем ещё раз
    if (( result != 0 )); then
        XDISPLAY=""
        detect_display || return 1
        DISPLAY="$XDISPLAY" xhost si:localuser:root > /dev/null 2>&1
        DISPLAY="$XDISPLAY" sudo -n /usr/bin/nvidia-settings -a "[gpu:0]/GPUFanControlState=1" \
            -a "[fan:0]/GPUTargetFanSpeed=$speed" \
            -a "[fan:1]/GPUTargetFanSpeed=$speed" > /dev/null 2>&1
        result=$?
        DISPLAY="$XDISPLAY" xhost -si:localuser:root > /dev/null 2>&1
    fi
    return $result
}

get_temp() {
    nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null
}

calculate_fan_speed() {
    local temp=$1

    if (( temp <= TEMP_MIN )); then
        echo $FAN_MIN
    elif (( temp >= TEMP_MAX )); then
        echo $FAN_MAX
    else
        # Квадратичная кривая (прогиб вниз - дольше тихо, резче к концу)
        local range_temp=$((TEMP_MAX - TEMP_MIN))
        local range_fan=$((FAN_MAX - FAN_MIN))
        local offset=$((temp - TEMP_MIN))
        # normalized^2 даёт выпуклую кривую
        local speed=$(awk "BEGIN {
            n = $offset / $range_temp;
            curved = n * n;
            printf \"%.0f\", $FAN_MIN + curved * $range_fan
        }")
        echo $speed
    fi
}

log "=== GPU Fan Control Started ==="
log "Fan curve: ${FAN_MIN}% at ${TEMP_MIN}°C -> ${FAN_MAX}% at ${TEMP_MAX}°C"

# Даем время XWayland запуститься
sleep 3

LAST_SPEED=0
LAST_CHANGE_TS=0
MIN_CHANGE_INTERVAL=60  # секунд между реальными изменениями оборотов

while true; do
    TEMP=$(get_temp)

    if [[ -z "$TEMP" ]]; then
        log "ERROR: Cannot read GPU temperature"
        sleep $INTERVAL
        continue
    fi

    TARGET_SPEED=$(calculate_fan_speed $TEMP)

    # Гистерезис. Порог был 3%, и это ровно амплитуда автоколебания: вентилятор
    # охлаждал GPU до 48°C -> кривая просила 44% -> нагрев до 52°C -> 47% -> по
    # кругу, каждые 10-30 секунд. Каждое срабатывание — nvidia-settings через
    # NV-CONTROL в ЖИВОЙ XWayland, ~53 мс с остановкой драйвера, то есть
    # видимый фриз рабочего стола. 8% шире любого нормального дребезга, плюс
    # холодный старт по времени на случай медленного дрейфа температуры.
    DIFF=$((TARGET_SPEED - LAST_SPEED))
    DIFF=${DIFF#-}
    NOW=$(date +%s)
    COOLDOWN_OK=$(( NOW - LAST_CHANGE_TS >= MIN_CHANGE_INTERVAL ))

    if (( LAST_SPEED == 0 )) || ( (( DIFF >= 8 )) && (( COOLDOWN_OK )) ); then
        if set_fan_speed $TARGET_SPEED; then
            log "Temp: ${TEMP}°C -> Fan: ${TARGET_SPEED}%"
            LAST_SPEED=$TARGET_SPEED
            LAST_CHANGE_TS=$NOW
        else
            log "ERROR: Failed to set fan speed"
        fi
    fi

    sleep $INTERVAL
done
