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

# Номера (ddcci3, ddcci1, ...) зависят от порядка инициализации видеокарты и
# между загрузками не фиксированы — поэтому берём всё, что реально создалось.
# Мониторов больше одного: одна ручка крутит сразу все экраны, поэтому здесь
# список, а не единственное устройство.
DEVS=()
for d in /sys/class/backlight/ddcci*; do
    [ -d "$d" ] && DEVS+=("$d")
done
STATE="${XDG_RUNTIME_DIR:-/tmp}/brightness-target"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/brightness.lock"
APPLIER="${XDG_RUNTIME_DIR:-/tmp}/brightness-applier.lock"

STEP=5
MIN=1      # не 0: часть мониторов на нуле гаснет полностью, и вернуть их
MAX=100    #       можно только кнопками на самом мониторе
QUIET=0.25 # столько тишины считаем концом жеста

[ "${#DEVS[@]}" -gt 0 ] || {
    echo '{"text":"","tooltip":"нет ddcci-устройства (systemctl status ddcci-bind)"}'
    exit 0
}

# Экраны держатся синхронно, так что за текущее значение отвечает первый.
hw() { cat "${DEVS[0]}/brightness" 2>/dev/null || echo 50; }

# Пишем последовательно, а не в фоне на каждый экран: у nvidia все i2c-шины
# сидят под одним локом драйвера, параллельные записи всё равно выстроятся в
# очередь, зато вперемешку дают DDC-таймауты и монитор проглатывает значение.
apply() {
    local v=$1 dev max w
    for dev in "${DEVS[@]}"; do
        max=$(cat "$dev/max_brightness" 2>/dev/null || echo 100)
        w=$v
        [ "$w" -gt "$max" ] && w=$max
        echo "$w" > "$dev/brightness" 2>/dev/null || true
    done
}

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
        if [ "${#DEVS[@]}" -gt 1 ]; then
            tip="Яркость мониторов (${#DEVS[@]}): $t%"
        else
            tip="Яркость монитора: $t%"
        fi
        printf '{"text":"%s%%","tooltip":"%s","class":"brightness"}\n' \
            "$t" "$tip"
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
        [ -n "$last" ] && apply "$last"
        refresh
    ) >/dev/null 2>&1 &
    disown
fi
