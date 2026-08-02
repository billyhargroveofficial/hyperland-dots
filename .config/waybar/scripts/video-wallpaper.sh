#!/usr/bin/env bash

# Manual Waybar control for nv-wallpaper. No window-state automation: a click
# starts or stops the renderer, while awww remains the static fallback.

set -euo pipefail

CONTROL="$HOME/.local/bin/nv-wallpaperctl"
WAYBAR_SIGNAL=11

refresh_bar() {
    pkill -RTMIN+$WAYBAR_SIGNAL waybar >/dev/null 2>&1 || true
}

notify_missing() {
    command -v notify-send >/dev/null 2>&1 || return 0
    notify-send -a nv-wallpaper -u low "Видеообои не установлены" \
        "Ожидался $CONTROL" >/dev/null 2>&1 &
}

if [[ ! -x "$CONTROL" ]]; then
    notify_missing
    refresh_bar
    exit 1
fi

case "${1:-toggle}" in
    toggle)
        "$CONTROL" toggle
        ;;
    on|play)
        "$CONTROL" on
        ;;
    off|static)
        "$CONTROL" off
        ;;
    status)
        if systemctl --user is-active --quiet nv-wallpaper.service; then
            printf 'playing\n'
        else
            printf 'stopped\n'
        fi
        exit 0
        ;;
    *)
        echo "usage: $0 {toggle|on|off|status}" >&2
        exit 2
        ;;
esac

sleep 0.15
refresh_bar
