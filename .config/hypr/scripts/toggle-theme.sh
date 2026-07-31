#!/bin/bash

# Toggle dark/light theme system-wide
# Bind: CTRL + Y
#
# Как это работает (важно для понимания, что можно, а что нельзя):
#
#   Единственный источник правды  -> gsettings org.gnome.desktop.interface
#   Его транслирует наружу        -> xdg-desktop-portal-gtk, ключ
#                                    org.freedesktop.appearance color-scheme
#
#   Само подхватывают вживую (ничего делать не надо):
#     * GTK4 / libadwaita (nautilus, mission-center, ...) — AdwStyleManager
#     * GTK3 (pavucontrol, blueman)                       — через gtk-theme
#     * waybar >= 0.15  — сам читает портал и берёт style-<appearance>.css
#     * ghostty >= 1.2  — сам читает портал, theme = light:...,dark:...
#     * Qt6             — QT_QPA_PLATFORMTHEME=xdgdesktopportal
#
#   Требуют явного пинка (делаем ниже): hyprland, nvim, VSCode
#
#   НЕ переключаются вживую вообще: Chromium/Chrome/Brave/Electron.
#   Они уходят в тёмную тему по сигналу портала, но обратно в светлую
#   НЕ возвращаются — известный баг Chromium. Нужен полный рестарт браузера.
#
# ВНИМАНИЕ: не добавлять `env = GTK_THEME,...` в hyprland.conf —
# GTK_THEME это жёсткий оверрайд, он полностью убивает переключение GTK3.

set -u

STATE_FILE="$HOME/.config/hypr/.theme-state"
WAYBAR_DIR="$HOME/.config/waybar"
SWAYNC_DIR="$HOME/.config/swaync"
WEZTERM_THEME="$HOME/.config/wezterm/theme.txt"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"

# Не даём повторному нажатию Ctrl+Y запустить второй переключатель, пока
# первый ещё рассылает обновления приложениям.
THEME_LOCK="${XDG_RUNTIME_DIR:-/tmp}/billy-toggle-theme.lock"
exec 9>"$THEME_LOCK"
flock -n 9 || exit 0

current_scheme=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null || true)
case "$current_scheme" in
    *dark*) current="dark" ;;
    *light*) current="light" ;;
    *) current=$(cat "$STATE_FILE" 2>/dev/null || echo "dark") ;;
esac

if [ "$current" = "dark" ]; then
    MODE="light"
    GTK_THEME_NAME="Adwaita"
    COLOR_SCHEME="prefer-light"
else
    MODE="dark"
    GTK_THEME_NAME="Adwaita-dark"
    COLOR_SCHEME="prefer-dark"
fi

# --- 1. Единственный источник правды -----------------------------------
# color-scheme  -> GTK4/libadwaita, Qt, waybar, ghostty, Electron
# gtk-theme     -> GTK3 (у него нет понятия color-scheme, только имя темы;
#                  поэтому нужны две РЕАЛЬНЫЕ темы: Adwaita и Adwaita-dark
#                  из пакета gnome-themes-extra)
gsettings set org.gnome.desktop.interface color-scheme "$COLOR_SCHEME"
gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME"

# --- 2. settings.ini для GTK3 -------------------------------------------
# Приложения читают его при старте (портал потом перекрывает). Держим в
# синхроне, чтобы свежезапущенное GTK3-приложение не мигало чужой темой.
# ВАЖНО: gtk-application-prefer-dark-theme сюда НЕ добавлять — он намертво
# прибивает тёмную тему, а settings.ini не перечитывается на лету.
if [ -f "$GTK3_INI" ]; then
    sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$GTK_THEME_NAME/" "$GTK3_INI"
fi

