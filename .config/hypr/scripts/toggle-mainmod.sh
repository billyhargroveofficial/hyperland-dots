#!/bin/bash
# Переключает главный модификатор Hyprland между ALT и SUPER.
# Бинд: F10.
#
# Зачем: клавиатура умеет Mac-режим, где под большим пальцем лежит Cmd (шлёт
# META/SUPER), и обычный режим, где там Alt. Мышечная память одна, модификатор
# разный — этот скрипт перекидывает весь конфиг с одного на другой.
#
# Правятся только две строки объявления модификатора; сами бинды написаны через
# переменные, поэтому больше трогать нечего.
#
# Конфиг бывает в двух форматах, и правим мы РОВНО ТОТ, который Hyprland
# реально загрузил, а не тот, что лежит на диске:
#
#   hyprland.lua   local mainMod = "ALT"
#   hyprland.conf  $mainMod = ALT
#
# Формат выбирается один раз при старте Hyprland: если .lua на месте, берётся
# он, иначе .conf. `hyprctl reload` этот выбор НЕ пересматривает, поэтому
# сразу после создания .lua сессия ещё живёт на .conf — и править надо .conf.
# Отличаем по Lua REPL: он отвечает только когда активен lua-менеджер.

set -euo pipefail

HYPR_DIR="$HOME/.config/hypr"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Hyprland" "$1" -i input-keyboard || echo "$1"
}

if hyprctl repl 'return "probe"' 2>&1 | grep -q "only supported with the lua"; then
    FORMAT=conf
    CONF="$HYPR_DIR/hyprland.conf"
    # $mainMod = ALT
    CURRENT_RE='^\$mainMod\s*=\s*\K\S+'
    sed_expr() { printf 's/^(\\$mainMod\\s*=\\s*).*/\\1%s/; s/^(\\$wsMod\\s*=\\s*).*/\\1%s/' "$1" "$1"; }
    check_re() { printf '^\\$mainMod\\s*=\\s*%s\\b' "$1"; }
else
    FORMAT=lua
    CONF="$HYPR_DIR/hyprland.lua"
    # local mainMod = "ALT"
    CURRENT_RE='^local\s+mainMod\s*=\s*"\K[A-Z]+'
    sed_expr() { printf 's/^(local\\s+mainMod\\s*=\\s*").*(")/\\1%s\\2/; s/^(local\\s+wsMod\\s*=\\s*").*(")/\\1%s\\2/' "$1" "$1"; }
    check_re() { printf '^local\\s+mainMod\\s*=\\s*"%s"' "$1"; }
fi

[[ -f "$CONF" ]] || { notify "toggle-mainmod: нет $CONF"; exit 1; }

CURRENT=$(grep -m1 -oP "$CURRENT_RE" "$CONF" || true)

case "$CURRENT" in
    ALT)   NEW=SUPER ;;
    SUPER) NEW=ALT ;;
    *)     notify "toggle-mainmod: mainMod = '${CURRENT:-не найден}' в $FORMAT-конфиге, ожидался ALT или SUPER"; exit 1 ;;
esac

# Бэкап на случай, если sed съест что-то не то
cp -- "$CONF" "$CONF.bak-mainmod"

# Пишем во временный файл и подменяем атомарно: оборванный sed прямо в конфиг
# оставил бы Hyprland без биндов вообще.
TMP=$(mktemp "$CONF.XXXXXX")
trap 'rm -f "$TMP"' EXIT
sed -E "$(sed_expr "$NEW")" "$CONF" > "$TMP"

# Проверяем, что замена реально произошла, прежде чем ломать рабочий конфиг
if ! grep -qP "$(check_re "$NEW")" "$TMP"; then
    notify "toggle-mainmod: замена не удалась, конфиг не тронут"
    exit 1
fi

cat -- "$TMP" > "$CONF"   # cat, а не mv: сохраняем inode и права исходного файла
rm -f "$TMP"
trap - EXIT

hyprctl reload > /dev/null

ERRORS=$(hyprctl configerrors 2>/dev/null)
if [[ -n "$ERRORS" && "$ERRORS" != "no errors" ]]; then
    notify "toggle-mainmod: ОШИБКИ КОНФИГА, откатываю"
    cat -- "$CONF.bak-mainmod" > "$CONF"
    hyprctl reload > /dev/null
    exit 1
fi

notify "Главный модификатор: $NEW"
