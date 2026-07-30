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
#
# Мониторов может быть несколько, и на первую попытку отвечают не все: 26 июля
# DP-2 промолчал ("ddcci 2-0037: core device [6e] probe failed: -19"), а старая
# версия скрипта выходила по первой же появившейся подсветке — второй экран так
# и оставался без ddcci до следующей перезагрузки. Поэтому целимся в число
# подключённых коннекторов и добираем отставших.

set -u

DEADLINE=60

modprobe i2c-dev 2>/dev/null
modprobe ddcci-backlight 2>/dev/null

# Номера i2c-шин, принадлежащих видеокартам
gpu_buses() {
    local card gpu bus
    for card in /sys/class/drm/card*; do
        # Отсекаем коннекторы (card1-DP-2): у них тот же префикс, но свой
        # симлинк device, и перебор шин для них просто дублирует работу.
        case "${card##*/}" in *-*) continue ;; esac
        [ -e "$card/device" ] || continue
        gpu=$(readlink -f "$card/device")
        for bus in /sys/bus/i2c/devices/i2c-*; do
            case "$(readlink -f "$bus")" in
                "$gpu"/*) echo "${bus##*/i2c-}" ;;
            esac
        done
    done | sort -un
}

# Сколько подсветок ждём: по одной на подключённый монитор видеокарты. Карты
# без своих i2c-шин пропускаем — DDC/CI там всё равно невозможен, и их
# коннекторы только завышали бы цель, заставляя скрипт ждать весь дедлайн.
want_displays() {
    local card gpu bus conn n=0 has_i2c
    for card in /sys/class/drm/card*; do
        case "${card##*/}" in *-*) continue ;; esac
        [ -e "$card/device" ] || continue
        gpu=$(readlink -f "$card/device")
        has_i2c=0
        for bus in /sys/bus/i2c/devices/i2c-*; do
            case "$(readlink -f "$bus")" in
                "$gpu"/*) has_i2c=1; break ;;
            esac
        done
        [ "$has_i2c" = 1 ] || continue
        for conn in "$card"-*; do
            [ -e "$conn/status" ] || continue
            [ "$(cat "$conn/status" 2>/dev/null)" = connected ] && n=$((n + 1))
        done
    done
    echo "$n"
}

have_backlights() {
    local d n=0
    for d in /sys/class/backlight/ddcci*; do
        [ -d "$d" ] && n=$((n + 1))
    done
    echo "$n"
}

# 0x37 — стандартный адрес DDC/CI. Промахи безвредны: там, где никто не
# отвечает, драйвер не привяжется.
bind_bus() {
    local n=$1
    if [ -e "/sys/bus/i2c/devices/${n}-0037" ]; then
        # Клиент с драйвером — шина уже рабочая, не трогаем.
        [ -e "/sys/bus/i2c/devices/${n}-0037/driver" ] && return 1
        # Клиент без драйвера — осадок неудачного probe (монитор спал или ещё
        # не проснулся). Просто повторить new_device нельзя, ядро ответит
        # EBUSY на занятый адрес, поэтому сносим и создаём заново.
        echo 0x37 > "/sys/bus/i2c/devices/i2c-${n}/delete_device" 2>/dev/null
    fi
    [ -w "/sys/bus/i2c/devices/i2c-${n}/new_device" ] || return 1
    echo "ddcci 0x37" > "/sys/bus/i2c/devices/i2c-${n}/new_device" 2>/dev/null
}

want=$(want_displays)
[ "$want" -gt 0 ] || want=1

deadline=$((SECONDS + DEADLINE))
tried=0
pause=2
while :; do
    [ "$(have_backlights)" -ge "$want" ] && break

    for n in $(gpu_buses); do
        bind_bus "$n" && tried=$((tried + 1))
    done

    [ "$(have_backlights)" -ge "$want" ] && break
    [ "$SECONDS" -lt "$deadline" ] || break
    # Устройство появляется не мгновенно: probe драйвера делает живую
    # DDC-транзакцию (~100 мс) плюс чтение capability string. Пауза растёт,
    # чтобы полсотни промахов по спящему монитору не залили dmesg строками
    # "probe failed: -19".
    sleep "$pause"
    [ "$pause" -lt 16 ] && pause=$((pause * 2))
done

got=$(have_backlights)
devs=$(ls -d /sys/class/backlight/ddcci* 2>/dev/null | sed 's|.*/||' | tr '\n' ' ')

if [ "$got" -ge "$want" ]; then
    echo "ddcci-bind: ok, подсветки: ${devs% } (привязок $tried)"
    exit 0
fi

if [ "$got" -gt 0 ]; then
    # Частичный успех — не ошибка юнита: одним экраном яркость уже управляется,
    # а молчащий монитор чаще всего просто выключен физически.
    echo "ddcci-bind: ответили $got из $want мониторов: ${devs% } (привязок $tried)" >&2
    exit 0
fi

echo "ddcci-bind: монитор не ответил по DDC за ${DEADLINE}с (привязок $tried)" >&2
exit 1
