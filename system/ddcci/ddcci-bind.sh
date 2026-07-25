#!/bin/bash
# Привязывает ddcci к i2c-шинам видеокарты, на которых сидит монитор.
#
# Зачем скрипт, а не просто modprobe: начиная с ядра 6.8 авто-проба дисплеев в
# драйвере отключена (в dmesg: "Auto-probing of displays is not available on
# kernel 6.8 and later"), устройство нужно создавать вручную через new_device.
# Номер шины между загрузками не фиксирован — зависит от порядка инициализации
# видеокарты, поэтому перебираем все её шины и пробуем каждую.
#
# Бьём ТОЛЬКО по шинам видеокарты (их родитель — PCI-устройство карты из
# /sys/class/drm/card*/device). Слать 0x37 во все подряд нельзя: на SMBus-шинах
# чипсета живут SPD-EEPROM модулей памяти, и мусорные клиенты там остаются
# висеть (следы прошлой версии скрипта: /sys/bus/i2c/devices/4-0036, 4-0037).
#
# Ретраи нужны потому, что юнит стартует раньше, чем видеодрайвер поднимет свои
# i2c-адаптеры: ждём до DEADLINE секунд.

set -u

DEADLINE=60

modprobe i2c-dev 2>/dev/null
modprobe ddcci-backlight 2>/dev/null

have_backlight() {
    ls -d /sys/class/backlight/ddcci* >/dev/null 2>&1
}

# Номера i2c-шин, принадлежащих видеокартам
gpu_buses() {
    local card gpu bus
    for card in /sys/class/drm/card*; do
        [ -e "$card/device" ] || continue
        gpu=$(readlink -f "$card/device")
        for bus in /sys/bus/i2c/devices/i2c-*; do
            case "$(readlink -f "$bus")" in
                "$gpu"/*) echo "${bus##*/i2c-}" ;;
            esac
        done
    done | sort -un
}

# 0x37 — стандартный адрес DDC/CI. Промахи безвредны: там, где никто не
# отвечает, драйвер не привяжется. Уже привязанные шины отсекаем, иначе ядро
# ругается в лог на повторное создание.
bind_bus() {
    local n=$1
    [ -e "/sys/bus/i2c/devices/${n}-0037" ] && return 1
    [ -w "/sys/bus/i2c/devices/i2c-${n}/new_device" ] || return 1
    echo "ddcci 0x37" > "/sys/bus/i2c/devices/i2c-${n}/new_device" 2>/dev/null
}

deadline=$((SECONDS + DEADLINE))
tried=0
while :; do
    have_backlight && break

    for n in $(gpu_buses); do
        bind_bus "$n" && tried=$((tried + 1))
    done

    have_backlight && break
    [ "$SECONDS" -lt "$deadline" ] || break
    # Устройство появляется не мгновенно: probe драйвера делает живую
    # DDC-транзакцию (~100 мс) плюс чтение capability string.
    sleep 2
done

if have_backlight; then
    dev=$(ls -d /sys/class/backlight/ddcci* | head -1)
    echo "ddcci-bind: ok, подсветка ${dev##*/} (привязок $tried)"
    exit 0
fi

echo "ddcci-bind: монитор не ответил по DDC за ${DEADLINE}с (привязок $tried)" >&2
exit 1
