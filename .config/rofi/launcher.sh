#!/usr/bin/env bash

set -euo pipefail

scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
if [[ "$scheme" == *dark* ]]; then
    icon_theme="Papirus-Dark"
else
    icon_theme="Papirus"
fi

exec rofi \
    -show drun \
    -show-icons \
    -icon-theme "$icon_theme" \
    -theme "$HOME/.config/rofi/launcher.rasi" \
    "$@"
