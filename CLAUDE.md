# Hyperland Dots

Dotfiles для Hyprland + waybar + awww + rofi на Arch Linux.

## Структура репозитория

```
hyperland-dots/
├── .zshrc                    # Zsh конфиг (Oh My Zsh + Powerlevel10k + алиасы)
├── .p10k.zsh                 # Powerlevel10k конфиг
├── restore-config.sh         # Скрипт полной установки системы
├── AGENTS.md                 # Вендор-нейтральный вход в проектные инструкции
├── README.md                 # Документация
├── CLAUDE.md                 # Этот файл
├── docs/                     # Грабли и замечания — читать ПЕРЕД правкой
│   ├── waybar.md             #   свои модули, отступы иконок, анимации GTK3
│   ├── screen-recording.md   #   wf-recorder + NVENC
│   ├── notifications.md      #   swaync и переключение тем
│   ├── hyprland.md           #   Alt+Tab без оверлея, два монитора
│   ├── bluetooth-audio.md    #   наушники: кодек AAC вместо LDAC, баг WirePlumber
│   └── private-state.md      #   секреты и runtime, которые бэкапятся отдельно
├── .local/bin/bt-audio-*     # Автопереключение звука на BT и его починка
│
└── .config/
    ├── systemd/user/         # bt-audio и обратный SSH-туннель
    ├── hypr/                 # Hyprland конфиг
    │   ├── hyprland.lua      # Основной конфиг (Lua, с 0.55; см. docs/hyprland.md)
    │   └── scripts/          # Скрипты автоматизации
    │       ├── toggle-theme.sh       # Dark/Light theme toggle (Ctrl+Y)
    │       ├── voice-input.sh        # Voice-to-text (Ctrl+Super)
    │       ├── transcribe.py         # faster-whisper CUDA транскрибация
    │       ├── gpu-fan-control.sh    # NVIDIA fan control
    │       ├── singbox-toggle.sh     # VPN toggle
    │       ├── restart_hyprland.sh   # Restart waybar + awww + Hyprland
    │       ├── toggle-mainmod.sh     # Главный модификатор ALT <-> SUPER (F10)
    │       └── get-keyboard-layout.sh # Current keyboard layout
    │
    ├── waybar/               # Waybar панель
    │   ├── config            # Модули и layout
    │   ├── style-dark.css    # Тёмная тема
    │   ├── style-light.css   # Светлая тема
    │   ├── style.css         # Симлинк на активную тему
    │   └── scripts/          # Скрипты для модулей
    │       ├── cpu.py             # CPU: загрузка + топ по CPU в попапе
    │       ├── memory.py          # Память: занято/всего + топ по RSS
    │       ├── disk.py            # Диск: занято/всего + крупнейшие каталоги
    │       ├── recorder.sh        # Запись экрана 720p60 -> ~/records
    │       ├── singbox-status.sh  # sing-box status
    │       └── leave.sh           # Power menu
    │
    ├── ghostty/              # Ghostty терминал
    │   ├── config            # Основной конфиг
    │   └── themes/           # Активные gruvbox-mine темы
    │       ├── gruvbox-mine-dark   # opacity 0.9
    │       └── gruvbox-mine-light  # opacity 0.7
    │
    ├── Code/User/            # VSCode настройки
    │   ├── settings.json     # Gruvbox Dark Hard / Bearded Milkshake Mint
    │   └── keybindings.json  # Кастомные хоткеи
    │
    ├── sing-box/             # VPN конфиг
    │   └── config.json.example  # Шаблон (без реальных данных!)
    │
    ├── swaync/               # Уведомления (оформлены под палитру waybar)
    │   ├── config.json       # SwayNC конфиг
    │   ├── style-dark.css    # Тёмная тема
    │   ├── style-light.css   # Светлая тема
    │   └── style.css         # Симлинк на активную (swaync портал НЕ слушает)
    │
    ├── rofi/                 # Borderless light/dark launcher + общий акцент
    ├── niri/                 # Niri compositor конфиг
    ├── kitty/                # Kitty терминал
    ├── alacritty/            # Alacritty терминал
    ├── gtk-3.0/              # GTK3 темы
    ├── gtk-4.0/              # GTK4 темы
    ├── neofetch/             # System info
    ├── swaykbdd/             # Per-window keyboard layout
    └── scripts/              # Общие скрипты

└── system/                   # то, что ставится ВНЕ $HOME — см. system/README.md
    ├── hk-translator/        # хоткеи в кириллице (-> /opt) — форк, апстрим сломан
    ├── kbd-layout-toggle/    # Alt+Shift (-> /opt)
    ├── ddcci/                # яркость монитора (-> /usr/local/bin + systemd)
    ├── ssh/                  # key-only sshd + обратный туннель
    ├── udev/                 # права на /sys/class/backlight
    └── modules-load/         # автозагрузка i2c-dev и ddcci-backlight
```