# --- 3. waybar ----------------------------------------------------------
# waybar 0.15 сам слушает портал и предпочитает style-<appearance>.css
# перед style.css, так что перезапуск НЕ нужен. Симлинк оставляем только
# как запасной вариант на случай, если портал недоступен.
#
# Цель симлинка задаётся ОТНОСИТЕЛЬНО (`style-dark.css`, а не полный путь):
# каталог waybar лежит в git, и абсолютная цель зашила бы туда /home/billy —
# на другой машине ссылка оказалась бы битой. Плюс репа и система тогда
# расходятся при каждом переключении темы.
ln -sfn "style-${MODE}.css" "$WAYBAR_DIR/style.css"

# --- 3b. swaync ---------------------------------------------------------
# Уведомления оформлены под waybar и держат две темы теми же файлами:
# style-{dark,light}.css, а style.css — симлинк на активную. Портал swaync
# не слушает (в отличие от waybar), поэтому переключаем сами и просим
# перечитать CSS: без --reload-css смена симлинка ничего не изменит до
# перезапуска демона.
if [ -d "$SWAYNC_DIR" ]; then
    ln -sfn "style-${MODE}.css" "$SWAYNC_DIR/style.css"
    if pgrep -x swaync >/dev/null 2>&1 && command -v swaync-client >/dev/null 2>&1; then
        timeout 2 swaync-client --reload-css >/dev/null 2>&1 || true
    fi
fi

# --- 4. Hyprland: цвета рамок -------------------------------------------
# `hyprctl keyword` тут НЕ работает: конфиг на Lua, и команда отвечает
# «keyword can't work with non-legacy parsers. Use eval.» — причём молча, с
# нулевым кодом возврата, так что скрипт бы спокойно поехал дальше, а рамки
# остались бы прежними. Настройки на лету меняются через eval с hl.config().
if [ "$MODE" = "light" ]; then
    INACTIVE_BORDER="rgba(d5c4a144)"
else
    INACTIVE_BORDER="rgba(28282800)"
fi
hyprctl eval "hl.config({ general = { col = {
    active_border   = \"rgba(ffffffcc)\",
    inactive_border = \"$INACTIVE_BORDER\",
} } })" >/dev/null 2>&1

# --- 5. Nvim: пнуть все живые инстансы ----------------------------------
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
for sock in "$RUNTIME_DIR"/nvim.*.0 /tmp/nvim.*/0; do
    [ -e "$sock" ] || continue
    nvim --server "$sock" --remote-send ":set background=$MODE<CR>" 2>/dev/null
done

# --- 6. VSCode ----------------------------------------------------------
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
if [ -f "$VSCODE_SETTINGS" ]; then
    if [ "$MODE" = "light" ]; then
        sed -i 's/"workbench.colorTheme": ".*"/"workbench.colorTheme": "Bearded Theme Milkshake Mint"/' "$VSCODE_SETTINGS"
    else
        sed -i 's/"workbench.colorTheme": ".*"/"workbench.colorTheme": "Gruvbox Dark Hard"/' "$VSCODE_SETTINGS"
    fi
fi

# --- 7. WezTerm (если вдруг появится) -----------------------------------
if [ -d "$(dirname "$WEZTERM_THEME")" ]; then
    echo "$MODE" > "$WEZTERM_THEME"
fi

echo "$MODE" > "$STATE_FILE"

# --- 8. Предупреждение про Chromium -------------------------------------
# Переход dark -> light Chromium-приложения не отрабатывают (баг апстрима).
# Перезапуск порталов тут НЕ помогает (проверено), помогает только рестарт
# самого приложения. Поэтому просто предупреждаем.
if [ "$MODE" = "light" ] && command -v notify-send >/dev/null 2>&1; then
    if pgrep -x chrome >/dev/null 2>&1 || pgrep -x brave >/dev/null 2>&1 || pgrep -x electron >/dev/null 2>&1; then
        notify-send -a "theme" -u low "Тема: light" \
            "Chromium/Electron не умеют возвращаться в светлую тему на лету — перезапусти браузер." \
            9>&- 2>/dev/null &
    fi
fi

exit 0
