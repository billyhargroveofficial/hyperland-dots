# Промпт для LLM: установка Hyperland Dots

Этот файл — обязательный контракт для AI-агента, который устанавливает или
восстанавливает этот репозиторий. Пользователю достаточно сказать агенту:

> Прочитай `AGENTS.md`, `CLAUDE.md` и `PROMPT-INSTALL.md`, выполни preflight,
> покажи отчёт и только после моего подтверждения начинай установку.

Главное правило: наличие скопированных конфигов ещё не означает успешную
установку. Агент должен доказать, что зависимости, точные семейства шрифтов,
сервисы, внешние файлы и аппаратные предпосылки действительно присутствуют, а
приложения не перешли на молчаливые fallback-значения.

## Роль и порядок работы

Ты устанавливаешь персональные dotfiles для Arch Linux + Hyprland. Не запускай
`restore-config.sh` сразу после clone. Работай в четыре фазы:

1. Прочитай инструкции и проведи только read-only preflight.
2. Покажи пользователю отчёт `PASS / WARN / BLOCKED`, точный план изменений,
   запросы `sudo`, ожидаемые перезапуски и необходимость reboot/relogin.
3. Дождись явного подтверждения пользователя.
4. Устанавливай, затем проведи postflight по критериям ниже. Не называй работу
   завершённой, пока обязательные проверки не прошли.

Если это не исходная целевая машина, а перенос на другое железо, сначала
отдели переносимые пользовательские настройки от аппаратно-зависимых. Не
применяй настройки этой машины только потому, что они находятся в Git.

## Сначала прочитай

До любых изменений полностью прочитай:

- `AGENTS.md` и `CLAUDE.md`;
- `README.md`;
- `docs/fonts.md`;
- `docs/private-state.md`;
- `docs/hyprland.md`;
- `docs/waybar.md`;
- `docs/notifications.md`;
- `docs/bluetooth-audio.md`;
- `docs/video-wallpaper.md`;
- `system/README.md`;
- сам `restore-config.sh`, особенно массивы пакетов, `copy_configs()` и `main()`.

Документация описывает принятые решения, но источником фактических действий
остаётся текущая версия скрипта. Если документ и код расходятся, остановись,
покажи расхождение и предложи исправление — не выбирай молча одну из версий.

## Жёсткие запреты

- Не запускай `restore-config.sh` от root. `sudo` используется только внутри
  отдельных шагов; пароль пользователь вводит в своём терминале, не в чате.
- Не перезаписывай существующие конфиги без аудита и согласованного бэкапа.
  `copy_configs()` удаляет целые live-каталоги через `rm -rf` перед копированием.
- Не запускай полный restore на уже настроенной живой машине, если достаточно
  точечной синхронизации нескольких файлов.
- Не перезапускай Hyprland, Waybar, Ghostty, порталы, сеть, VPN или всю сессию
  во время активной работы пользователя без предупреждения и подтверждения.
  В конце полного restore Waybar и `awww-daemon` перезапускаются, а Hyprland
  получает reload.
- Не выводи и не добавляй в Git VLESS-ссылки, токены, приватные SSH-ключи,
  содержимое `~/.codex/`, OpenCode или другие секреты/runtime-данные.
- Не удаляй OpenCode и не вырезай `~/.local/bin/opencode` из `PATH`.
- Не возвращай удалённые DMS, Niri, Hermes, CC Switch или старый voice-input
  без нового явного запроса владельца.
- Не утверждай, что шрифт установлен, проверив только имя в CSS/gsettings.
  Fontconfig может молча подставить другой файл.
- Не считай отсутствие ошибки доказательством успеха: Waybar, Rofi, SwayNC,
  GTK и Chrome часто принимают неизвестное семейство и используют fallback.

## Preflight: репозиторий и сохранность данных

Выполни read-only проверки:

```bash
git status --short --branch
git remote -v
./scripts/check-repo.sh
```

Затем:

- выясни, свежая это установка или существующая рабочая среда;
- покажи все незакоммиченные изменения и не присваивай их себе;
- сравни отслеживаемые конфиги с live-копиями в `$HOME`;
- отдельно перечисли файлы, которые будут удалены или заменены;
- согласуй место бэкапа и проверь, что там достаточно свободного места;
- не включай в публичный бэкап секреты из `docs/private-state.md`;
- проверь доступ к Arch mirrors, AUR и GitHub до начала длинной установки;
- проверь, что `sudo` работает, но не проси прислать пароль сообщением.