## Ключевые файлы

| Файл | Описание |
|------|----------|
| `.config/hypr/hyprland.lua` | Основной конфиг Hyprland — формат Lua |
| `.config/hypr/scripts/toggle-theme.sh` | Переключение dark/light (Ctrl+Y) |
| `.config/hypr/scripts/voice-input.sh` | Voice-to-text (Ctrl+Super) |
| `.config/hypr/scripts/transcribe.py` | faster-whisper транскрибация |
| `.config/waybar/config` | Waybar модули и layout |
| `.config/ghostty/config` | Ghostty терминал конфиг |
| `.config/Code/User/settings.json` | VSCode настройки |
| `.zshrc` | Shell конфиг + алиасы |
| `.local/bin/bt-audio-autoswitch` | Звук на BT-наушники при подключении (`docs/bluetooth-audio.md`) |
| `.local/bin/bt-audio-recover` | Обход бага WirePlumber с потерей BlueZ-endpoints |
| `restore-config.sh` | Скрипт установки |

## Codex CLI

Codex — единственный поддерживаемый AI-харнесс на машине. Его нативные
настройки, MCP, авторизация и история живут в `~/.codex/`; dotfiles не
устанавливают и не генерируют их.

## Тема (Gruvbox)

Единая система тем на базе Gruvbox, переключение Ctrl+Y:

