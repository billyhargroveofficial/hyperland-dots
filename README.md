# Мои Dotfiles для Hyprland

Персональная конфигурация для Hyprland + waybar + swww + rofi на Arch Linux.

Целевая машина: Ryzen 9 5950X / 96 ГБ DDR4 / RTX 3080 Ti / 2× Samsung 980 PRO 1TB
на ASUS ROG STRIX X570-F GAMING. Часть конфигов привязана именно к этому железу
(кривая системных вентиляторов написана под чип мониторинга `nct6798`, GPU-кривая — под 3080 Ti).

## Особенности

- **Waybar** — минималистичная панель с Gruvbox цветами
- **Gruvbox тема** — единый стиль для ghostty, waybar, VSCode, nvim, GTK, rofi, swaync
- **Dark/Light toggle** — переключение всех тем по Ctrl+Y
- **Voice Input** — speech-to-text через faster-whisper на CUDA (Ctrl+Super)
- **Плавные анимации** — настроенные bezier curves для окон и workspaces
- **VPN с split tunneling** — sing-box (VLESS + Reality), .ru домены напрямую
- **NVIDIA GPU fan control** — динамическое управление вентиляторами на Wayland
- **LazyVim** — nvim с прозрачным gruvbox-material
- **SwayNC** — уведомления в стиле Gruvbox
- **Statusline Claude Code** — cship: папка, модель, effort, контекст в токенах,
  5h и недельная квота с таймерами сброса (1 мс на отрисовку)

## Быстрая установка

```bash
git clone https://github.com/billyhargroveofficial/hyperland-dots ~/hyperland-dots
cd ~/hyperland-dots
chmod +x restore-config.sh
./restore-config.sh
```

Скрипт установит все зависимости, настроит конфиги, waybar, swww, LazyVim, voice input venv.

Запускать **обычным пользователем**, не от root — скрипт сам зовёт `sudo` там, где нужно.
Он не падает от единичного сбоя сети: каждый шаг логирует свой результат сам,
поэтому после прогона стоит просмотреть лог на `[WARN]`.

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
| `Alt + F` | Fullscreen |
| `Alt + T` | Toggle floating |
| `Alt + S` | Pin window |
| `Alt + Shift` | Переключить раскладку us/ru |
| `Alt + Tab` | Переключатель окон (hyprshell) |
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
| `Alt + Ctrl + W` | Restart Hyprland + waybar + swww |
| `Print` / `Alt + Ctrl + S` | Скриншот области |

### Навигация (Vim-style)

| Клавиша | Действие |
|---------|----------|
| `Alt + H/J/K/L` | Фокус между окнами |
| `Alt + Shift + H/J/K/L` | Переместить окно |
| `Alt + Ctrl + H/J/K/L` | Resize окна |
| `Alt + 1-9, 0` | Workspace 1-10 |
| `Alt + Ctrl + 1-9` | Переместить на workspace |

## Мониторы

**Сначала посмотри, в какой разъём монитор реально воткнут**: `hyprctl monitors`.
Строка на несуществующий разъём просто не применяется — молча, без ошибки, — и
срабатывает catch-all. Так монитор больше суток проработал на 59.95 Гц вместо
200: в конфиге стоял `DP-2`, а кабель был в `DP-3`.

Второе: catch-all должен быть `highrr`, а не `preferred`. **`preferred` берёт
режим из EDID, а он у большинства мониторов 60 Гц** — именно это и давало 59.95.

```
monitor = , highrr, auto, 1              # запасной вариант для любого монитора
monitor = DP-3, 2560x1440@200, 0x0, 1    # явно и с проверенной частотой
```

Проверка после правки:
```bash
hyprctl monitors -j | jq '.[] | {name, width, height, refreshRate}'
```

Не забыть, что на разъём монитора завязаны ещё три места: `workspace = N,
monitor:DP-X`, `hyprpaper.conf` и аргумент `-o` у `nwg-dock-hyprland`.

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
  через `new_device`, а номер i2c-шины между загрузками не фиксирован.

```bash
ddcutil detect                        # монитор виден по DDC/CI?
ls /sys/class/backlight/              # должен быть ddcciN
cat /sys/class/backlight/ddcci3/brightness
```

Права даёт udev-правило через группу `video`. **Членство в группе подхватывается
только при следующем логине** — до него яркость меняется только от root.

## Тема (Gruvbox)

Единая система тем с переключением по Ctrl+Y:

