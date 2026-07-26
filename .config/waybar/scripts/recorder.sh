#!/bin/bash

# Запись экрана для waybar. Клик — старт, повторный клик — стоп.
# Монитор с фокусом целиком, 720p60, h264_nvenc, → ~/records/*.mp4
#
# Вызовы:
#   recorder.sh          — переключить запись (on-click в waybar)
#   recorder.sh status   — JSON для модуля custom/recorder
#
# Почему именно так (каждый пункт чинит реальную поломку, не менять вслепую):
#
#   -r 60        Монитор DP-3 работает на 200 Гц, а wf-recorder без -r берёт
#                частоту источника. Получался бы файл на 200 fps — втрое
#                больше по размеру, и ни один сценарий этих кадров не просит.
#
#   -x yuv420p   NVENC не принимает то, что отдаёт wlr-screencopy (XRGB8888),
#                и падает на первом кадре. Заодно это единственный pixel
#                format, который открывают все плееры и браузеры.
#
#   -F scale=    Масштабирование делает ffmpeg-фильтр. Флага -s у wf-recorder
#                нет вообще — из-за него прошлая версия скрипта умирала сразу
#                после старта, а waybar продолжал рапортовать «Запись начата».
#
#   PID в файле  Останавливаем ровно свой процесс. `pkill -INT wf-recorder`
#                убил бы и чужую запись, а голый `pidof` не отличает «идёт
#                запись» от «процесс умер на старте»: ровно поэтому каждый
#                клик уходил в ветку старта и ничего не останавливал.
#
#   ожидание     После SIGINT wf-recorder дописывает moov-atom, без которого
#                mp4 не открывается ничем. Поэтому «сохранено» показываем
#                только после фактического выхода процесса, а не сразу.
#
#   RTMIN+10     Перерисовывает кнопку немедленно. Без сигнала вид иконки
#                менялся бы только на следующем interval — до 30 секунд.
#
# Звука в записи нет намеренно (его не просили). Включить — добавить в args
# `-a` (дефолтный источник) или `-a <имя>` из `pactl list short sources`.

set -u

RECORDS_DIR="$HOME/records"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNTIME_DIR/wf-recorder.pid"
OUTFILE="$RUNTIME_DIR/wf-recorder.out"
LOGFILE="$RUNTIME_DIR/wf-recorder.log"

FPS=60
SCALE="1280:720"
CODEC="h264_nvenc"   # hevc_nvenc — файл меньше, но хуже совместимость плееров
WAYBAR_SIGNAL=10     # обязан совпадать с "signal" в custom/recorder

notify() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a "recorder" -u low "$1" "${2:-}" >/dev/null 2>&1 &
}

# Немедленно перерисовать кнопку в waybar.
refresh_bar() { pkill -RTMIN+$WAYBAR_SIGNAL waybar >/dev/null 2>&1; }

# Печатает PID живой записи, иначе возвращает 1. Имя процесса сверяем: PID из
# файла система могла переиспользовать после падения wf-recorder.
rec_pid() {
    local pid
    pid=$(cat "$PIDFILE" 2>/dev/null) || return 1
    [ -n "$pid" ] || return 1
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = "wf-recorder" ] || return 1
    printf '%s' "$pid"
}

# --- статус для waybar --------------------------------------------------
if [ "${1:-toggle}" = "status" ]; then
    if rec_pid >/dev/null; then
        printf '{"text":"󰑊  Rec","class":"recording","tooltip":"Идёт запись — клик, чтобы остановить"}\n'
    elif command -v wf-recorder >/dev/null 2>&1; then
        printf '{"text":"󰻃","class":"idle","tooltip":"Запись экрана 720p60 → ~/records"}\n'
    else
        printf '{"text":"󰻃","class":"missing","tooltip":"wf-recorder не установлен: sudo pacman -S wf-recorder"}\n'
    fi
    exit 0
fi

# --- стоп ---------------------------------------------------------------
if pid=$(rec_pid); then
    kill -INT "$pid" 2>/dev/null

    # Ждём, пока допишется moov-atom (обычно доли секунды).
    for _ in $(seq 100); do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.1
    done

    if kill -0 "$pid" 2>/dev/null; then
        kill -TERM "$pid" 2>/dev/null
        notify "Запись оборвана" "wf-recorder не вышел за 10 с — файл может быть битым"
    else
        notify "Запись остановлена" "$(basename "$(cat "$OUTFILE" 2>/dev/null)" 2>/dev/null)"
    fi

    rm -f "$PIDFILE"
    refresh_bar
    exit 0
fi

# --- старт --------------------------------------------------------------
if ! command -v wf-recorder >/dev/null 2>&1; then
    notify "wf-recorder не установлен" "sudo pacman -S wf-recorder"
    refresh_bar
    exit 1
fi

mkdir -p "$RECORDS_DIR"
OUT="$RECORDS_DIR/$(date +%Y-%m-%d_%H-%M-%S).mp4"

args=(-f "$OUT" -c "$CODEC" -x yuv420p -r "$FPS" -F "scale=$SCALE")

# Пишем монитор с фокусом. Без -o wf-recorder при нескольких выходах ждёт
# выбора на stdin, которого под waybar нет, и молча умирает.
MON=$(hyprctl -j monitors 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)
[ -n "$MON" ] && args+=(-o "$MON")

wf-recorder "${args[@]}" >"$LOGFILE" 2>&1 &
pid=$!
printf '%s' "$pid" >"$PIDFILE"
printf '%s' "$OUT" >"$OUTFILE"

# Даём дожить до первого кадра: почти все ошибки (нет кодека, занят GPU,
# кривой фильтр) вылезают в первые полсекунды. Без этой проверки waybar
# рапортовал «Запись начата» даже когда писать было нечем.
sleep 0.7
if ! kill -0 "$pid" 2>/dev/null; then
    rm -f "$PIDFILE"
    notify "Запись не запустилась" "$(tail -n 2 "$LOGFILE" 2>/dev/null)"
    refresh_bar
    exit 1
fi

notify "Запись начата" "720p60 → ~/records"
refresh_bar
