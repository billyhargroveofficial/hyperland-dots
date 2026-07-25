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
WEZTERM_THEME="$HOME/.config/wezterm/theme.txt"
GTK3_INI="$HOME/.config/gtk-3.0/settings.ini"

current=$(cat "$STATE_FILE" 2>/dev/null || echo "dark")

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
if [ "$MODE" = "light" ]; then
    ln -sf "$WAYBAR_DIR/style-light.css" "$WAYBAR_DIR/style.css"
else
    ln -sf "$WAYBAR_DIR/style-dark.css" "$WAYBAR_DIR/style.css"
fi

# --- 4. Hyprland: цвета рамок -------------------------------------------
if [ "$MODE" = "light" ]; then
    hyprctl keyword general:col.active_border "rgba(ffffffcc)" >/dev/null 2>&1
    hyprctl keyword general:col.inactive_border "rgba(d5c4a144)" >/dev/null 2>&1
else
    hyprctl keyword general:col.active_border "rgba(ffffffcc)" >/dev/null 2>&1
    hyprctl keyword general:col.inactive_border "rgba(28282800)" >/dev/null 2>&1
fi

# --- 5. Nvim: пнуть все живые инстансы ----------------------------------
for sock in /run/user/1000/nvim.*.0 /tmp/nvim.*/0; do
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
            "Chromium/Electron не умеют возвращаться в светлую тему на лету — перезапусти браузер." 2>/dev/null &
    fi
fi

exit 0
