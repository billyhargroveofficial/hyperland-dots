#!/bin/bash

# Restart script for Hyprland and related services
# Bind: $mainMod CTRL + W

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t "$RUNTIME_DIR/hypr/" 2>/dev/null | head -1)

echo "Restarting Hyprland services..."

# Restart waybar
pkill waybar 2>/dev/null
sleep 0.5
WAYBAR_BIN="$HOME/.local/bin/waybar"
[[ -x "$WAYBAR_BIN" ]] || WAYBAR_BIN=waybar
"$WAYBAR_BIN" &disown

# Restart wallpaper
pkill awww-daemon 2>/dev/null
sleep 0.5
awww-daemon &disown
sleep 1
# Источник правды — кэш ~/.cache/current_wallpaper, который пишут wall-next.sh и
# wall-select.sh. Раньше путь выковыривался grep'ом из hyprland.conf, и любая
# правка строки exec-once ломала восстановление обоев.
WALLPAPER=$(cat ~/.cache/current_wallpaper 2>/dev/null)
if [[ ! -f "$WALLPAPER" ]]; then
    WALLPAPER="$HOME/wallpapers/1.jpg"
fi
if [[ -f "$WALLPAPER" ]]; then
    awww img "$WALLPAPER" --transition-type none
else
    echo "WARN: обои не найдены ($WALLPAPER), фон останется чёрным"
fi

# Restart clipboard manager
pkill wl-paste 2>/dev/null
sleep 0.5
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# nwg-dock отключён по просьбе пользователя. Гасим на случай, если он остался
# запущенным с прошлой сессии. -x по comm, а не -f по cmdline: -f матчит любую
# строку, где встретилось имя, включая шелл, который этот pkill и запустил.
# comm обрезан ядром до 15 символов, отсюда усечённое имя.
pkill -x nwg-dock-hyprla 2>/dev/null
# Вернуть док: раскомментировать строку ниже и layerrule'ы в hyprland.conf.
# nwg-dock-hyprland -d -l overlay -p bottom -i 48 -nolauncher -o DP-3 -m -iw "1,2,3,4,5,6,7,8,9,10" &disown

# hyprshell отсюда убран вместе с автозапуском: его оверлей на Alt+Tab был не
# нужен. Переключение окон теперь нативное (bind = ALT, Tab, cyclenext в
# hyprland.conf) и переживает reload само, поднимать ничего не надо.

# Reload Hyprland config
hyprctl reload

echo "Restart complete!"
