#!/bin/bash
# Яркость внешнего монитора с подавлением дребезга.
#
# Зачем не нативный модуль waybar backlight/slider: запись в DDC/CI стоит
# 80-380 мс и деградирует при повторных вызовах — десять записей подряд
# занимают 3 секунды. Слайдер за одно перетаскивание шлёт десятки событий,
# очередь на i2c растёт до десятков секунд, монитор отстаёт, а waybar
# читает из sysfs ещё старое значение и рисует скачок назад. Выглядит
# как зацикливание.
#
# Здесь целевое значение копится в файле и показывается сразу, а в железо
# уходит ОДНА запись — после того, как пользователь перестал крутить.

set -u

# Номер шины (ddcci3, ddcci1, ...) зависит от порядка инициализации видеокарты
# и между загрузками не фиксирован — поэтому берём то, что реально создалось.
DEV=
for d in /sys/class/backlight/ddcci*; do
    [ -d "$d" ] && { DEV=$d; break; }
done
STATE="${XDG_RUNTIME_DIR:-/tmp}/brightness-target"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/brightness.lock"
APPLIER="${XDG_RUNTIME_DIR:-/tmp}/brightness-applier.lock"

STEP=5
MIN=1      # не 0: часть мониторов на нуле гаснет полностью, и вернуть их
MAX=100    #       можно только кнопками на самом мониторе
QUIET=0.25 # столько тишины считаем концом жеста

[ -n "$DEV" ] && [ -d "$DEV" ] || {
    echo '{"text":"","tooltip":"нет ddcci-устройства (systemctl status ddcci-bind)"}'
    exit 0
}

hw() { cat "$DEV/brightness" 2>/dev/null || echo 50; }

# Цель живёт максимум пару секунд после жеста. Если файл старый — значит
# предыдущий жест давно применён, и точка отсчёта берётся из железа.
target() {
    if [ -f "$STATE" ] && [ -n "$(find "$STATE" -mmin -1 2>/dev/null)" ]; then
        cat "$STATE"
    else
        hw
    fi
}

refresh() { pkill -RTMIN+9 -x waybar 2>/dev/null || true; }

case "${1:-get}" in
    get)
        t=$(target)
        if   [ "$t" -ge 67 ]; then icon="󰃠"
        elif [ "$t" -ge 34 ]; then icon="󰃟"
        else                       icon="󰃞"
        fi
        printf '{"text":"%s %s%%","tooltip":"Яркость монитора: %s%%","class":"brightness"}\n' \
            "$icon" "$t" "$t"
        exit 0
        ;;
    up|down|set) ;;
    *) echo "usage: $(basename "$0") {get|up|down|set <N>}" >&2; exit 1 ;;
esac

# --- обновляем цель под блокировкой -------------------------------------
exec 9>"$LOCK"
flock 9
cur=$(target)
case "$1" in
    # Со дна (MIN=1) вверх идём на ровный STEP, иначе вся сетка съезжает
    # на единицу и дальше получаются 6, 11, 16 вместо 5, 10, 15.
    up)   if [ "$cur" -lt "$STEP" ]; then new=$STEP; else new=$((cur + STEP)); fi ;;
    down) new=$((cur - STEP)) ;;
    set)  new=${2:-$cur} ;;
esac
[ "$new" -gt "$MAX" ] && new=$MAX
[ "$new" -lt "$MIN" ] && new=$MIN
echo "$new" > "$STATE"
flock -u 9
exec 9>&-

refresh   # индикатор меняется мгновенно, не дожидаясь железа

# --- применяем в железо один раз, когда жест закончился ------------------
# mkdir атомарен — гарантирует, что применяющий процесс ровно один.
if mkdir "$APPLIER" 2>/dev/null; then
    (
        trap 'rmdir "$APPLIER" 2>/dev/null' EXIT
        last=""
        # Ждём, пока цель перестанет меняться. Пока крутят колесо — цикл
        # крутится вхолостую и в монитор ничего не пишет.
        while :; do
            sleep "$QUIET"
            t=$(cat "$STATE" 2>/dev/null || break)
            [ "$t" = "$last" ] && break
            last="$t"
        done
        [ -n "$last" ] && echo "$last" > "$DEV/brightness" 2>/dev/null
        refresh
    ) >/dev/null 2>&1 &
    disown
fi
