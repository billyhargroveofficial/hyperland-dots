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
| `Alt + M` | Выход из Hyprland |
| `Alt + E` | Файловый менеджер (nautilus) |
| `Alt + Space` | Лаунчер (rofi) |
| `Alt + V` | Буфер обмена (cliphist + rofi) |
| `Alt + F` | Fullscreen |
| `Alt + T` | Toggle floating |
| `Alt + S` | Pin window |
| `Ctrl + Y` | Toggle dark/light тема |
| `Ctrl + Super` | Voice input (toggle запись/транскрибация) |

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

Частоты задавать явно, иначе Hyprland выберет режим сам и не всегда лучший.
Разъёмы смотреть через `hyprctl monitors`:

```
monitor=DP-1,2560x1440@180,0x0,1
monitor=DP-2,2560x1440@200,2560x0,1
```

## Тема (Gruvbox)

Единая система тем с переключением по Ctrl+Y:

| Компонент | Dark | Light |
|-----------|------|-------|
| Ghostty | Gruvbox Dark (0.8 opacity) | Gruvbox Light (0.3 opacity) |
| Waybar | Gruvbox Dark monochrome | Gruvbox Light monochrome |
| VSCode | Gruvbox Dark Hard | Bearded Theme Milkshake Mint |
| Nvim | gruvbox-material transparent | gruvbox-material transparent |
| GTK | Adwaita:dark | Adwaita |
| Rofi | Gruvbox Dark (muted) | — |
| SwayNC | Gruvbox Dark | — |

## Voice Input

Speech-to-text через faster-whisper large-v3-turbo на CUDA.

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
├── hypr/                 # Hyprland + скрипты (voice-input, theme toggle)
├── waybar/               # Панель (Gruvbox dark/light CSS, voice indicator)
├── ghostty/              # Терминал + themes/
├── Code/User/            # VSCode settings + keybindings
├── swaync/               # Уведомления (Gruvbox)
├── sing-box/             # VPN (только шаблон!)
├── rofi/                 # Launcher темы (Gruvbox)
├── niri/                 # Niri compositor
├── kitty/                # Терминал
├── alacritty/            # Терминал
├── gtk-3.0/              # GTK темы
└── gtk-4.0/              # GTK темы
```
