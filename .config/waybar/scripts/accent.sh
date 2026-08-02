#!/usr/bin/env bash

set -u

WAYBAR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
STATE_FILE="$WAYBAR_DIR/accent-name"
CSS_FILE="$WAYBAR_DIR/accent.css"
MONO_ICONS="$HOME/.local/bin/waybar-mono-icons"

palette() {
    case "$1" in
        purple) printf '%s\n' '#6F4AC8' '#B69AF6' '#8D69D5' 'Фиолетовый' ;;
        blue)   printf '%s\n' '#2867B2' '#7CB6F9' '#4B8FD3' 'Синий' ;;
        teal)   printf '%s\n' '#16796F' '#67CFC1' '#36A99B' 'Бирюзовый' ;;
        amber)  printf '%s\n' '#9A6300' '#F0BE58' '#C78C24' 'Янтарный' ;;
        *) return 1 ;;
    esac
}

selected_color() {
    local selected
    selected=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)
    palette "$selected" >/dev/null 2>&1 || selected=purple
    printf '%s\n' "$selected"
}

write_accent_css() {
    local name=$1 light dark icon label css_tmp
    mapfile -t colors < <(palette "$name") || return 1
    light=${colors[0]}
    dark=${colors[1]}
    icon=${colors[2]}
    label=${colors[3]}

    css_tmp=$(mktemp "$WAYBAR_DIR/.accent.css.XXXXXX") || return 1
    printf '@define-color waybar_accent_light %s;\n@define-color waybar_accent_dark %s;\n' \
        "$light" "$dark" > "$css_tmp"
    mv -f "$css_tmp" "$CSS_FILE"

    if [[ -x "$MONO_ICONS" ]]; then
        "$MONO_ICONS" --color "$icon" --quiet
    fi
}

apply_color() {
    local name=$1 state_tmp
    palette "$name" >/dev/null || return 1
    state_tmp=$(mktemp "$WAYBAR_DIR/.accent-name.XXXXXX") || return 1
    printf '%s\n' "$name" > "$state_tmp"
    mv -f "$state_tmp" "$STATE_FILE"
    write_accent_css "$name" || return 1
    pkill -USR2 -x waybar 2>/dev/null || true
}

status() {
    local name=$1 selected class label
    palette "$name" >/dev/null || return 1
    selected=$(selected_color)
    [[ "$selected" == "$name" ]] && class=active || class=inactive
    label=$(palette "$name" | sed -n '4p')
    printf '{"text":"●","class":"%s","tooltip":"%s"}\n' "$class" "$label"
}

theme_status() {
    local scheme
    scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
    if [[ "$scheme" == *dark* ]]; then
        printf '{"text":"󰖔","class":"dark","tooltip":"Тёмная тема — нажать для светлой"}\n'
    else
        printf '{"text":"󰖙","class":"light","tooltip":"Светлая тема — нажать для тёмной"}\n'
    fi
}

case "${1:-}" in
    set) apply_color "${2:-}" ;;
    status) status "${2:-}" ;;
    refresh) write_accent_css "$(selected_color)" ;;
    theme-status) theme_status ;;
    *)
        printf 'usage: %s {set NAME|status NAME|refresh|theme-status}\n' "$0" >&2
        exit 2
        ;;
esac
