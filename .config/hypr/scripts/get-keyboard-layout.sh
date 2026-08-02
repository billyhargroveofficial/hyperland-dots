#!/bin/bash
# Hyprland keyboard layout detector

if [ "$XDG_CURRENT_DESKTOP" = "Hyprland" ] || pgrep -x Hyprland > /dev/null; then
    hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_keymap' | head -c 2 | tr '[:lower:]' '[:upper:]'
else
    echo "??"
fi