| Компонент | Dark | Light |
|-----------|------|-------|
| Ghostty | `gruvbox-mine-dark` (0.9 opacity) | `gruvbox-mine-light` (0.9 opacity) |
| Waybar | Gruvbox Dark monochrome | Gruvbox Light monochrome |
| VSCode | Gruvbox Dark Hard | Bearded Theme Milkshake Mint |
| Nvim | gruvbox-material transparent | gruvbox-material transparent |
| GTK | **`Adwaita-dark`** | `Adwaita` |
| Rofi | Gruvbox Dark (muted) | — |
| SwayNC | Gruvbox Dark | — |

### Три вещи, которые ломали переключение

Архитектура правильная — источник правды `gsettings org.gnome.desktop.interface`,
наружу его транслирует `xdg-desktop-portal-gtk` через `org.freedesktop.appearance`.
Ломали её три конкретные вещи, и все три устранены:

**1. `env = GTK_THEME,Adwaita:dark` в `hyprland.conf`.** Главная причина.
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

## Voice Input — ОТКЛЮЧЁН

Speech-to-text через faster-whisper large-v3-turbo на CUDA. **Сейчас выключен.**

Причина: бинд висел на голом `F11`, а это **фуллскрин в любом браузере и
видеоплеере** — он съедался глобально, во всей системе. Плюс venv на 2.7 ГБ
с CUDA-библиотеками пересобирался при каждом прогоне установки.

Вернуть: раскомментировать `setup_voice_input` в `main()` и бинды `F11` в
`.config/hypr/hyprland.conf`. Если возвращаешь — перевесь на комбинацию с
модификатором, иначе снова потеряешь фуллскрин.

- **Ctrl+Super** — первое нажатие начинает запись (красный ● в waybar)
- **Ctrl+Super** — второе нажатие останавливает и транскрибирует (жёлтый ●)
- Текст автоматически вставляется в активное поле через wtype
- Venv: `~/.local/share/voice-input/venv`

### Troubleshooting

| Проблема | Решение |
|----------|---------|
| `libcublas.so.12 not found` | `pip install nvidia-cublas-cu12 nvidia-cudnn-cu12` в venv (CUDA 13 в системе, ctranslate2 собран под CUDA 12) |
| Текст не вставляется | `sudo pacman -S wtype` — нужен для имитации Ctrl+V на Wayland |
| `bindr` не работает с Super_L | Используется toggle вместо hold-to-record |
| Первый запуск долгий | Модель (~1.6GB) скачивается при первом использовании |

## Ghostty

- **НЕТ hot-reload** — `pkill -USR1 ghostty` крашит терминал
- Тема применяется только при открытии нового окна
- toggle-theme.sh использует atomic write (tmpfile + mv), не sed -i
- sed -i на ghostty config создаёт дубли строк — не использовать

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

### Перенос конфига с macOS — три обязательные правки

Конфиг с мака НЕ работает на Linux как есть. Симптом один и тот же на всё:

```
dial udp <сервер>:<порт>: route ip+net : no such network interface
```

Причём падает мгновенно, за `0ms`, даже без TUN и с обычным socks-входом — то есть
дело не в маршрутизации, а в описании исходящего соединения.

| Что | Почему |
|-----|--------|
| Убрать `"bind_interface": "en0"` из **всех** исходов и endpoint'ов | `en0` — имя интерфейса macOS, на Linux его нет. Именно это и даёт ошибку выше. Не менять на `wlan0`: имя интерфейса нестабильно, а при переходе на витую пару сломается снова |
| Добавить `"auto_detect_interface": true` в `route` | На Linux при `auto_route` трафик самого прокси обязан выходить мимо TUN. Без флага в TUN уходит всё, включая ответы в локалку — рвётся даже SSH |
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
├── hypr/                 # Hyprland + скрипты (theme toggle, вентиляторы, обои)
├── waybar/               # Панель (Gruvbox dark/light CSS, звук + яркость)
├── ghostty/              # Терминал + themes/gruvbox-mine-{dark,light}
├── Code/User/            # VSCode settings + keybindings
├── swaync/               # Уведомления (Gruvbox)
├── sing-box/             # VPN (только шаблон!)
├── rofi/                 # Launcher темы (Gruvbox)
├── niri/                 # Niri compositor
├── kitty/                # Терминал
├── alacritty/            # Терминал
├── cship.toml            # Statusline Claude Code (см. CLAUDE.md)
├── gtk-3.0/              # GTK темы
└── gtk-4.0/              # GTK темы

system/                   # то, что живёт вне $HOME — см. system/README.md
├── hk-translator/        # хоткеи в кириллице (-> /opt, форк: апстрим сломан)
├── kbd-layout-toggle/    # Alt+Shift (-> /opt)
├── ddcci/                # яркость монитора (-> /usr/local/bin + systemd)
├── udev/                 # права на /sys/class/backlight
└── modules-load/         # автозагрузка i2c-dev и ddcci-backlight
```