Если рабочее дерево грязное, live-конфиги отличаются или бэкап не согласован,
статус preflight — `BLOCKED`, а не «можно продолжать».

## Preflight: целевая машина

Эти dotfiles аппаратно-зависимы. Текущая целевая конфигурация:

- Arch Linux, Hyprland, zsh;
- Ryzen 9 5950X, плата ASUS X570-F, hwmon `nct6798`;
- NVIDIA RTX 3080 Ti с проприетарным драйвером;
- `DP-3` слева и `DP-2` справа, оба 2560×1440 с `highrr`;
- рабочие столы `DP-2`: 1–10, `DP-3`: 11–20;
- яркость внешних мониторов через `ddcci-backlight`;
- SDDM с X11-greeter;
- системные сервисы из `system/` и обратный SSH-туннель на конкретную
  инфраструктуру владельца.

Собери факты, не меняя систему:

```bash
cat /etc/os-release
uname -r
id
printf '%s\n' "$SHELL"
hyprctl version
hyprctl monitors -j
lspci -nn
ls /sys/class/hwmon/*/name 2>/dev/null
ddcutil detect 2>/dev/null
```

На другой машине не устанавливай автоматически GPU/system fan, DDC/CI,
мониторные правила, SDDM, SSH-туннель и NVIDIA-конфигурацию. Сначала выдай
таблицу `применимо / нужно адаптировать / пропустить` и получи решение
пользователя.

Для NVIDIA отдельно проверь:

- используются проприетарные модули, а не `nvidia-open`;
- версии `nvidia-utils-beta` и `nvidia-beta-dkms` совпадают;
- ядро имеет matching `linux-headers`;
- изменение `mkinitcpio`, параметров ядра и GSP действительно нужно;
- reboot ещё не обещан и будет выполнен только после подтверждения.

## Preflight: зависимости и версии

Не копируй статический список пакетов из этого prompt. Извлеки актуальные
списки из `install_pacman_packages()`, `install_aur_packages()` и отдельных
setup-функций текущего `restore-config.sh`, затем покажи:

- что уже установлено;
- что будет установлено из pacman;
- что будет собрано из AUR;
- какие пакеты недоступны или конфликтуют;
- какие сервисы будут enabled/started;
- какие шаги требуют сети, `sudo`, logout или reboot.

Минимальные version gates для текущей архитектуры:

- Hyprland `>= 0.55`: основной конфиг написан на Lua;
- Waybar `>= 0.15`: автоматический выбор `style-<appearance>.css` через портал;
- Ghostty `>= 1.2`: light/dark theme через портал без переписывания конфига;
- рабочие `rofi-wayland`, SwayNC, `awww`, PipeWire + WirePlumber;
- `xdg-desktop-portal-gtk`, `jq`, Python, `lm_sensors`, ImageMagick, `ffmpeg`,
  `wl-clipboard`, `cliphist`, `grim`, `slurp`, `wf-recorder`;
- Fontconfig/Pango (`fc-list`, `fc-scan`, `fc-match`, `fc-cache`) для проверки
  реального разрешения семейств, а не только строк в настройках;
- `gnome-themes-extra` для настоящего `Adwaita-dark` и Papirus для Rofi;
- Nerd Font и emoji-шрифт из следующего раздела.

Новая версия допустима только после проверки конфигов. Не понижай пакеты и не
заменяй их похожими по названию без объяснения пользователю.

## Обязательный font gate

### Источники правды

Текущий интерфейс ожидает:

- системный UI: `SF Pro Display`, обычный текст Regular, выделение Semibold
  (CSS weight `600`);
- GTK/gsettings: `SF Pro Display, Semi-Bold 11`;
- Waybar и SwayNC: `SF Pro Display`, weight `600`;
- Rofi: `SF Pro Display` с Regular/Semibold/Bold;
- Ghostty и generic `monospace`: `JetBrainsMono Nerd Font`;
- иконки powermenu Rofi: `JetBrainsMono Nerd Font`;
- emoji: `Noto Color Emoji`/`noto-fonts-emoji`.

Проприетарные файлы SF Pro намеренно не лежат в Git. Текущий
`restore-config.sh` устанавливает переносимый Inter Tight и Nerd Fonts, но
**не устанавливает SF Pro**, после чего всё равно записывает имя SF Pro в GTK
и gsettings. Это известный разрыв, который LLM обязана закрыть до применения
настроек.

