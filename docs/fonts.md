# Шрифты интерфейса

## Перед заменой

Положить файл шрифта в `~/.local/share/fonts/<Family>/`, затем проверить
внутреннее имя семейства и обновить кэш:

```bash
fc-scan --format '%{family}\n' ~/.local/share/fonts/<Family>/*.ttf | sort -u
fc-cache -f
fc-match 'Suisse Intl'
```

В конфиги нужно писать именно имя из `fc-scan`, а не имя файла.

### Важный разрыв при новой установке

Файлы SF Pro проприетарные и намеренно не хранятся в публичном репозитории.
Текущий `restore-config.sh` ставит Inter Tight как переносимый fallback и Nerd
Fonts, но сам SF Pro не устанавливает, хотя затем записывает его имя в GTK и
gsettings. Поэтому установка через LLM обязана пройти font gate из
[`PROMPT-INSTALL.md`](../PROMPT-INSTALL.md): либо владелец предоставляет
законно полученные Regular/Semibold/Bold OTF, либо явно согласуется замена во
всех перечисленных ниже точках. Молчаливый fallback не считается успехом.

## Системный пропорциональный шрифт

Источник правды в dotfiles:

- `.config/gtk-3.0/settings.ini` — `gtk-font-name=...`;
- `.config/gtk-4.0/settings.ini` — `gtk-font-name=...`;
- `.config/fontconfig/conf.d/60-interface-fonts.conf` — семейства
  `sans-serif` и `system-ui`, а также alias `SF Pro` → `SF Pro Display`;
- `restore-config.sh` — три значения `gsettings` для обычного, документного и
  titlebar-шрифта.

Для немедленного применения, например `Suisse Intl 11`:

```bash
gsettings set org.gnome.desktop.interface font-name 'Suisse Intl 11'
gsettings set org.gnome.desktop.interface document-font-name 'Suisse Intl 11'
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Suisse Intl SemiBold 11'
fc-cache -f
```

Те же имена обязательно записать в файлы репозитория выше, иначе
`restore-config.sh` при следующем восстановлении вернёт старое значение.

## Компоненты с собственным CSS

Они не обязаны наследовать GTK, поэтому семейство меняется отдельно:

- Waybar: `.config/waybar/style-light.css` и `style-dark.css`, глобальный `*`;
- Rofi: `launcher.rasi`, `wallpaper.rasi`, `alt-tab.rasi`, `powermenu.rasi`;
- SwayNC: `.config/swaync/style-common.css`;
- Ghostty: `.config/ghostty/config` (`font-family` и `font-thicken-strength`).

В `powermenu.rasi` у `element-text` оставлен `JetBrainsMono Nerd Font`: это не
обычный текст, а пиктограммы питания. Его заменять пропорциональным шрифтом
нельзя — символы исчезнут.

## Chrome использует общий системный шрифт

Отдельных keyfile, Fontconfig-матрицы, wrapper и пользовательского desktop-файла
для Chrome нет. Штатный `google-chrome.desktop` запускает браузер, а его UI
наследует `gtk-font-name` из `.config/gtk-3.0/settings.ini` и общий gsettings.
Поэтому шрифт Chrome меняется вместе со всей системой. После изменения нужно
полностью закрыть Chrome и открыть снова.
