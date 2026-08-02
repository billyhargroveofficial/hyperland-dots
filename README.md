# Мои Dotfiles для Hyprland

Персональная конфигурация для Hyprland + waybar + awww + rofi на Arch Linux.

Целевая машина: Ryzen 9 5950X / 96 ГБ DDR4 / RTX 3080 Ti / 2× Samsung 980 PRO 1TB
на ASUS ROG STRIX X570-F GAMING. Часть конфигов привязана именно к этому железу
(кривая системных вентиляторов написана под чип мониторинга `nct6798`, GPU-кривая — под 3080 Ti).

## Особенности

- **Waybar** — три островка: безымянные рабочие столы без app-иконок, Lucide SVG
  для CPU/GPU/RAM/VRAM/SSD и системных индикаторов, монохромные tray-иконки;
  слева SVG-переключатели акцента и dark/light
- **Запись экрана кнопкой** — 720p60, h264_nvenc, в `~/records` (см. `docs/screen-recording.md`)
- **Видеообои вручную** — отдельная play/pause-кнопка Waybar для Vulkan-рендерера
  `nv-wallpaper`, без автозапуска и правил по активным окнам (см. `docs/video-wallpaper.md`)
- **Два монитора**, столы делятся по экранам и выбираются по курсору (`docs/hyprland.md`)
- **Конфиг Hyprland на Lua** — формат с 0.55, бинды умеют произвольные функции
- **Единая тема** — ghostty, waybar, VSCode, nvim, GTK, rofi, swaync
- **Единый UI-шрифт** — SF Pro Display SemiBold в Waybar, Rofi, SwayNC, GTK и Chrome
- **Dark/Light toggle** — переключение всех тем по Ctrl+Y
- **Плавные анимации** — настроенные bezier curves для окон и workspaces
- **VPN с split tunneling** — sing-box (VLESS + Reality), .ru домены напрямую
- **NVIDIA GPU fan control** — динамическое управление вентиляторами на Wayland
- **LazyVim** — nvim с прозрачным gruvbox-material
- **SwayNC** — чистые уведомления без action-кнопок, SF Pro Display и динамический акцент панели
- **Codex во вкладках tmux** — иконка и состояния агента с запасным детектом
  процесса по полной командной строке (см. `harness-hooks/README.md`)
- **Обратный SSH-туннель** — постоянный доступ через `nareshka.ru:2223`,
  без password login и без restart-loop при занятом удалённом порте
- **Codex CLI и OpenCode** — поддерживаемые AI-харнессы; их нативное состояние
  не управляется dotfiles

## Быстрая установка

```bash
git clone https://github.com/billyhargroveofficial/hyperland-dots ~/hyperland-dots
cd ~/hyperland-dots
chmod +x restore-config.sh
./restore-config.sh
```

Скрипт установит зависимости и настроит desktop.

Кнопка видеообоев входит в dotfiles, а сам `nv-wallpaper` остаётся отдельным
репозиторием и автоматически не клонируется. Если он уже лежит в
`~/nv-wallpaper`, пользовательская установка выглядит так:

```bash
cd ~/nv-wallpaper
./scripts/install-user.sh /absolute/path/to/video.mov DP-2,DP-3
```

После этого воспроизведение включается только вручную кнопкой play в Waybar.
Обычный статичный фон `awww` всё время остаётся под видео.

Запускать **обычным пользователем**, не от root — скрипт сам зовёт `sudo` там, где нужно.
Он продолжает работу после единичного сбоя сети, собирает все `[WARN]` и
возвращает ненулевой код, если восстановление получилось неполным.

## Проверка репозитория

```bash
./scripts/check-repo.sh
git config core.hooksPath .githooks
```

Скрипт проверяет Bash/Zsh/Python, JSON/JSONC, TOML, Lua, whitespace и типичные
литералы секретов. `restore-config.sh` включает тот же pre-commit автоматически.
Workflow `.github/workflows/validate.yml` повторяет проверку на GitHub, если
Actions разрешены в настройках репозитория.

## Прежде чем что-то править