Inter Tight в репозитории — только свободный fallback-файл. Пока конфиги явно
называют SF Pro, наличие Inter Tight не делает font gate успешным.

### Проверка до установки

```bash
fc-cache -f
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' 'SF Pro Display'
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' 'SF Pro Display:style=Semibold'
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' 'SF Pro Display:style=Bold'
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' 'JetBrainsMono Nerd Font'
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' 'Noto Color Emoji'
```

Для SF Pro должны разрешаться реальные читаемые файлы SF Pro, а Semibold
должен показывать style `Semibold`, не `Regular` и не другой шрифт. Проверяй
внутренние имена через `fc-scan`, а не имена файлов:

```bash
fc-scan --format '%{family[0]} | %{style[0]}\n' \
  ~/.local/share/fonts/SF-Pro/SF-Pro-Display-Semibold.otf
```

Если SF Pro отсутствует, до установки есть только два допустимых пути:

1. Попросить владельца предоставить законно полученные файлы SF Pro, установить
   Regular/Semibold/Bold в пользовательский font directory и повторить gate.
2. Получить явное согласие на переносимую замену и согласованно изменить **все**
   точки из `docs/fonts.md`: GTK3/GTK4, Fontconfig, gsettings в restore,
   Waybar light/dark, все темы Rofi, SwayNC и документацию.

Нельзя скачивать неизвестный архив, подставлять Inter Tight только в одном
файле или оставлять настройки SF Pro при фактическом fallback.

После установки дополнительно проверь:

```bash
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' sans-serif
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' system-ui
fc-match -f '%{family[0]} | %{style[0]} | %{file}\n' monospace
gsettings get org.gnome.desktop.interface font-name
gsettings get org.gnome.desktop.interface document-font-name
gsettings get org.gnome.desktop.wm.preferences titlebar-font
```

Chrome наследует общий GTK/system font и требует полного обычного закрытия и
повторного запуска. Не создавай для него отдельный wrapper, desktop-файл или
Fontconfig-матрицу. Проверка Chrome до его рестарта не считается провалом
общей установки.

## Приватные данные и AI-харнессы

Репозиторий не является полным бэкапом `$HOME`. До установки выясни, сохранены
ли отдельно:

- `~/.ssh/`;
- `~/.config/sing-box/config.json`;
- `~/.codex/`;
- `~/.opencode/`, `~/.config/opencode/`, `~/.local/share/opencode/`;
- `~/.agents/memory/`;
- OAuth/session state приложений;
- `~/wallpapers/` и другие локальные медиа.

Не читай содержимое секретов без необходимости и не показывай его в отчёте.
Проверяй наличие, владельца и permissions. Состояние Codex/OpenCode нельзя
копировать в репозиторий или пересоздавать из dotfiles.

`setup_singbox()` интерактивно просит VLESS URL. Не вставляй секрет в командную
строку, лог, prompt или commit. Если рабочий config уже восстановлен отдельно,
скрипт обязан его сохранить.

## Внешние обои и nv-wallpaper

Статичные и видеообои не хранятся в Git. Кнопка Waybar и интеграция находятся
в dotfiles, но C++-рендерер остаётся отдельным checkout `~/nv-wallpaper`, а
видео должно быть восстановлено отдельно.

Канонический текущий источник:

```text
~/wallpapers/video/Tahiti-Coast-Apple-1440p24-slow.mov
SHA-256: 3cbd003b00b950bc8af8a48d6deba20e67321a4977e5ecc5b0a6fbebb815f44c
2560x1440, HEVC, 24 fps, один самостоятельный видеопоток
```

Если файла или проверенного URL нет, не скачивай случайный одноимённый ролик.
Пометь видеообои как `WARN: external asset missing`; остальной desktop может
работать со статичным `awww`. После получения файла проверь `sha256sum` и
`ffprobe`, затем запускай `~/nv-wallpaper/scripts/install-user.sh` обычным
пользователем с фактическими именами outputs.

## Выбор режима установки

### Свежая целевая машина

После успешного preflight и подтверждения можно запускать полный скрипт:

```bash
cd ~/hyperland-dots
./restore-config.sh
```

Запиши полный лог, собери каждый `[WARN]` и исправь его. Ненулевой exit code
нельзя игнорировать. Скрипт интерактивный, меняет systemd, SSH, SDDM, драйверы,
initramfs, группы пользователя и live-конфиги; заранее предупреди о каждом
классе изменений.

