#!/bin/bash
# Переключает главный модификатор Hyprland между ALT и SUPER.
# Бинд: F10 (см. hyprland.conf).
#
# Зачем: клавиатура умеет Mac-режим, где под большим пальцем лежит Cmd (шлёт
# META/SUPER), и обычный режим, где там Alt. Мышечная память одна, модификатор
# разный — этот скрипт перекидывает весь конфиг с одного на другой.
#
# Правятся только строки `$mainMod = ` и `$wsMod = `; сами бинды написаны через
# переменные, поэтому больше трогать нечего.

set -euo pipefail

CONF="$HOME/.config/hypr/hyprland.conf"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Hyprland" "$1" -i input-keyboard || echo "$1"
}

[[ -f "$CONF" ]] || { notify "toggle-mainmod: нет $CONF"; exit 1; }

CURRENT=$(grep -m1 -oP '^\$mainMod\s*=\s*\K\S+' "$CONF" || true)

case "$CURRENT" in
    ALT)   NEW=SUPER ;;
    SUPER) NEW=ALT ;;
    *)     notify "toggle-mainmod: \$mainMod = '${CURRENT:-не найден}', ожидался ALT или SUPER"; exit 1 ;;
esac

# Бэкап на случай, если sed съест что-то не то
cp -- "$CONF" "$CONF.bak-mainmod"

# Пишем во временный файл и подменяем атомарно: оборванный sed прямо в конфиг
# оставил бы Hyprland без биндов вообще.
TMP=$(mktemp "$CONF.XXXXXX")
trap 'rm -f "$TMP"' EXIT
sed -E "s/^(\\\$mainMod\s*=\s*).*/\1$NEW/; s/^(\\\$wsMod\s*=\s*).*/\1$NEW/" "$CONF" > "$TMP"

# Проверяем, что замена реально произошла, прежде чем ломать рабочий конфиг
if ! grep -qE "^\\\$mainMod\s*=\s*$NEW\b" "$TMP"; then
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

# Перерегистрация hyprshell отсюда убрана вместе с самим hyprshell. Alt+Tab
# теперь описан биндами в hyprland.conf, а не вешается в рантайме, поэтому
# `hyprctl reload` его больше не сбрасывает и чинить после reload нечего.

notify "Главный модификатор: $NEW"