В [`docs/`](docs/) собраны грабли, на которые уже наступали — с причинами, а не
только рецептами. Стоит заглянуть туда до того, как менять панель, запись
экрана, уведомления или конфиг Hyprland:

| | |
|---|---|
| [`docs/waybar.md`](docs/waybar.md) | островки, SVG-телеметрия, монохромные app/tray-иконки, выбор акцента и особенности GTK3 |
| [`docs/video-wallpaper.md`](docs/video-wallpaper.md) | ручная play/pause-кнопка, установка отдельного Vulkan-рендерера и сохранение позиции |
| [`docs/hyprland.md`](docs/hyprland.md) | конфиг на Lua и что миграция ломает молча, два монитора, Alt+Tab |
| [`docs/screen-recording.md`](docs/screen-recording.md) | wf-recorder + NVENC: несуществующие флаги, диапазон яркости |
| [`docs/notifications.md`](docs/notifications.md) | swaync и почему он не следует за системной темой сам |
| [`docs/fonts.md`](docs/fonts.md) | все точки замены единого системного шрифта, включая Chrome |
| [`docs/bluetooth-audio.md`](docs/bluetooth-audio.md) | наушники: заикания на LDAC и почему кодек прибит к AAC, потеря BlueZ-endpoints |
| [`docs/private-state.md`](docs/private-state.md) | что намеренно не лежит в публичной репе и нужно бэкапить отдельно |

## AI-харнессы

На машине поддерживаются Codex CLI и OpenCode. Dotfiles не устанавливают их и
не генерируют нативные каталоги `~/.codex/`, `~/.opencode/`,
`~/.config/opencode/` и `~/.local/share/opencode/`: авторизация, MCP, история и
другие runtime-данные остаются локальными.


## Драйвер NVIDIA — проприетарный, не open

Это не вкусовщина, а обязательное условие для двух мониторов на высокой частоте.

