#!/usr/bin/env bash

# Render the bundled Lucide SVGs with the current Waybar accent and expose
# state-aware image paths for Waybar's native image module.

set -euo pipefail

WAYBAR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/waybar"
SOURCE_DIR="$WAYBAR_DIR/icons"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-svg-icons"
STATE_FILE="$WAYBAR_DIR/accent-name"
ACCENT_SCRIPT="$WAYBAR_DIR/scripts/accent.sh"

build_icon() {
    local source=$1 destination=$2 color=$3 icon_tmp
    icon_tmp=$(mktemp "$CACHE_DIR/.icon.XXXXXX.svg")
    sed "s|currentColor|$color|g" "$source" > "$icon_tmp"
    mv -f "$icon_tmp" "$destination"
}

theme_variant() {
    local scheme
    scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
    if [[ "$scheme" == *dark* ]]; then
        printf '%s\n' dark
    else
        printf '%s\n' light
    fi
}

write_swatch() {
    local name=$1 color=$2 active=$3 swatch_tmp
    local radius opacity ring suffix=''

    if [[ "$active" == true ]]; then
        radius=6.5
        opacity=1
        suffix='-active'
        ring="<circle cx=\"12\" cy=\"12\" r=\"9.5\" fill=\"none\" stroke=\"$color\" stroke-width=\"1.5\"/>"
    else
        radius=5.5
        opacity=0.58
        ring=""
    fi

    swatch_tmp=$(mktemp "$CACHE_DIR/.swatch.XXXXXX.svg")
    printf '%s\n' \
        "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"24\" height=\"24\" viewBox=\"0 0 24 24\">$ring<circle cx=\"12\" cy=\"12\" r=\"$radius\" fill=\"$color\" opacity=\"$opacity\"/></svg>" \
        > "$swatch_tmp"
    mv -f "$swatch_tmp" "$CACHE_DIR/swatch-$name$suffix.svg"
}