### Уже работающая машина

Не запускай полный restore по умолчанию. Составь минимальный план: поставить
недостающие зависимости, затем синхронизировать только нужные repo/live-файлы
и root-копии. Перед заменой каждого live-каталога проверь пользовательские
изменения. Не перезапускай всю сессию ради CSS или одного скрипта.

## Postflight: синтаксис и конфиги

Минимальные проверки:

```bash
cd ~/hyperland-dots
./scripts/check-repo.sh
git status --short --branch
luac -p .config/hypr/hyprland.lua
jq empty .config/waybar/config
jq empty .config/swaync/config.json
ghostty +show-config >/dev/null
rofi -no-config -theme .config/rofi/launcher.rasi -dump-theme >/dev/null
rofi -no-config -theme .config/rofi/wallpaper.rasi -dump-theme >/dev/null
rofi -no-config -theme .config/rofi/alt-tab.rasi -dump-theme >/dev/null
rofi -no-config -theme .config/rofi/powermenu.rasi -dump-theme >/dev/null
```

Также:

- докажи, что repo/live-копии совпадают там, где они должны совпадать;
- не считай различием ожидаемое runtime-состояние темы, кэши и секреты;
- проверь относительные `style.css` symlinks Waybar и SwayNC;
- запусти `~/.config/waybar/scripts/accent.sh refresh` только если Waybar уже
  поддерживает модульные realtime-сигналы;
- проверь наличие пар `*-light.svg`/`*-dark.svg` в cache, а не только CSS;
- не делай полный reload Waybar ради переключения темы;
- не перезапускай VPN и не запускай его дочерним процессом Waybar.

## Postflight: сервисы и железо

Проверь применимые к машине пункты:

```bash
systemctl is-active sddm gpu-fan system-fan bluetooth nvidia-persistenced
systemctl is-active hk-translator kbd-layout-toggle ddcci-bind sshd
systemctl --user is-active pipewire wireplumber pipewire-pulse
systemctl --user is-active bt-audio-autoswitch bt-audio-recover
hyprctl monitors
pactl info
ls /sys/class/backlight/
sudo /usr/bin/sshd -t
```

Для VPN выполняй только структурную проверку без печати секрета:

```bash
sing-box check -c ~/.config/sing-box/config.json >/dev/null
```

После согласованного reboot/relogin отдельно проверь:

- GSP показывает `N/A`, а NVIDIA fan не равен 0%;
- версии kernel module и NVIDIA userspace совпадают;
- оба монитора работают на максимальной частоте из EDID;
- количество `ddcci*` соответствует подключённым DDC/CI-мониторам;
- членство в группе `video` реально применилось;
- SDDM не упал на QML/QtMultimedia;
- SSH остаётся key-only;
- раскладка переключается на всех физических и виртуальных клавиатурах.

Root-копии из `system/` должны совпадать с установленными файлами. Для любого
расхождения покажи diff без секретов и получи разрешение перед заменой.

## Postflight: визуальная приёмка

Попроси пользователя подтвердить, а не угадывай по отсутствию ошибок:

- Waybar показывает три островка, телеметрию и непрозрачные SVG правильного
  light/dark-оттенка;
- рабочие столы не меняют ширину, tooltips не появляются;
- Rofi без рамки, выбранный пункт имеет контрастный текст;
- SwayNC без action-кнопок и с правильным правым padding;
- Ghostty использует JetBrainsMono Nerd Font и opacity `0.7` в обеих темах;
- GTK/Waybar/Rofi/SwayNC/Chrome действительно показывают SF Pro Display, а не
  похожий fallback;
- Ctrl+Y меняет тему без уведомления и без рестарта Waybar/VPN;
- аудио, Bluetooth, яркость, запись экрана и ручные видеообои работают.

## Формат итогового отчёта

Закончи установку таблицей или коротким списком:

- `PASS`: что проверено фактической командой и каким результатом;
- `WARN`: что опционально отсутствует и как это влияет;
- `BLOCKED`: что требует файла, секрета, sudo, reboot или решения владельца;
- какие файлы и сервисы были изменены;
- какие процессы перезапускались и почему;
- требуется ли Chrome restart, relogin или reboot;
- подтверждение, что секреты и native state Codex/OpenCode не попали в Git.

Фраза «установка готова» допустима только если обязательные gates, особенно
font gate, прошли без fallback. Иначе честно сообщи «установка частичная».
