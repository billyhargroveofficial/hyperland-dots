#!/bin/bash
# Привязывает ddcci к тем i2c-шинам, на которых реально сидит монитор.
#
# Зачем скрипт, а не просто modprobe: начиная с ядра 6.8 авто-проба дисплеев в
# драйвере отключена (в dmesg: "Auto-probing of displays is not available on
# kernel 6.8 and later"), устройство нужно создавать вручную через new_device.
# Номер шины между загрузками не фиксирован — зависит от порядка инициализации
# видеокарты, поэтому перебираем все и пробуем каждую. Промахи безвредны:
# ядро просто не создаст устройство там, где никто не отвечает по 0x37.

set -u

modprobe i2c-dev 2>/dev/null
modprobe ddcci-backlight 2>/dev/null

# Даём видеодрайверу поднять i2c-адаптеры
for _ in $(seq 20); do
    [ -n "$(ls -d /sys/bus/i2c/devices/i2c-* 2>/dev/null)" ] && break
    sleep 0.5
done

bound=0
for bus in /sys/bus/i2c/devices/i2c-*; do
    [ -w "$bus/new_device" ] || continue
    # 0x37 — стандартный адрес DDC/CI. Уже привязанные шины отсекаем, иначе
    # ядро ругается в лог на повторное создание.
    busnum=${bus##*i2c-}
    [ -e "/sys/bus/i2c/devices/${busnum}-0037" ] && continue
    echo "ddcci 0x37" > "$bus/new_device" 2>/dev/null && bound=$((bound + 1))
done

sleep 2
count=$(ls -1 /sys/class/backlight/ 2>/dev/null | grep -c '^ddcci' || true)
echo "ddcci-bind: попыток привязки $bound, устройств подсветки $count"
[ "$count" -gt 0 ]