build() {
    local light=${1:-} dark=${2:-}
    local source stem

    [[ "$light" =~ ^#[0-9A-Fa-f]{6}$ ]] || {
        printf 'invalid light SVG accent color: %s\n' "$light" >&2
        return 2
    }
    [[ -n "$dark" ]] || dark=$light
    [[ "$dark" =~ ^#[0-9A-Fa-f]{6}$ ]] || {
        printf 'invalid dark SVG accent color: %s\n' "$dark" >&2
        return 2
    }

    mkdir -p "$CACHE_DIR"
    for source in "$SOURCE_DIR"/*.svg; do
        [[ -f "$source" ]] || continue
        stem=$(basename "$source" .svg)
        build_icon "$source" "$CACHE_DIR/$stem-light.svg" "$light"
        build_icon "$source" "$CACHE_DIR/$stem-dark.svg" "$dark"
    done

    # Recording is the only semantic warning state; everything else remains
    # on the selected accent so both islands stay visually unified.
    build_icon "$SOURCE_DIR/video.svg" "$CACHE_DIR/video-active-light.svg" '#D93025'
    build_icon "$SOURCE_DIR/video.svg" "$CACHE_DIR/video-active-dark.svg" '#D93025'

    write_swatch purple '#8D69D5' false
    write_swatch purple '#8D69D5' true
    write_swatch blue '#4B8FD3' false
    write_swatch blue '#4B8FD3' true
    write_swatch teal '#36A99B' false
    write_swatch teal '#36A99B' true
    write_swatch amber '#C78C24' false
    write_swatch amber '#C78C24' true
}

ensure_cache() {
    [[ -f "$CACHE_DIR/cpu-light.svg" && -f "$CACHE_DIR/cpu-dark.svg" ]] && return 0
    if [[ -x "$ACCENT_SCRIPT" ]]; then
        "$ACCENT_SCRIPT" refresh >/dev/null
    fi
    [[ -f "$CACHE_DIR/cpu-light.svg" && -f "$CACHE_DIR/cpu-dark.svg" ]] \
        || build '#6F4AC8' '#B69AF6'
}

icon_path() {
    local name=$1 path variant
    ensure_cache
    if [[ "$name" == swatch-* ]]; then
        path="$CACHE_DIR/$name.svg"
    else
        variant=$(theme_variant)
        path="$CACHE_DIR/$name-$variant.svg"
    fi
    [[ -f "$path" ]] || {
        printf 'unknown SVG icon: %s\n' "$name" >&2
        return 2
    }
    printf '%s\n' "$path"
}

show_icon() {
    local name=$1 tooltip=${2:-}
    icon_path "$name"
    [[ -n "$tooltip" ]] && printf '%s\n' "$tooltip"
}

accent_status() {
    local name=$1 selected label suffix=''
    selected=$(sed -n '1p' "$STATE_FILE" 2>/dev/null || true)
    [[ "$selected" == "$name" ]] && suffix='-active'
    case "$name" in
        purple) label='Фиолетовый акцент' ;;
        blue) label='Синий акцент' ;;
        teal) label='Бирюзовый акцент' ;;
        amber) label='Янтарный акцент' ;;
        *) return 2 ;;
    esac
    show_icon "swatch-$name$suffix" "$label"
}

theme_status() {
    local scheme
    scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
    if [[ "$scheme" == *dark* ]]; then
        show_icon moon 'Тёмная тема — нажать для светлой'
    else
        show_icon sun 'Светлая тема — нажать для тёмной'
    fi
}

network_status() {
    local row connection
    row=$(nmcli -t -f TYPE,STATE,CONNECTION device status 2>/dev/null \
        | awk -F: '$1 == "wifi" && $2 == "connected" { print; exit }') || true
    if [[ -n "$row" ]]; then
        connection=${row#*:*:}
        show_icon wifi "Wi-Fi: ${connection:-подключён}"
    else
        show_icon wifi-off 'Wi-Fi не подключён'
    fi
}

vpn_status() {
    if pgrep -x sing-box >/dev/null 2>&1; then
        show_icon lock-keyhole 'VPN включён — переключение Alt+P'
    else
        show_icon lock 'VPN выключен — переключение Alt+P'
    fi
}

bluetooth_status() {
    local controller connections
    controller=$(timeout 1 bluetoothctl show 2>/dev/null || true)
    if grep -q 'Powered: yes' <<<"$controller"; then
        connections=$(timeout 1 bluetoothctl devices Connected 2>/dev/null || true)
        connections=$(sed '/^$/d' <<<"$connections" | wc -l)
        if (( connections > 0 )); then
            show_icon bluetooth "Bluetooth: подключено устройств — $connections"
        else
            show_icon bluetooth 'Bluetooth включён'
        fi
    else
        show_icon bluetooth-off 'Bluetooth выключен'
    fi
}

volume_status() {
    local status percent
    status=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
    percent=$(awk '{ printf "%.0f", $2 * 100 }' <<<"$status")
    if [[ "$status" == *MUTED* ]]; then
        show_icon volume-x "Звук выключен (${percent:-0}%)"
    else
        show_icon volume-2 "Громкость: ${percent:-0}%"
    fi
}

recorder_status() {
    local pid_file="${XDG_RUNTIME_DIR:-/tmp}/wf-recorder.pid" pid
    pid=$(cat "$pid_file" 2>/dev/null || true)
    if [[ -n "$pid" && "$(cat "/proc/$pid/comm" 2>/dev/null || true)" == wf-recorder ]]; then
        show_icon video-active 'Идёт запись — нажать, чтобы остановить'
    elif command -v wf-recorder >/dev/null 2>&1; then
        show_icon video 'Запись экрана 720p60'
    else
        show_icon video 'wf-recorder не установлен'
    fi
}

wallpaper_status() {
    if systemctl --user is-active --quiet nv-wallpaper.service; then
        show_icon pause 'Видеообои идут — остановить и сохранить позицию'
    else
        show_icon play 'Видеообои остановлены — продолжить с сохранённой позиции'
    fi
}

case "${1:-}" in
    build) build "${2:-}" "${3:-}" ;;
    path) show_icon "${2:-}" "${3:-}" ;;
    accent) accent_status "${2:-}" ;;
    theme) theme_status ;;
    network) network_status ;;
    vpn) vpn_status ;;
    bluetooth) bluetooth_status ;;
    volume) volume_status ;;
    recorder) recorder_status ;;
    wallpaper) wallpaper_status ;;
    *)
        printf 'usage: %s {build LIGHT [DARK]|path NAME [TOOLTIP]|accent NAME|theme|network|vpn|bluetooth|volume|recorder|wallpaper}\n' "$0" >&2
        exit 2
        ;;
esac