Открытые модули (`nvidia-open`) построены на **GSP** — сопроцессоре GPU. Именно GSP даёт
рваные анимации и просадки FPS на Wayland при 180/200 Гц
([open-gpu-kernel-modules #693](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/693),
[Hyprland #9029](https://github.com/hyprwm/Hyprland/issues/9029)). Выключить GSP можно
только на проприетарных модулях — на открытых параметр не работает в принципе,
так как без GSP они не работают вообще.

Arch выкинул проприетарные модули из репозиториев начиная с ветки 590, поэтому они
берутся из AUR. Версия модулей обязана совпадать с версией utils:

```bash
yay -S nvidia-utils-beta nvidia-beta-dkms    # 610.43.03, мейнтейнер dbermond
```

Обязательные настройки после установки драйвера:

```bash
# 1. Заглушить GSP — иначе всё вышеописанное вернётся
echo 'options nvidia NVreg_EnableGpuFirmware=0' | sudo tee /etc/modprobe.d/nvidia-gsp.conf

# 2. Ранний KMS для Wayland
sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
sudo mkinitcpio -P

# 3. Параметры ядра в загрузочную запись
#    nvidia_drm.modeset=1 nvidia_drm.fbdev=1
```

Проверка, что GSP действительно выключен:

```bash
grep EnableGpuFirmware /proc/driver/nvidia/params   # должно быть 0
nvidia-smi -q | grep 'GSP Firmware'                # должно быть N/A
```

| Грабля | Что происходит |
|--------|----------------|
| Репный `nvidia-settings` | Конфликтует с `nvidia-settings-beta`. Не ставить, не добавлять в списки пакетов |
| Обновление `nvidia-utils` из репов | Уедет на версию новее модулей → X/Wayland не стартанёт. Держать обе половины из AUR |
| Новое ядро | DKMS пересобирает сам, но `linux-headers` и `dkms` должны быть в системе |

## Разметка дисков (свежая установка)

Два одинаковых 980 PRO — модели не отличить, только по серийнику. Износ у них разный,
поэтому роли назначены осознанно: система на уставший диск, `/home` на свежий.

| Диск | Serial | Износ | Роль |
|------|--------|-------|------|
| `nvme1n1` | `S5GXNS0RC45064M` (EUI …bac7) | 27 % | ESP 1 ГБ `/boot` + ext4 `/` |
| `nvme0n1` | `S5GXNS0RC45054N` (EUI …babd) | 11 % | ext4 `/home` целиком |

На `/home` идёт основная запись — Rust `target/`, ML-модели, кэши сборки. Поэтому он
на менее изношенном диске. Резерв ext4 снижен с 5 % до 1 % (`mkfs.ext4 -m 1`) — это
+37 ГБ полезного места на каждом диске.

Swap-раздела нет: с 96 ГБ он бессмысленен, вместо него zram 8 ГБ через `zram-generator`.
Гибернация в такой схеме недоступна — потребовала бы 96+ ГБ на диске.

Загрузчик — systemd-boot. Запись в NVRAM создаётся **не** через `bootctl install`
внутри chroot: там он молча пишет «skipping EFI variable modifications» и запись
не появляется. Из живой системы или с ISO:

```bash
efibootmgr --create --disk /dev/nvme1n1 --part 1 \
  --loader '\EFI\systemd\systemd-bootx64.efi' --label 'Linux Boot Manager' --unicode
```

### BIOS

| Пункт | Значение |
|-------|----------|
| Secure Boot → OS Type | Other OS |
| CSM | Disabled |
| Fast Boot | Disabled |
| NVMe RAID Mode (Advanced → AMD PBS) | Disabled |
| SATA Mode | AHCI |
| Ai Overclock Tuner | D.O.C.P. (иначе 96 ГБ крутятся на 2666 вместо 3200) |
| Above 4G Decoding / Re-Size BAR | Enabled |

Del — вход в BIOS, F8 при POST — меню загрузки.

## Сеть

Wi-Fi — **USB-донгл Realtek 8822BU** (`rtw88_8822bu`), ему нужен пакет
`linux-firmware-realtek`, иначе после установки сети не будет вообще.

Имя интерфейса не стабильно (`wlan1` на ISO → `wlan0` в системе), поэтому в профиле
NetworkManager **не прибивать** `interface-name`. Роутер переставляет DHCP-аренды,
так что для стабильного доступа по SSH на соединение навешен статический алиас:

```bash
nmcli connection modify <имя> +ipv4.addresses 192.168.1.240/24
```

DHCP при этом продолжает работать, адрес просто добавляется вторым. Плюс `avahi` +
`nss-mdns` дают имя `mujik.local`, но mDNS работает через раз — статический алиас надёжнее.

## Сочетания клавиш

### Основные

| Клавиша | Действие |
|---------|----------|
| `Alt + W` | Терминал (ghostty) |
| `Alt + Q` | Закрыть окно |
| `Alt + Ctrl + M` | Выход из Hyprland |
| `Alt + E` | Файловый менеджер (nautilus) |
| `Alt + Space` | Лаунчер (rofi) |
| `Alt + V` | Буфер обмена (cliphist + rofi) |
| `Alt + F` | Fullscreen (повторное нажатие выводит обратно) |
| `Alt + T` | Toggle floating |
| `Alt + S` | Закрепить окно поверх всех (тайловое сначала станет плавающим) |
| `Alt + Shift` | Переключить раскладку us/ru |
| `Alt + Tab` | Следующее окно (нативный `cyclenext`, без оверлея) |
| `Alt + Shift + Tab` | Предыдущее окно |
| `Ctrl + Y` | Toggle dark/light тема |
| `F10` | Переключить `$mainMod` между ALT и SUPER |

> Выход из сессии сидит на `Alt + Ctrl + M`, а не на `Alt + M`. При
> `$mainMod = ALT` одиночный `Alt + M` — это мнемоника меню в любом GTK/Qt
> приложении, и случайное нажатие мгновенно убивало сессию без подтверждения.

### VPN и система

| Клавиша | Действие |
|---------|----------|
| `Alt + P` | Toggle VPN (sing-box) |
| `Alt + Ctrl + T` | Mission Center |
| `Alt + Ctrl + W` | Restart Hyprland + waybar + awww |
| `Print` / `Alt + Ctrl + S` | Скриншот области |

### Навигация (Vim-style)

| Клавиша | Действие |
|---------|----------|
| `Alt + H/J/K/L` | Фокус между окнами |
| `Alt + Shift + H/J/K/L` | Переместить окно |
| `Alt + Ctrl + H/J/K/L` | Resize окна |
| `Alt + 1-9, 0` | Стол 1-10 **того монитора, где курсор** |
| `Alt + Ctrl + 1-9, 0` | Перенести окно на этот стол (в т.ч. на соседний экран) |
| `Alt + колесо` | Столы монитора под курсором: вперёд — вправо, назад — влево; по кругу внутри десятка |

> Цифра выбирает стол по монитору **под курсором**: над `DP-2` это столы 1-10,
> над `DP-3` — 11-20. Курсор, а не клавиатурный фокус — при `follow_mouse = 1`
> они почти всегда совпадают, но после Alt+Tab или окна, открывшегося на
> соседнем экране, цифры продолжают работать по взгляду.

## Мониторы

Мониторов два, оба 2560x1440:

```
┌───────────────┬───────────────┐
│     DP-3      │     DP-2      │
│     новый     │    старый     │
│   180.06 Гц   │    200 Гц     │
│  столы 11-20  │  столы 1-10   │
│      0x0      │    2560x0     │
└───────────────┴───────────────┘
```

**Сначала посмотри, в какой разъём монитор реально воткнут**: `hyprctl monitors`.
Строка на несуществующий разъём просто не применяется — молча, без ошибки, — и
срабатывает catch-all. Так монитор больше суток проработал на 59.95 Гц вместо
200: в конфиге стоял `DP-2`, а кабель был в `DP-3`. Разъёмы с тех пор переехали:
старый монитор теперь в `DP-2`, новый — в `DP-3`.

Второе: catch-all должен быть `highrr`, а не `preferred`. **`preferred` берёт
режим из EDID, а он у большинства мониторов 60 Гц** — именно это и давало 59.95.

Третье: **частоту лучше не прописывать явно.** Строка `DP-3, 2560x1440@200`
пережила перетыкание кабелей и стала требовать 200 Гц от нового монитора, у
которого потолок 180.06 — режим не применился, и снова спас catch-all. `highrr`
берёт максимум из EDID у каждого монитора отдельно.

```lua
hl.monitor({ output = "",     mode = "highrr", position = "auto",   scale = 1 })
hl.monitor({ output = "DP-3", mode = "highrr", position = "0x0",    scale = 1 })
hl.monitor({ output = "DP-2", mode = "highrr", position = "2560x0", scale = 1 })
```

Проверка после правки:
```bash
hyprctl monitors -j | jq '.[] | {name, x, y, refreshRate}'
```

Не забыть, что на разъём монитора завязаны ещё места: таблица `wsBase` в
`hyprland.lua` (деление столов), `hyprpaper.conf` и аргумент `-o` у
`nwg-dock-hyprland`.

## Яркость внешнего монитора

У десктопа нет `/sys/class/backlight` — это интерфейс подсветки ноутбучных
матриц. Внешний монитор управляется по **DDC/CI** через i2c прямо по кабелю.
Другого способа менять настоящую яркость не существует: `hyprsunset` и гамма
лишь затемняют картинку, подсветка при этом продолжает жарить на 100%.

Гонять `ddcutil` из скрипта не годится — **~600 мс на вызов**. Вместо этого
ставится ядерный модуль `ddcci-backlight`, и монитор появляется как обычный
`/sys/class/backlight/ddcciN`: чтение мгновенное, запись 165 мс, работает
нативный модуль waybar `backlight/slider`.

Подводные камни (оба обойдены в `install_ddcci_backlight`, детали в
`system/README.md`):

- стабильный AUR-пакет **не собирается** на ядрах 7.x — нужен форк `clemax`;
- с ядра 6.8 **отключена авто-проба дисплеев**, устройство создаётся вручную
  через `new_device`, а номер i2c-шины между загрузками не фиксирован;
- мониторов два, и **отвечают они не одновременно** — скрипт ждёт подсветку на
  каждый подключённый коннектор, а не выходит по первой.

```bash
systemctl status ddcci-bind           # это он создаёт устройство — проверять первым
ddcutil detect                        # мониторы видны по DDC/CI? (должно быть два)
ls /sys/class/backlight/              # должно быть ddcciN на КАЖДЫЙ монитор
bright                                # текущая яркость по экранам
bright 1                              # диапазон 1-100, шаг колеса 5; ставится на все сразу
```

Если `ddcutil detect` показывает два дисплея, а `/sys/class/backlight/` — одну
подсветку, монитор ни при чём: не привязался `ddcci`. Лечится
`sudo systemctl restart ddcci-bind`, причина обычно в `dmesg`
(`core device [6e] probe failed: -19` — экран спал в момент привязки).

Права даёт udev-правило через группу `video`. **Членство в группе подхватывается
только при следующем логине** — до него яркость меняется только от root.

## Тема (Gruvbox)

Единая система тем с переключением по Ctrl+Y:

| Компонент | Dark | Light |
|-----------|------|-------|
| Ghostty | `gruvbox-mine-dark` (0.7 opacity) | `gruvbox-mine-light` (0.7 opacity) |
| Waybar | чёрные островки + выбранный акцент | белые островки + выбранный акцент |
| VSCode | Gruvbox Dark Hard | Bearded Theme Milkshake Mint |
| Nvim | gruvbox-material transparent | gruvbox-material transparent |
| GTK | **`Adwaita-dark`** | `Adwaita` |
| Rofi | чёрный полупрозрачный без рамки + акцент | белый полупрозрачный без рамки + акцент |
| SwayNC | тёмная поверхность + выбранный акцент | светлая поверхность + выбранный акцент |

### Три вещи, которые ломали переключение

Архитектура правильная — источник правды `gsettings org.gnome.desktop.interface`,
наружу его транслирует `xdg-desktop-portal-gtk` через `org.freedesktop.appearance`.
Ломали её три конкретные вещи, и все три устранены:

**1. `env = GTK_THEME,Adwaita:dark` в конфиге Hyprland.** Главная причина.
`GTK_THEME` — жёсткий оверрайд уровня CSS-провайдера, приоритетнее всего
остального. Любое GTK3-приложение наследовало его из сессии и оставалось тёмным
при любом положении gsettings. Замер при `color-scheme=prefer-light`:

```
с GTK_THEME=Adwaita:dark  ->  #353535  ТЁМНЫЙ   (неправильно)
без GTK_THEME             ->  #f6f5f4  СВЕТЛЫЙ  (правильно)
```

**Не добавлять эту переменную обратно.** В Hyprland Discussion #5867 она прямо
помечена как workaround, а не решение.

**2. `gsettings set gtk-theme 'Adwaita:dark'` — это no-op.** Суффикс `:dark`
GTK3 парсит только у переменной окружения, а не у значения из gsettings. Через
gsettings `Adwaita:dark` ищется как буквальное имя темы, не находится, и GTK3
падает на светлую. Правильное имя — `Adwaita-dark`.

**3. В системе не было ни одной тёмной GTK3-темы.** В `/usr/share/themes/`
лежали только `Default`, `Emacs` и `HighContrast` — переключать было физически
не на что. Ставится пакетом `gnome-themes-extra`.

### Чего делать не надо

- **Перезапускать порталы** на каждое переключение. Chromium от этого тему не
  перечитывает (проверено через DevTools Protocol), а открытые файловые диалоги
  и захват экрана рвутся.
- **Убивать waybar.** С версии 0.15 он сам слушает портал и берёт
  `style-<appearance>.css` приоритетнее `style.css`, с живой перезагрузкой CSS.
- **Переписывать конфиг ghostty через sed.** Ghostty ≥1.2 сам читает портал,
  достаточно `theme = light:...,dark:...` и `window-theme = auto`.

### Что починить нельзя

**Chromium, Chrome, Brave, Electron не возвращаются из тёмной темы в светлую.**
Баг апстрима ([chromium/40268108](https://issues.chromium.org/issues/40268108)):
light→dark на лету работает, обратно — нет. Ни перезапуск порталов, ни смена
бэкенда не помогают, только рестарт приложения. `toggle-theme.sh` про это
честно предупреждает уведомлением.

### Chrome: голубой тулбар на светлой теме

Тулбар и вкладки Chrome красятся **не темой GTK, а «цветом профиля»**
(Material You): дефолтный сид — голубой, поэтому светлый хедер остаётся
подкрашенным при любом автотемировании. Лечится:
`chrome://settings/manageProfile` → «Pick a theme color» → **Grey default
color**. Применяется мгновенно, авто dark/light продолжает работать.
Настройка живёт в `Preferences` профиля браузера — в дотфайлы её не вынести,
на новой машине кликнуть руками. Запасные варианты: свотчи Cool grey / Grey
или режим GTK в `chrome://settings/appearance` (рамка возьмёт цвета системной
темы).

## Звук

Ставить **демоны**, а не только GUI. Классическая ловушка этого репозитория: в
списке пакетов был `pavucontrol`, но не было `wireplumber` и `pipewire-pulse` —
в системе оказывались только библиотеки `libpipewire`/`libwireplumber`, PipeWire
крутился без session-менеджера, `pactl` отвечал `Connection refused`, и
pavucontrol не открывался вообще.

```bash
pactl info | grep 'Server Name'     # PulseAudio (on PipeWire X.Y.Z)
systemctl --user is-active pipewire pipewire-pulse wireplumber
```

Если звука нет, а сервер работает — проверь две вещи:

```bash
pactl get-default-sink              # тот ли выход
pactl get-sink-volume @DEFAULT_SINK@   # бывает 0% при живом сервере
```

Дефолтный выход стоит закрепить, иначе wireplumber каждую сессию выбирает его
заново по приоритету и может увести звук на случайное устройство:

```bash
wpctl status                        # найти id нужного sink
wpctl set-default <id>              # пишется в ~/.local/state/wireplumber/default-nodes
```

## Bluetooth

Та же болезнь: `blueman` (GUI) ставился, а `bluez-utils` — нет, и
`bluetooth.service` оставался `disabled`. Оба пункта закрыты в
`install_pacman_packages` и `enable_system_services`.

```bash
systemctl is-active bluetooth       # active
bluetoothctl show | grep Powered    # Powered: yes
rfkill list bluetooth               # Soft/Hard blocked: no
```

## Раскладка и хоткеи в кириллице

Два независимых демона, оба в `system/` (подробности — `system/README.md`):

- **`hk-translator`** — чтобы `Ctrl+C` работал в русской раскладке. Перехватывает
  клавиатуру на уровне evdev и переотправляет через два виртуальных устройства.
  В апстримной версии был баг, из-за которого он **захватывал мышь** вместо
  клавиатуры и не работал никогда.
- **`kbd-layout-toggle`** — переключение по `Alt+Shift`. Штатная xkb-опция
  `grp:alt_shift_toggle` здесь работать не может: **в Hyprland раскладка живёт
  отдельно у каждого устройства ввода**, а их больше десятка.

```bash
systemctl is-active hk-translator kbd-layout-toggle
journalctl -u hk-translator -n 20      # какие устройства захвачены
hyprctl devices | grep -A1 Keyboard    # раскладки не должны разъезжаться
```

## Ghostty

- Конфиг перечитывается по `Ctrl+Shift+,` или `pkill -USR2 -x ghostty`;
  `SIGUSR1` использовать нельзя — он завершает процесс.
- Тема меняется в уже открытом окне через системный портал; скрипт конфиг
  Ghostty не переписывает.
- `font-size = 20` — базовый размер для каждого нового окна, локальный zoom
  окна не наследуется (`window-inherit-font-size = false`).

## sing-box VPN

VPN на основе VLESS + Reality с split tunneling.

- .ru домены идут напрямую
- Остальной трафик через VPN
- DNS over HTTPS (Google)

```bash
# Настройка через restore-config.sh (вставить VLESS ссылку)
# Или вручную:
cp ~/.config/sing-box/config.json.example ~/.config/sing-box/config.json
nano ~/.config/sing-box/config.json
```

Шаг настройки VPN в скрипте **интерактивный** — ждёт VLESS-ссылку со stdin.
При неинтерактивном прогоне он просто пропускается с предупреждением.

### Перенос конфига с macOS — четыре обязательные правки

Конфиг с мака НЕ работает на Linux как есть. Симптом один и тот же на всё:

```
dial udp <сервер>:<порт>: route ip+net : no such network interface
```

Причём падает мгновенно, за `0ms`, даже без TUN и с обычным socks-входом — то есть
дело не в маршрутизации, а в описании исходящего соединения.

| Что | Почему |
|-----|--------|
| Убрать `"bind_interface": "en0"` из **всех** исходов и endpoint'ов | `en0` — имя интерфейса macOS, на Linux его нет. Именно это и даёт ошибку выше. Не менять на `wlan0`: имя интерфейса нестабильно, а при переходе на витую пару сломается снова |
| Добавить `"auto_detect_interface": true` в `route` | На Linux при `auto_route` трафик самого прокси обязан выходить мимо TUN |
| Добавить `"route_exclude_address": ["192.168.0.0/16"]` в TUN inbound | Иначе sing-box ставит свою policy-таблицу выше обычного LAN-маршрута: запрос к SSH приходит по Wi‑Fi, а ответ уходит в `tun0` |
| Пути к `rule_set` сделать абсолютными | Конфиг с мака ссылается на `rule-sets/*.srs` относительно рабочего каталога, а `singbox-toggle.sh` запускает демон без `-D`. Либо абсолютные пути, либо `-D ~/.config/sing-box` в скрипте — сделано и то и то |

Проверять правки до запуска: `sing-box check -D ~/.config/sing-box -c ~/.config/sing-box/config.json`.
Проверять результат после: IP должен стать серверным.

```bash
curl -s https://api.ipify.org      # без тоннеля — IP провайдера
# запустить sing-box, повторить — должен быть IP сервера
curl -s -o /dev/null -w '%{http_code} %{time_total}\n' https://ya.ru   # быстро и напрямую
```

Тестировать тоннель на удалённой машине только под `timeout`: при ошибке в конфиге
маршрутизация ломается вместе с твоим SSH, и `timeout` — единственное, что вернёт
доступ без похода к клавиатуре.

```bash
timeout 25 sudo sing-box run -D ~/.config/sing-box -c ~/.config/sing-box/config.json
```

## NVIDIA GPU Fan Control

Скрипт `gpu-fan-control.sh` + systemd сервис для управления вентиляторами.

| Температура | Скорость |
|-------------|----------|
| ≤ 35°C | 40% |
| 50°C | 58% |
| 70°C | 82% |
| ≥ 85°C | 100% |

## System Fan Curve (nct6798)

Кастомная кривая для системных вентиляторов через hwmon (nct6798). Systemd сервис при загрузке.

| CPU температура | Скорость |
|-----------------|----------|
| ≤ 30°C | 20% |
| 40°C | 25% |
| 48°C | 50% |
| 55°C | 90% |
| ≥ 58°C | 100% |

## Структура

```
.config/
├── systemd/user/         # bt-audio и обратный SSH-туннель
├── hypr/                 # Hyprland + скрипты (theme toggle, вентиляторы, обои)
├── waybar/               # Панель (Lucide SVG, телеметрия, акценты, dark/light CSS)
├── ghostty/              # Терминал + themes/gruvbox-mine-{dark,light}
├── Code/User/            # VSCode settings + keybindings
├── swaync/               # Уведомления (SF Pro Display, динамический акцент Waybar)
├── sing-box/             # VPN (только шаблон!)
├── rofi/                 # Borderless launcher: light/dark + общий акцент Waybar
├── kitty/                # Терминал
├── alacritty/            # Терминал
├── gtk-3.0/              # GTK темы
└── gtk-4.0/              # GTK темы

system/                   # то, что живёт вне $HOME — см. system/README.md
├── hk-translator/        # хоткеи в кириллице (-> /opt, форк: апстрим сломан)
├── kbd-layout-toggle/    # Alt+Shift (-> /opt)
├── ddcci/                # яркость монитора (-> /usr/local/bin + systemd)
├── udev/                 # права на /sys/class/backlight
└── modules-load/         # автозагрузка i2c-dev и ddcci-backlight

scripts/                  # вспомогательные системные скрипты
```