| Компонент | Dark | Light |
|-----------|------|-------|
| Ghostty | Gruvbox Dark (0.9 opacity) | Gruvbox Light (0.7 opacity) |
| Waybar | чёрные островки + выбранный акцент | белые островки + выбранный акцент |
| VSCode | Gruvbox Dark Hard | Bearded Theme Milkshake Mint |
| Hyprland border | White (#ffffffcc) | White (#ffffffcc) |
| GTK | **`Adwaita-dark`** | `Adwaita` |
| Nvim | gruvbox-material (transparent) | gruvbox-material (transparent) |
| Rofi | чёрный полупрозрачный + акцент | белый полупрозрачный + акцент |
| SwayNC | палитра waybar | палитра waybar |

### Правила, которые нельзя нарушать

Переключение темы ломалось тремя способами. Все три исправлены — **не возвращай их**:

1. **Никогда не добавляй `hl.env("GTK_THEME", ...)` в конфиг Hyprland.** Это жёсткий
   оверрайд уровня CSS-провайдера: любое GTK3-приложение наследует его из сессии
   и остаётся в заданной теме при любом положении gsettings. Замер при
   `color-scheme=prefer-light`: с переменной `#353535`, без неё `#f6f5f4`.
2. **Имя тёмной темы — `Adwaita-dark`, а не `Adwaita:dark`.** Суффикс `:dark`
   GTK3 парсит только у переменной окружения. Через gsettings он ищется как
   буквальное имя темы, не находится, и GTK3 молча остаётся на светлой.
3. **Не ставь `gtk-application-prefer-dark-theme` в `settings.ini`.** Он прибивает
   тёмную тему намертво, а `settings.ini` не перечитывается на лету.

Чего делать НЕ надо в `toggle-theme.sh` (всё это оттуда уже выброшено):

- перезапускать xdg-desktop-portal — Chromium от этого тему не перечитывает,
  а открытые файловые диалоги и захват экрана рвутся;
- убивать waybar — с 0.15 он сам слушает портал и берёт `style-<appearance>.css`;
- переписывать конфиг ghostty через sed — с 1.2 он сам читает портал.

**Chromium/Chrome/Brave/Electron не возвращаются из тёмной темы в светлую** —
баг апстрима, лечится только рестартом приложения.

**Голубой тулбар Chrome на светлой теме — это «цвет профиля» Material You**
(дефолтный сид голубой), а не GTK-тема. Чинится руками:
`chrome://settings/manageProfile` → Pick a theme color → **Grey default color**.
Живёт в профиле браузера, в репозиторий не выносится — на новой машине
кликнуть заново.

## Демоны вне $HOME — каталог `system/`

Четыре вещи ставятся в системные каталоги, исходники лежат в репозитории
(подробное объяснение каждой — `system/README.md`):

| Что | Зачем |
|---|---|
| `hk-translator` | хоткеи в кириллице. **Форк, а не апстрим**: в оригинале отбор клавиатуры шёл по числу объявленных клавиш, и `grab()` доставался HID-интерфейсу мыши |
| `kbd-layout-toggle` | Alt+Shift. Штатный `grp:alt_shift_toggle` тут не работает: **в Hyprland раскладка живёт отдельно у каждого устройства ввода** |
| `ddcci` | яркость внешнего монитора через `/sys/class/backlight` |
| `ssh` | key-only sshd и обратный туннель через `nareshka.ru:2223` |

## Voice Input (faster-whisper) — ОТКЛЮЧЁН

**Сейчас выключен**: бинд висел на голом `F11`, то есть глобально съедал фуллскрин
в браузерах и видеоплеерах. Вернуть — раскомментировать `setup_voice_input` в
`main()` и бинды в `hyprland.lua`, но перевесить на комбинацию с модификатором.

Speech-to-text через CTRL+Super (toggle: первое нажатие — запись, второе — транскрибация).

- **Модель**: large-v3-turbo на CUDA (float16)
- **Venv**: `~/.local/share/voice-input/venv`
- **Индикатор**: красный ● в waybar (запись), жёлтый ● (обработка)
- **Вставка**: wl-copy + wtype (Ctrl+V в активное поле)

### Известные проблемы и решения

- **libcublas.so.12 not found**: ctranslate2 собран под CUDA 12, а в системе CUDA 13. Решение: `pip install nvidia-cublas-cu12 nvidia-cudnn-cu12` в venv, скрипт transcribe.py загружает их через ctypes перед импортом.
- **bindr не работает с Super_L**: `bindr = CTRL, Super_L` не срабатывает на отпускание. Решение: toggle-скрипт вместо hold-to-record (одно нажатие старт, второе стоп).
- **wtype не установлен**: текст попадает в буфер (wl-copy), но не вставляется. Решение: `sudo pacman -S wtype`.

## Ghostty — важные особенности

- **Тему переключать не надо руками.** В конфиге стоит
  `theme = light:gruvbox-mine-light,dark:gruvbox-mine-dark` + `window-theme = auto`,
  и ghostty ≥1.2 сам следует за системной темой через портал. Скрипт его больше
  не трогает вообще.
- **`SIGUSR1` крашит терминал. Перечитать конфиг — `SIGUSR2`** (`pkill -USR2 -x ghostty`).
  Нужно только если правил конфиг руками; на смену темы это не требуется.
- Нельзя использовать `sed -i` на ghostty config — создаёт дубли строк.
- `background-opacity` живёт **в файлах тем**, а не только в `config`. Правка
  только в `config` будет затёрта при следующем переключении темы — менять надо
  в `themes/gruvbox-mine-dark` и `themes/gruvbox-mine-light`.
- `themes/dark.conf` и `themes/light.conf` — legacy, больше не используются.

## Вставка картинок в CLI-агентов — Alt+V

`Alt+V` передаёт картинку из буфера совместимым терминальным AI-клиентам.
Работает и в кириллице — hk-translator при зажатом Alt гонит буквы
латиницей, так что Alt+М это тот же Alt+V. Скриншот сразу в буфер — `Print`
(`hyprshot -m region -c`), история картинок — `Super+V` (cliphist).

Совместимые клиенты слушают **`Ctrl+V`, то есть байт `0x16`**, и дальше читают
буфер сами (`wl-paste --type image/png` или аналогом). Терминал
картинку не передаёт и не может: его дело — доставить нажатие.

Нажатие съедалось дважды, поэтому нужны обе правки сразу:

| Кто ел | Правка |
|---|---|
| ghostty: `keybind = ctrl+v=paste_from_clipboard` вставлял сам, и только текст | `keybind = alt+v=text:\x16` — отдаёт приложению сырой `^V` |
| hyprland: `bind = $mainMod, V` при `$mainMod = ALT` это Alt+V — cliphist+rofi | cliphist перевешен на явный `SUPER, V` |

**Не возвращай cliphist на `$mainMod, V`.** При `$mainMod = ALT` он забирает Alt+V
раньше терминала, и вместо вставки вылезает rofi с историей буфера. Явный `SUPER`
переживает переключение по `F10`: `toggle-mainmod.sh` правит только строки
`$mainMod =` / `$wsMod =`, биндов не касается.

`Ctrl+V` картинку не вставляет и не должен — он остаётся обычной вставкой текста в
терминал. Отдать под картинки можно и его, убрав `ctrl+v=paste_from_clipboard`, но
тогда `^V` будет уходить в приложение всегда и сломает вставку в zsh и vim.

Ghostty перечитывает конфиг по `Ctrl+Shift+,` (или `pkill -USR2 -x ghostty`).

Проверка, что дело не в буфере: `wl-paste --list-types` должен показать `image/png`.
Учти, что **XWayland-мост буфера мёртв** — `xclip` не видит даже текст из `wl-copy`.
Терминальным клиентам с Wayland-fallback это безразлично, но X11-приложения
картинку из буфера не получат.

## Синхронизация конфигов

При изменении конфигов нужно обновлять **оба** места:
1. Repo: `~/hyperland-dots/.config/...`
2. Live: `~/.config/...`

Порядок: редактировать в repo → `cp` в live. Или наоборот если менял руками.

## Zsh алиасы

| Алиас | Описание |
|-------|----------|
| `disk` | Обзор дисков |
| `space` | Топ-20 по размеру в текущей папке |
| `vpn-log` | Sing-box лог в реалтайме |
| `vpn-traffic` | Только proxy/direct трафик |

## Важно

- **sing-box/config.json** исключён из git (содержит приватные данные)
- Используй `config.json.example` как шаблон
- nvim конфиг устанавливается отдельно (LazyVim) — restore создаёт transparent.lua
- LazyVim тема сбрасывается при повторном запуске restore (клонирует заново)
- **Диски: NTFS больше нет.** `nvme0n1p1` теперь `ext4` и монтируется как `/home`,
  а не в `/media/$USER/Storage`. Функция `mount_ntfs_disk` вырезана из
  `restore-config.sh`: она лезла драйвером `ntfs3 -o force` по жёстко прописанному
  UUID `7E68A3DE68A39405` в живой `/home` и ломала загрузку.
- **Мониторов два: `DP-3` слева (новый, 180.06 Гц), `DP-2` справа (старый,
  200 Гц, серийник `7041110026654` в EDID).** Раньше единственный монитор был
  в `DP-3` — при подключении второго старый переехал в `DP-2`, и строка
  `DP-3, 2560x1440@200` стала целиться в новый монитор, который 200 Гц не
  умеет. Поэтому у обоих `highrr`, а не явные частоты: он берёт максимум из
  EDID и переживает перетыкание кабелей. Строка `monitor` на несуществующий
  разъём не применяется молча, без ошибки, и срабатывает catch-all — так
  монитор больше суток работал на 59.95 Гц вместо 200. Catch-all тоже должен
  быть `highrr`, а не `preferred`: `preferred` берёт режим из EDID, а он у
  большинства мониторов 60 Гц.
- **Яркость идёт на оба монитора сразу.** `bright 50` пишет во все
  `/sys/class/backlight/ddcci*`, а не в первый попавшийся. Если крутится только
  один экран — не привязался `ddcci` ко второй i2c-шине (второй монитор молчал
  на загрузке): `sudo systemctl restart ddcci-bind`, детали в
  `system/README.md`. Сверять надо `ddcutil detect` (видит мониторы напрямую)
  с `ls /sys/class/backlight/`.
- **Столы разделены по мониторам: `DP-2` — 1..10, `DP-3` — 11..20.** Таблица
  `wsBase` в `hyprland.lua` — единственный источник этого деления: её читают и
  `workspace_rule`, и бинды цифр, и прокрутка колесом. Цифра выбирает стол по
  монитору **под курсором** (`hl.get_monitor_at_cursor`), а не по
  клавиатурному фокусу. Функции `hyprWs*` объявлены глобальными намеренно —
  их же дёргает waybar через `hyprctl dispatch`, Lua-состояние у конфига и у
  dispatch одно.
- **`$mainMod = ALT`**, не SUPER. Клавиатура была в Mac-режиме, где под большим
  пальцем Cmd. Переключалка ALT↔SUPER — `toggle-mainmod.sh` на `F10`.
- **`.gitignore`: строка `!*/` обязательна.** Без неё `*` не пускает git внутрь
  каталогов, негативные правила не срабатывают, и НОВЫЕ файлы молча не
  добавляются в репозиторий. На уже отслеживаемые файлы это не влияет, поэтому
  проблему легко не заметить.
- **`awww` — бывший `swww`**, бинарники `awww` / `awww-daemon`. Демон не уходит
  в фон сам: `awww-daemon && awww img ...` зависает на первой команде, обои не
  ставятся вообще. Запускать двумя отдельными `exec-once`.
- **Обоев в репозитории нет** — используются локальные файлы из `~/wallpapers/`.
- **BT-наушники «подключены», а звука нет — это не BlueZ.** WirePlumber на долгом
  аптайме теряет регистрацию своих BlueZ media-endpoints, и `MediaTransport1` не
  создаётся: `bluetoothctl` при этом честно пишет `Connected: yes`, а логи
  wireplumber пусты. Проверять `busctl introspect org.bluez /org/bluez/hci0/dev_<MAC>`,
  а не логи. Автоматически лечит `bt-audio-recover.service`; подробности и ручной
  рецепт — [docs/bluetooth-audio.md](docs/bluetooth-audio.md).
