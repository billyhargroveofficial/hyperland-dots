#!/usr/bin/env bash

# Return a colorized play/pause SVG for Waybar's manual nv-wallpaper control.

set -euo pipefail

WAYBAR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
SOURCE_DIR="$WAYBAR_DIR/icons"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-video-wallpaper"
ACCENT_FILE="$WAYBAR_DIR/accent-name"

selected_accent() {
    local name
    name=$(sed -n '1p' "$ACCENT_FILE" 2>/dev/null || true)
    case "$name" in
        purple|blue|teal|amber) printf '%s\n' "$name" ;;
        *) printf '%s\n' purple ;;
    esac
}

accent_color() {
    local name=$1 scheme
    scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
    case "$name:$scheme" in
        purple:*dark*) printf '%s\n' '#B69AF6' ;;
        purple:*)      printf '%s\n' '#6F4AC8' ;;
        blue:*dark*)   printf '%s\n' '#7CB6F9' ;;
        blue:*)        printf '%s\n' '#2867B2' ;;
        teal:*dark*)   printf '%s\n' '#67CFC1' ;;
        teal:*)        printf '%s\n' '#16796F' ;;
        amber:*dark*)  printf '%s\n' '#F0BE58' ;;
        amber:*)       printf '%s\n' '#9A6300' ;;
    esac
}

if systemctl --user is-active --quiet nv-wallpaper.service; then
    icon=pause
else
    icon=play
fi

color=$(accent_color "$(selected_accent)")
source_icon="$SOURCE_DIR/$icon.svg"
destination="$CACHE_DIR/$icon-${color#\#}.svg"
[[ -f "$source_icon" ]] || {
    printf 'missing video wallpaper icon: %s\n' "$source_icon" >&2
    exit 1
}

if [[ ! -f "$destination" || "$source_icon" -nt "$destination" ]]; then
    mkdir -p "$CACHE_DIR"
    icon_tmp=$(mktemp "$CACHE_DIR/.icon.XXXXXX.svg")
    sed "s|currentColor|$color|g" "$source_icon" > "$icon_tmp"
    chmod 600 "$icon_tmp"
    mv -f "$icon_tmp" "$destination"
fi

printf '%s\n' "$destination"
