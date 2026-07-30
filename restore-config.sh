#!/bin/bash

# Скрипт для полного восстановления системы
# Устанавливает весь необходимый софт и конфиги

# Намеренно НЕ set -e: скрипт качает из десятка внешних источников (GitHub, PyPI,
# AUR, зеркала шрифтов). При set -e один обрыв сети на шрифтах убивал весь остаток
# прогона — GPU-вентиляторы, oh-my-zsh, voice input, копирование конфигов. Каждая
# функция логирует свой результат сама, после прогона искать по логу [WARN].
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WARN_COUNT=0

echo "=========================================="
echo "  Hyprland Dotfiles Restore Script"
echo "=========================================="

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() {
    ((WARN_COUNT += 1))
    echo -e "${YELLOW}[WARN]${NC} $1"
}
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка root
if [[ $EUID -eq 0 ]]; then
    log_error "Не запускай от root! Используй обычного пользователя."
    exit 1
fi

# ==========================================
# 1. Установка yay (AUR helper)
# ==========================================
install_yay() {
    log_info "Установка yay..."
    if command -v yay &> /dev/null; then
        log_info "yay уже установлен"
        return
    fi

    sudo pacman -S --needed --noconfirm git base-devel
    cd /tmp
    rm -rf yay
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ~
    log_info "yay установлен"
}

# ==========================================
# 2. Установка пакетов из pacman
# ==========================================
install_pacman_packages() {
    log_info "Установка pacman пакетов..."

    local packages=(
        # Базовые
        git
        base-devel
        openssh

        # Shell
        zsh
        zsh-autosuggestions
        zsh-syntax-highlighting

        # Терминальные утилиты
        neovim
        bat
        eza
        fd
        fzf
        ripgrep
        yazi
        lazygit
        htop
        curl
        wget
        unzip
        uv

        # Wayland/Hyprland
        hyprland
        hyprpaper
        waybar
        rofi-wayland
        wofi
        swaync
        awww            # бывший swww: пакет и бинарники переименованы (awww / awww-daemon)
        hyprshot
        grim            # снимок экрана; на нём же держится hyprshot
        slurp           # выбор области для hyprshot
        wf-recorder     # запись экрана кнопкой в waybar (scripts/recorder.sh)
        wl-clipboard
        cliphist
        udiskie
        xdg-desktop-portal-gtk
        network-manager-applet
        nautilus

        # ЗВУК. Раньше здесь стоял только pavucontrol — то есть GUI микшера без
        # звукового сервера под ним. В системе оказывались лишь библиотеки
        # libpipewire/libwireplumber, PipeWire крутился без session-менеджера и
        # без Pulse-совместимости, `pactl` отвечал "Connection refused", а
        # pavucontrol не открывался. Демоны обязательны, GUI сам по себе бесполезен.
        pipewire
        wireplumber      # session-менеджер; без него PipeWire не маршрутизирует звук
        pipewire-pulse   # слой совместимости с PulseAudio: его и спрашивает pavucontrol
        pipewire-alsa
        pavucontrol

        # Dev tools
        npm
        python
        python-pip
        python-poetry
        docker
        docker-compose

        # Misc
        ghostty
        kitty
        alacritty
        fastfetch

        # NVIDIA GPU Fan Control.
        # nvidia-settings тут НЕТ намеренно: он конфликтует с nvidia-settings-beta,
        # который приезжает из AUR вместе с проприетарным драйвером (см. setup_nvidia).
        xorg-server
        xorg-xhost

        # Проприетарные модули NVIDIA собираются через DKMS
        dkms
        linux-headers

        # Дисплей-менеджер.
        # qt6-multimedia КРИТИЧЕН: тема sddm-astronaut-theme делает
        # `import QtMultimedia` в Main.qml на верхнем уровне, и без пакета гритер
        # падает с "module QtMultimedia is not installed" -> "Fallback to embedded
        # theme". Тема при этом не показывается вообще, а в логе тишина, если не
        # знать где искать (journalctl -u sddm).
        sddm
        qt6-svg
        qt6-declarative
        qt6-multimedia
        qt6-virtualkeyboard   # Components/VirtualKeyboard.qml; не фатально, но тема его грузит

        # Dependencies
        gtk3
        libxrandr
        clang
        cmake
        xdotool
        wtype
        zellij
        imagemagick
        nwg-dock-hyprland

        # BLUETOOTH. Та же болезнь, что со звуком: blueman (GUI) стоял, а демона
        # под ним не было. bluetooth.service оказывался disabled, bluez-utils
        # отсутствовал целиком — то есть не было даже bluetoothctl.
        # Включение сервиса — в enable_system_services().
        bluez
        bluez-utils

        # ТЕМЫ И ИКОНКИ.
        # gnome-themes-extra даёт Adwaita-dark. Без него в /usr/share/themes/
        # лежат только Default, Emacs и HighContrast — то есть ни одной тёмной
        # GTK3-темы, и переключать light/dark физически не на что.
        # papirus-icon-theme: hyprland.lua запускает rofi с
        # `-icon-theme Papirus-Dark`, без пакета иконки в лаунчере пустые.
        gnome-themes-extra
        papirus-icon-theme

        # Яркость внешнего монитора по DDC/CI (см. system/README.md).
        # ddcutil нужен для диагностики (`ddcutil detect`), сама регулировка
        # идёт через ядерный модуль ddcci-backlight.
        ddcutil

        # Нужен и hk-translator, и kbd-layout-toggle
        python-evdev

        # jq разбирает вывод hyprctl в scripts/recorder.sh (выбор монитора для
        # записи). Без него запись стартует без -o и на нескольких выходах
        # молча умирает, ожидая выбора на stdin.
        jq

        # lm_sensors — источник данных для модулей температуры и оборотов
        # вентилятора в waybar (`sensors k10temp-...`, `sensors asusec-...`).
        # Без пакета модули просто пустые, ошибок при этом никаких.
        lm_sensors

        # lua нужен не Hyprland (он со встроенным), а для проверки конфига
        # руками: `luac -p ~/.config/hypr/hyprland.lua` до перезахода в сессию.
        lua
    )

    sudo pacman -S --needed --noconfirm "${packages[@]}" || log_warn "Некоторые пакеты не найдены в pacman"
    log_info "pacman пакеты установлены"
}

# ==========================================
# 3. Установка AUR пакетов
# ==========================================
install_aur_packages() {
    log_info "Установка AUR пакетов..."

    local aur_packages=(
        google-chrome
        brave-bin
        telegram-desktop
        mission-center
        mcmojave-cursors
        zen-browser-bin
        visual-studio-code-bin
        obsidian
        # hyprshell-bin убран: его оверлей вылезал на Alt+Tab и был не нужен.
        # Переключение окон нативное — hl.bind("ALT + Tab", hl.dsp.window.cycle_next()).
    )

    for pkg in "${aur_packages[@]}"; do
        if ! yay -Qi "$pkg" &> /dev/null; then
            log_info "Установка $pkg..."
            yay -S --noconfirm "$pkg" || log_warn "Не удалось установить $pkg"
        else
            log_info "$pkg уже установлен"
        fi
    done

    log_info "AUR пакеты установлены"
}

# ==========================================
# 4. Установка шрифтов
# ==========================================
install_fonts() {
    log_info "Установка шрифтов..."

    # Maple Mono NF CN
    if ! fc-list | grep -qi "maple"; then
        log_info "Установка Maple Mono NF CN..."
        mkdir -p ~/.local/share/fonts
        cd /tmp
        rm -f MapleMono-NF-CN.zip
        curl -fL "https://github.com/subframe7536/maple-font/releases/latest/download/MapleMono-NF-CN.zip" -o MapleMono-NF-CN.zip
        unzip -o MapleMono-NF-CN.zip -d ~/.local/share/fonts/
        fc-cache -fv
    else
        log_info "Maple Mono уже установлен"
    fi

    # Playpen Sans
    if ! fc-list | grep -qi "playpen"; then
        log_info "Установка Playpen Sans..."
        mkdir -p ~/.local/share/fonts
        cd /tmp
        rm -rf Playpen-Sans
        git clone --depth=1 https://github.com/TypeTogether/Playpen-Sans.git
        cp Playpen-Sans/fonts/ttf/*.ttf ~/.local/share/fonts/ 2>/dev/null || true
        cp Playpen-Sans/fonts/variable/*.ttf ~/.local/share/fonts/ 2>/dev/null || true
        rm -rf Playpen-Sans
        fc-cache -fv
    else
        log_info "Playpen Sans уже установлен"
    fi

    # Nerd Fonts (дополнительно)
    sudo pacman -S --needed --noconfirm ttf-jetbrains-mono-nerd ttf-firacode-nerd 2>/dev/null || true

    # Emoji шрифт (для waybar иконок)
    sudo pacman -S --needed --noconfirm noto-fonts-emoji 2>/dev/null || true

    log_info "Шрифты установлены"
}

# ==========================================
# 5. Настройка sing-box VPN
# ==========================================
setup_singbox() {
    log_info "Настройка sing-box..."

    # Проверяем наличие sing-box
    if ! command -v sing-box &> /dev/null; then
        log_info "Установка sing-box..."
        sudo pacman -S --needed --noconfirm sing-box || {
            log_warn "sing-box не найден в pacman, пробуем AUR..."
            yay -S --noconfirm sing-box-bin || log_warn "Не удалось установить sing-box"
        }
    fi

    mkdir -p ~/.config/sing-box

    # Генерация конфига из VLESS ссылки
    if [[ ! -f "$HOME/.config/sing-box/config.json" ]]; then
        echo ""
        echo -e "${YELLOW}Вставь VLESS ссылку (vless://...) для настройки VPN:${NC}"
        echo -e "${YELLOW}(или нажми Enter чтобы пропустить)${NC}"
        read -r vless_link

        if [[ "$vless_link" == vless://* ]]; then
            # Парсим: vless://UUID@SERVER:PORT?params#fragment
            local userinfo="${vless_link#vless://}"
            local uuid="${userinfo%%@*}"
            local rest="${userinfo#*@}"
            local hostport="${rest%%\?*}"
            local server="${hostport%%:*}"
            local port="${hostport##*:}"
            local params="${rest#*\?}"
            params="${params%%#*}"

            # Извлекаем параметры
            local pbk="" fp="" sni="" sid=""
            IFS='&' read -ra PAIRS <<< "$params"
            for pair in "${PAIRS[@]}"; do
                local key="${pair%%=*}"
                local val="${pair#*=}"
                case "$key" in
                    pbk) pbk="$val" ;;
                    fp)  fp="$val" ;;
                    sni) sni="$val" ;;
                    sid) sid="$val" ;;
                esac
            done

            # Генерируем config.json из шаблона
            sed -e "s|YOUR_SERVER_IP|$server|g" \
                -e "s|YOUR_UUID_HERE|$uuid|g" \
                -e "s|YOUR_REALITY_PUBLIC_KEY|$pbk|g" \
                -e "s|YOUR_SHORT_ID|$sid|g" \
                -e "s|YOUR_USERNAME|$USER|g" \
                "$SCRIPT_DIR/.config/sing-box/config.json.example" | \
            python3 -c "
import sys, json
cfg = json.load(sys.stdin)
cfg['outbounds'][0]['server_port'] = $port
cfg['outbounds'][0]['tls']['server_name'] = '$sni'
cfg['outbounds'][0]['tls']['utls']['fingerprint'] = '$fp'
json.dump(cfg, sys.stdout, indent=2, ensure_ascii=False)
" > "$HOME/.config/sing-box/config.json"

            log_info "sing-box config.json сгенерирован из VLESS ссылки"
            log_info "  Сервер: $server:$port | SNI: $sni"
        else
            if [[ -n "$vless_link" ]]; then
                log_warn "Невалидная ссылка (должна начинаться с vless://)"
            fi
            log_warn "sing-box конфиг не создан. Создай вручную: ~/.config/sing-box/config.json"
        fi
    else
        log_info "sing-box config.json уже существует, пропускаем"
    fi

    # Sudoers для sing-box (без пароля)
    sudo tee /etc/sudoers.d/singbox > /dev/null << EOF
$USER ALL=(ALL) NOPASSWD: /usr/bin/sing-box, /usr/bin/pkill sing-box
EOF
    sudo chmod 440 /etc/sudoers.d/singbox

    log_info "sing-box настроен (используй Alt+P для toggle)"
}

# ==========================================
# 6. Настройка NVIDIA GPU Fan Control
# ==========================================
setup_gpu_fan() {
    log_info "Настройка GPU Fan Control..."

    # Проверка nvidia
    if ! lspci | grep -qi nvidia; then
        log_warn "NVIDIA GPU не найден, пропускаем настройку вентиляторов"
        return
    fi

    # Получаем BusID видеокарты
    local BUS_ID=$(lspci | grep -i 'vga.*nvidia' | awk '{print $1}' | head -1)
    if [[ -z "$BUS_ID" ]]; then
        BUS_ID=$(lspci | grep -i nvidia | awk '{print $1}' | head -1)
    fi

    # Конвертируем BusID в формат для xorg (09:00.0 -> PCI:9:0:0).
    # ВАЖНО: bus и device в выводе lspci шестнадцатеричные. Прежняя реализация делала
    # awk '{printf "%d", "0x"$1}', но awk по умолчанию не парсит hex-строки — "0x09"
    # превращалось в 0, в конфиг уезжал BusID "PCI:0:0:0", Xorg падал с
    # "(EE) No devices detected / no screens found", и сервис вентиляторов молча не
    # работал вообще. Считаем через арифметику bash с явным основанием 16.
    local _b _d _f
    IFS=':.' read -r _b _d _f <<< "$BUS_ID"
    local BUS_ID_XORG="PCI:$((16#$_b)):$((16#$_d)):$_f"
    log_info "NVIDIA GPU: $BUS_ID -> $BUS_ID_XORG"

    # Создаём xorg.conf с Coolbits
    sudo mkdir -p /etc/X11/xorg.conf.d
    sudo tee /etc/X11/xorg.conf.d/20-nvidia.conf > /dev/null << EOF
Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BusID          "$BUS_ID_XORG"
    Option         "Coolbits" "4"
    Option         "AllowEmptyInitialConfiguration" "True"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
EndSection
EOF

    # Создаём скрипт настройки вентиляторов
    sudo tee /usr/local/bin/gpu-fan-setup.sh > /dev/null << 'SCRIPT'
#!/bin/bash
LOG="/var/log/gpu-fan.log"
FAN_SPEED="${GPU_FAN_SPEED:-62}"

echo "[$(date)] Starting GPU fan setup (target: ${FAN_SPEED}%)..." >> $LOG

X :99 -config /etc/X11/xorg.conf.d/20-nvidia.conf -sharevts -noreset &
XPID=$!
sleep 3

if kill -0 $XPID 2>/dev/null; then
    echo "[$(date)] X server started on :99" >> $LOG
    DISPLAY=:99 nvidia-settings -a "[gpu:0]/GPUFanControlState=1" >> $LOG 2>&1
    DISPLAY=:99 nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=$FAN_SPEED" >> $LOG 2>&1
    DISPLAY=:99 nvidia-settings -a "[fan:1]/GPUTargetFanSpeed=$FAN_SPEED" >> $LOG 2>&1
    SPEED=$(DISPLAY=:99 nvidia-settings -q "[fan:0]/GPUTargetFanSpeed" -t 2>/dev/null)
    echo "[$(date)] Fan speed set to: ${SPEED}%" >> $LOG
    kill $XPID 2>/dev/null
    echo "[$(date)] X server stopped, fan settings preserved" >> $LOG
else
    echo "[$(date)] ERROR: Failed to start X server" >> $LOG
    exit 1
fi
SCRIPT

    sudo chmod +x /usr/local/bin/gpu-fan-setup.sh

    # Создаём systemd сервис
    sudo tee /etc/systemd/system/gpu-fan.service > /dev/null << 'SERVICE'
[Unit]
Description=NVIDIA GPU Fan Control
Before=display-manager.service
After=nvidia-persistenced.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/gpu-fan-setup.sh
RemainAfterExit=yes
Environment="GPU_FAN_SPEED=62"

[Install]
WantedBy=multi-user.target
SERVICE

    sudo systemctl daemon-reload
    sudo systemctl enable gpu-fan.service

    # Добавляем sudoers правило для nvidia-settings (для динамического контроля через XWayland)
    echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/nvidia-settings" | sudo tee /etc/sudoers.d/nvidia-settings > /dev/null
    sudo chmod 440 /etc/sudoers.d/nvidia-settings

    log_info "GPU Fan Control настроен"
    log_info "  - Systemd сервис: 62% при загрузке (до запуска Hyprland)"
    log_info "  - Демон: динамическая кривая после запуска Hyprland"
}

# ==========================================
# 6.1. Настройка системных вентиляторов (nct6798)
# ==========================================
setup_system_fan() {
    log_info "Настройка системных вентиляторов..."

    # Проверяем наличие nct6798
    if ! ls /sys/class/hwmon/hwmon*/name 2>/dev/null | xargs grep -l "nct6798" &>/dev/null; then
        # Загружаем модуль
        sudo modprobe nct6775 2>/dev/null || true
        echo nct6775 | sudo tee /etc/modules-load.d/nct6775.conf > /dev/null
        log_warn "Модуль nct6775 загружен. Может потребоваться перезагрузка."
    fi

    # Копируем скрипт
    sudo cp "$SCRIPT_DIR/scripts/setup-system-fan.sh" /usr/local/bin/system-fan-curve.sh
    sudo chmod +x /usr/local/bin/system-fan-curve.sh

    # Создаём systemd сервис
    sudo tee /etc/systemd/system/system-fan.service > /dev/null << 'EOF'
[Unit]
Description=System Fan Curve
After=systemd-modules-load.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/system-fan-curve.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable system-fan.service

    # Применяем сейчас
    sudo /usr/local/bin/system-fan-curve.sh 2>/dev/null || log_warn "Не удалось применить кривую (нужна перезагрузка?)"

    log_info "Системные вентиляторы настроены (nct6798)"
}

# ==========================================
# 6.2. Установка hk-translator
# ==========================================
install_hk_translator() {
    log_info "Установка hk-translator..."

    # Ставим из system/ в этом репозитории, а НЕ клонированием из
    # github.com/reflaxess123/hk-translator, как было раньше. Две причины:
    # аккаунт reflaxess123 больше не существует (301), и в апстримной версии
    # был баг, из-за которого транслятор не работал никогда — отбор клавиатуры
    # шёл по числу объявленных клавиш, и grab() доставался HID-интерфейсу мыши
    # Logitech G102 (273 «клавиши» — больше любой клавиатуры).
    # Подробности и список исправлений: system/README.md
    sudo pacman -S --needed --noconfirm python-evdev

    sudo mkdir -p /opt/hk-translator
    sudo install -m 755 "$SCRIPT_DIR/system/hk-translator/hk-translator.py" /opt/hk-translator/
    sudo install -m 644 "$SCRIPT_DIR/system/hk-translator/hk-translator.service" /etc/systemd/system/
    sudo mkdir -p /etc/systemd/system/hk-translator.service.d
    sudo install -m 644 "$SCRIPT_DIR/system/hk-translator/service.d/override.conf" \
        /etc/systemd/system/hk-translator.service.d/

    sudo systemctl daemon-reload
    sudo systemctl enable hk-translator

    log_info "hk-translator установлен (запустится после перезагрузки)"
}

# ==========================================
# Переключение раскладки по Alt+Shift
# ==========================================
install_kbd_layout_toggle() {
    log_info "Установка kbd-layout-toggle..."

    # Почему не kb_options = grp:alt_shift_toggle: в Hyprland раскладка живёт
    # отдельно у КАЖДОГО устройства ввода, а их тут больше десятка, включая две
    # виртуальные клавиатуры от hk-translator. xkb переключает группу только у
    # того устройства, на котором нажали, а печать идёт через другое.
    # Подробности: system/README.md
    sudo pacman -S --needed --noconfirm python-evdev

    sudo mkdir -p /opt/kbd-layout-toggle
    sudo install -m 755 "$SCRIPT_DIR/system/kbd-layout-toggle/kbd-layout-toggle.py" /opt/kbd-layout-toggle/
    sudo install -m 644 "$SCRIPT_DIR/system/kbd-layout-toggle/kbd-layout-toggle.service" /etc/systemd/system/
    sudo mkdir -p /etc/systemd/system/kbd-layout-toggle.service.d
    sudo install -m 644 "$SCRIPT_DIR/system/kbd-layout-toggle/service.d/override.conf" \
        /etc/systemd/system/kbd-layout-toggle.service.d/

    sudo systemctl daemon-reload
    sudo systemctl enable kbd-layout-toggle

    log_info "kbd-layout-toggle установлен"
}

# ==========================================
# Яркость внешнего монитора (DDC/CI)
# ==========================================
install_ddcci_backlight() {
    log_info "Установка ddcci-backlight (яркость внешнего монитора)..."

    # Стабильный ddcci-driver-linux-dkms НЕ собирается на ядрах 7.x: в ядре
    # добавили const в сигнатуру device_driver и выпилили I2C_CLASS_SPD.
    # Берём форк, который это чинит.
    yay -S --needed --noconfirm ddcci-driver-linux-clemax-dkms-git \
        || { log_warn "ddcci-driver не собрался — яркость монитора работать не будет"; return 0; }

    sudo install -m 755 "$SCRIPT_DIR/system/ddcci/ddcci-bind.sh" /usr/local/bin/
    sudo install -m 644 "$SCRIPT_DIR/system/ddcci/ddcci-bind.service" /etc/systemd/system/
    sudo install -m 644 "$SCRIPT_DIR/system/udev/99-ddcci-backlight.rules" /etc/udev/rules.d/
    sudo install -m 644 "$SCRIPT_DIR/system/modules-load/ddcci.conf" /etc/modules-load.d/
    # delay=10 вместо дефолтных 60 мс: запись яркости 32 мс вместо 165-380 и без
    # деградации. Без этого слайдер в панели упирается в очередь на шине.
    sudo install -m 644 "$SCRIPT_DIR/system/modules-load/ddcci-modprobe.conf" /etc/modprobe.d/ddcci.conf

    # Права на запись яркости даёт udev-правило через группу video.
    # ВНИМАНИЕ: членство в группе подхватывается только при следующем логине.
    sudo usermod -aG video "$USER"

    sudo systemctl daemon-reload
    sudo systemctl enable ddcci-bind.service
    sudo udevadm control --reload-rules

    log_info "ddcci-backlight установлен (заработает после перезагрузки)"
}

# ==========================================
# Системные сервисы, которые иначе остаются выключенными
# ==========================================
enable_system_services() {
    log_info "Включение системных сервисов..."

    # Bluetooth: пакеты ставятся, но сервис по умолчанию disabled.
    sudo systemctl enable --now bluetooth || log_warn "bluetooth не включился"

    # nvidia-persistenced. Без него на загрузке НЕ существует /dev/nvidia0 и
    # /dev/nvidia-modeset, а X-драйверу NVIDIA они нужны. Последствия были
    # такие: SDDM трижды не мог поднять X ("Could not start Display server on
    # vt 2") и появлялся с большой задержкой, а gpu-fan.service падал с
    # "No devices detected". gpu-fan.service объявляет After= на этот юнит,
    # но пока юнит выключен, зависимость молча указывает в пустоту.
    sudo systemctl enable --now nvidia-persistenced || log_warn "nvidia-persistenced не включился"

    # Звук — пользовательские юниты, не системные.
    systemctl --user enable --now pipewire wireplumber pipewire-pulse \
        || log_warn "аудио-юниты не включились"

    log_info "Системные сервисы включены"
}

# ==========================================
# Постоянный удалённый доступ к mujik через nareshka.ru
# ==========================================
setup_remote_ssh() {
    log_info "Настройка SSH и обратного туннеля..."

    sudo install -Dm644 \
        "$SCRIPT_DIR/system/ssh/10-billy.conf" \
        /etc/ssh/sshd_config.d/10-billy.conf
    if sudo /usr/bin/sshd -t; then
        sudo systemctl enable --now sshd.service \
            || log_warn "sshd не включился"
        sudo systemctl restart sshd.service \
            || log_warn "sshd не перечитал безопасный конфиг"
    else
        log_warn "sshd_config невалиден — sshd не включён"
        return
    fi

    # User manager должен жить уже на экране входа: иначе user-unit туннеля
    # появится только после первого графического логина.
    sudo loginctl enable-linger "$USER" \
        || log_warn "linger для $USER не включился"

    install -Dm644 \
        "$SCRIPT_DIR/.config/systemd/user/mujik-ssh-tunnel.service" \
        "$HOME/.config/systemd/user/mujik-ssh-tunnel.service"
    install -Dm755 \
        "$SCRIPT_DIR/.local/bin/mujik-ssh-tunnel" \
        "$HOME/.local/bin/mujik-ssh-tunnel"
    systemctl --user daemon-reload
    systemctl --user enable --now mujik-ssh-tunnel.service \
        || log_warn "обратный SSH-туннель не включился"

    log_info "SSH и обратный туннель настроены"
}

# Локальный pre-commit является частью репозитория, но Git не включает его
# автоматически после clone. Настройка локальная для этого checkout.
setup_repo_guards() {
    if git -C "$SCRIPT_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "$SCRIPT_DIR" config core.hooksPath .githooks \
            || log_warn "не удалось включить локальные git-хуки"
    fi
}

# ==========================================
# Bluetooth-аудио: автопереключение на наушники + обход бага WirePlumber
# ==========================================
# Подробности в docs/bluetooth-audio.md. Коротко, зачем оба юнита:
#
#   autoswitch — штатный module-switch-on-connect тут не годится: он уводит звук
#   на ЛЮБОЕ новое устройство, а NVIDIA пересоздаёт HDMI-ноду при пробуждении
#   монитора. Свой хук слушает pactl subscribe и реагирует только на bluez_output.*
#
#   recover — WirePlumber на долгом аптайме теряет регистрацию своих BlueZ
#   media-endpoints: bluetoothd рапортует Connected=yes, но MediaTransport1 не
#   создаётся и карты в PipeWire нет. Лечится рестартом wireplumber ОБЯЗАТЕЛЬНО
#   с переподключением устройства — само ACL-соединение A2DP не пересогласует.
install_bt_audio() {
    log_info "Установка Bluetooth-аудио сервисов..."

    install -Dm755 "$SCRIPT_DIR/.local/bin/bt-audio-autoswitch" \
        "$HOME/.local/bin/bt-audio-autoswitch"
    install -Dm755 "$SCRIPT_DIR/.local/bin/bt-audio-recover" \
        "$HOME/.local/bin/bt-audio-recover"

    local unit
    for unit in bt-audio-autoswitch bt-audio-recover; do
        install -Dm644 "$SCRIPT_DIR/.config/systemd/user/$unit.service" \
            "$HOME/.config/systemd/user/$unit.service"
    done

    systemctl --user daemon-reload
    systemctl --user enable --now bt-audio-autoswitch.service bt-audio-recover.service \
        || log_warn "bt-audio сервисы не включились"

    # btusb по умолчанию разрешает USB-автосуспенд адаптеру: донгл засыпает на
    # паузах в звуке и просыпается с задержкой — микрообрывы. На десктопе
    # экономить нечего. Применяется при следующей загрузке модуля.
    sudo install -m 644 "$SCRIPT_DIR/system/modules-load/btusb-modprobe.conf" \
        /etc/modprobe.d/btusb.conf

    log_info "Bluetooth-аудио сервисы установлены"
}

# ==========================================
# 7. Установка Oh-My-Zsh и Powerlevel10k
# ==========================================
install_ohmyzsh() {
    log_info "Установка Oh-My-Zsh..."

    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    else
        log_info "Oh-My-Zsh уже установлен"
    fi

    # Powerlevel10k
    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$p10k_dir" ]]; then
        log_info "Установка Powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
    else
        log_info "Powerlevel10k уже установлен"
    fi

    log_info "Oh-My-Zsh настроен"
}

# ==========================================
# 7.4. cship — statusline для Claude Code
# ==========================================
install_cship() {
    log_info "Установка cship (statusline для Claude Code)..."

    # Официальный установщик с cship.dev не годится на Arch: на шаге 4 он делает
    # `sudo apt-get install libsecret-tools`, а на шаге 5 тянет Starship ещё одним
    # `curl | sh`. Берём бинарь из релизов сами — он статический (musl), рантайма
    # не требует.
    #
    # Почему не ccstatusline (12k звёзд против 406): он запускается как
    # `npx -y ccstatusline@latest`, это ~70 мс на КАЖДУЮ отрисовку строки.
    # У cship — 1 мс, с обёрткой cship-wrap — 8 мс.
    local url="https://github.com/stephenleo/cship/releases/latest/download/cship-x86_64-unknown-linux-musl"
    mkdir -p "$HOME/.local/bin"
    if curl -fsSL "$url" -o "$HOME/.local/bin/cship.new"; then
        chmod +x "$HOME/.local/bin/cship.new"
        mv -f "$HOME/.local/bin/cship.new" "$HOME/.local/bin/cship"
        log_info "cship установлен: $("$HOME/.local/bin/cship" --version 2>/dev/null | head -1)"
    else
        rm -f "$HOME/.local/bin/cship.new"
        log_warn "cship не скачался — statusline в Claude Code останется дефолтным"
        return 0
    fi

    # Обёртка. Правит stdin-JSON от Claude Code до того, как он попадёт в cship:
    # basename папки, «Opus 5 1M» вместо «Opus 5 (1M context)», токены в тысячах.
    # Ничего этого cship не умеет — подробности в шапке самого файла. Ставится
    # ПОСЛЕ бинаря: без cship она бесполезна.
    install -Dm755 "$SCRIPT_DIR/.local/bin/cship-wrap" "$HOME/.local/bin/cship-wrap"

    # secret-tool из libsecret. Лимиты cship берёт из stdin-JSON, который отдаёт
    # сам Claude Code, но когда их там ещё нет (первые секунды сессии) — ходит
    # за ними в API, и вот там нужен доступ к кредам.
    sudo pacman -S --needed --noconfirm libsecret >/dev/null 2>&1 \
        || log_warn "libsecret не поставился — фоллбэк за лимитами через API не заработает"

    # statusLine дописывается в ~/.claude/settings.json МЕРЖЕМ, а не заменой файла.
    # Самого settings.json в репозитории нет намеренно: Claude Code переписывает
    # его на каждый /model и /config, и в репе он давал бы вечный грязный diff.
    local settings="$HOME/.claude/settings.json"
    mkdir -p "$HOME/.claude"
    [[ -f "$settings" ]] || echo '{}' > "$settings"
    python3 - "$settings" <<'PYEOF' || log_warn "не удалось прописать statusLine — добавь вручную"
import json, os, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except (ValueError, OSError) as e:
    print('settings.json нечитаем (%s) — statusLine не прописан' % e)
    sys.exit(1)
data['statusLine'] = {
    'type': 'command',
    # cship-wrap, а не cship: обёртка препроцессит JSON и сама зовёт бинарь.
    'command': os.path.expanduser('~/.local/bin/cship-wrap'),
}
with open(path, 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
print('statusLine прописан в ' + path)
PYEOF

    log_info "cship настроен (конфиг: ~/.config/cship.toml)"
}

# ==========================================
# 7.4. Общий control plane AI-харнессов
# ==========================================
install_ai_harnesses() {
    log_info "Установка общей системы AI-харнессов..."
    bash "$SCRIPT_DIR/scripts/install-ai-harnesses.sh" \
        || log_warn "AI control plane установлен не полностью"
}

# ==========================================
# 7.5. Установка LazyVim
# ==========================================
install_lazyvim() {
    log_info "Установка LazyVim..."

    # Бэкап старого конфига
    if [[ -d "$HOME/.config/nvim" ]]; then
        log_info "Бэкап старого nvim конфига..."
        rm -rf "$HOME/.config/nvim.bak"
        mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak"
    fi

    # Удаляем кэш
    rm -rf ~/.local/share/nvim
    rm -rf ~/.local/state/nvim
    rm -rf ~/.cache/nvim

    # Клонируем LazyVim starter
    log_info "Клонирование LazyVim..."
    git clone https://github.com/LazyVim/starter ~/.config/nvim
    rm -rf ~/.config/nvim/.git

    # Gruvbox Material с прозрачным фоном
    cat > ~/.config/nvim/lua/plugins/transparent.lua << 'NVIMEOF'
return {
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "gruvbox-material",
    },
  },
  {
    "sainnhe/gruvbox-material",
    lazy = false,
    priority = 1000,
    config = function()
      vim.g.gruvbox_material_transparent_background = 2
      vim.g.gruvbox_material_background = "hard"
    end,
  },
}
NVIMEOF

    log_info "LazyVim установлен (gruvbox-material). Запусти nvim для установки плагинов."
}

# ==========================================
# 8.5. Voice input (faster-whisper venv)
# ==========================================
setup_voice_input() {
    log_info "Настройка voice input (faster-whisper)..."

    local venv_dir="$HOME/.local/share/voice-input/venv"

    if [[ ! -d "$venv_dir" ]]; then
        mkdir -p "$(dirname "$venv_dir")"
        python -m venv "$venv_dir"
        "$venv_dir/bin/pip" install --upgrade pip
        "$venv_dir/bin/pip" install faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12
        # Pre-download model
        "$venv_dir/bin/python" -c "from faster_whisper import WhisperModel; WhisperModel('large-v3-turbo', device='cpu', compute_type='int8')" 2>/dev/null
        log_info "Voice input venv создан: $venv_dir"
    else
        log_info "Voice input venv уже существует"
    fi
}

# ==========================================
# 8.6. Проприетарный драйвер NVIDIA (из AUR) + выключение GSP
# ==========================================
# Открытые модули (nvidia-open) построены на GSP, а GSP — причина рваных анимаций и
# просадок FPS на Wayland при высоких частотах обновления (open-gpu-kernel-modules
# #693, Hyprland #9029). Выключить GSP можно ТОЛЬКО на проприетарных модулях: на
# открытых NVreg_EnableGpuFirmware не работает в принципе, без GSP они не живут.
# Arch выкинул проприетарные модули из репозиториев начиная с ветки 590, поэтому AUR.
setup_nvidia() {
    if ! lspci | grep -qi 'vga.*nvidia'; then
        log_warn "NVIDIA GPU не найден, пропускаю драйвер"
        return
    fi
    if pacman -Qq nvidia-beta-dkms &> /dev/null; then
        log_info "nvidia-beta-dkms уже установлен"
    else
        log_info "Установка проприетарных модулей NVIDIA из AUR..."
        # Порядок важен: modules зависят от utils ровно той же версии
        yay -S --noconfirm nvidia-utils-beta || log_warn "nvidia-utils-beta не установился"
        yay -S --noconfirm nvidia-beta-dkms  || log_warn "nvidia-beta-dkms не установился"
    fi

    log_info "Выключаю GSP..."
    sudo tee /etc/modprobe.d/nvidia-gsp.conf > /dev/null <<'EOF'
# GSP firmware даёт заикания и просадки FPS на Wayland при 144+ Гц.
# Проверка: nvidia-smi -q | grep 'GSP Firmware'  -> должно быть N/A
options nvidia NVreg_EnableGpuFirmware=0
EOF

    log_info "Ранний KMS для Wayland..."
    sudo sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
    sudo mkinitcpio -P

    log_warn "Добавь в параметры ядра: nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    log_warn "и перезагрузись — только после этого проверяй мониторы"
}

# ==========================================
# 8.7. Дисплей-менеджер SDDM
# ==========================================
# Тема ставится клоном из upstream, а НЕ из AUR: все обёртки в AUR заброшены с
# 2024 года и писались под Qt5, а SDDM давно на Qt6 — типовой исход в том, что
# тема молча не грузится и показывается дефолтный серый greeter.
setup_sddm() {
    log_info "Настройка SDDM..."
    local T=/usr/share/sddm/themes
    local V="${SDDM_VARIANT:-black_hole}"

    if [[ ! -d "$T/sddm-astronaut-theme" ]]; then
        sudo git clone -q --depth 1 https://github.com/keyitdev/sddm-astronaut-theme.git \
            "$T/sddm-astronaut-theme" || { log_warn "тему склонировать не удалось"; return; }
        sudo find "$T/sddm-astronaut-theme" -maxdepth 1 -iname 'Fonts' \
            -exec cp -r {}/. /usr/share/fonts/ \; 2>/dev/null
        sudo fc-cache -f > /dev/null 2>&1
    fi

    if [[ ! -f "$T/sddm-astronaut-theme/Themes/$V.conf" ]]; then
        V=$(basename "$(ls "$T/sddm-astronaut-theme/Themes/"*.conf | head -1)" .conf)
        log_warn "выбранного варианта нет, беру $V"
    fi
    sudo sed -i "s|^ConfigFile=.*|ConfigFile=Themes/$V.conf|" "$T/sddm-astronaut-theme/metadata.desktop"

    sudo mkdir -p /etc/sddm.conf.d
    printf '[Theme]\nCurrent=sddm-astronaut-theme\n' | sudo tee /etc/sddm.conf.d/10-theme.conf > /dev/null
    # X11-greeter: обкатаннее с проприетарным NVIDIA, а xorg-server всё равно нужен
    # для управления вентиляторами через Coolbits. Виртуальную клавиатуру не включаем.
    printf '[General]\nDisplayServer=x11\n' | sudo tee /etc/sddm.conf.d/20-general.conf > /dev/null

    sudo systemctl enable sddm
    sudo systemctl set-default graphical.target
    log_info "SDDM включён (вариант темы: $V)"
}

# ==========================================
# 9. Копирование конфигов
# ==========================================
copy_configs() {
    log_info "Копирование конфигов..."

    local items=(
        ".zshrc"
        ".p10k.zsh"
        ".config/hypr"
        ".config/ghostty"
        ".config/kitty"
        ".config/alacritty"
        ".tmux.conf"
        # Каталог целиком: rm -rf выше снёс бы rename-random.sh и
        # agent-win.sh, если положить только часть файлов.
        ".config/tmux"
        # Только models.json: рядом лежат auth.json и сессии Pi, а выше
        # по циклу идёт rm -rf — каталогом сюда нельзя.
        ".pi/agent/models.json"
        ".pi/agent/settings.json"
        ".config/cship.toml"
        ".config/cship.toml.compact-variant"
        ".config/swaykbdd"
        ".config/neofetch"
        ".config/scripts"
        ".config/sing-box"
        ".config/waybar"
        ".config/rofi"
        ".config/niri"
        ".config/gtk-3.0"
        ".config/gtk-4.0"
        ".config/swaync"
        ".config/Code/User"
        ".config/zellij"
        ".config/hyprshell"
        # Кодеки A2DP: LDAC выключен, наушники играют AAC.
        # Почему — в самом конфиге и в docs/bluetooth-audio.md.
        ".config/wireplumber"
        # Дефолтные приложения: без него xdg-open после восстановления не знает,
        # чем открывать ссылки, и http/https уходят в случайный .desktop.
        ".config/mimeapps.list"
    )

    for item in "${items[@]}"; do
        local src="$SCRIPT_DIR/$item"
        local dest="$HOME/$item"

        if [[ -e "$src" ]]; then
            local parent_dir=$(dirname "$dest")
            mkdir -p "$parent_dir"
            rm -rf "$dest"
            cp -r "$src" "$dest"
            log_info "Скопировано: $item"
        fi
    done

    log_info "Конфиги скопированы"
}

# ==========================================
# 10. Делаем скрипты исполняемыми
# ==========================================
make_scripts_executable() {
    log_info "Делаем скрипты исполняемыми..."

    chmod +x ~/.config/hypr/scripts/*.sh 2>/dev/null || true
    chmod +x ~/.config/waybar/scripts/*.sh 2>/dev/null || true
    chmod +x ~/.config/scripts/*.sh 2>/dev/null || true

    # Модули waybar для CPU, памяти и диска написаны на Python. Без бита
    # исполнения waybar их просто не запустит, и три модуля будут пустыми —
    # молча, без единой ошибки в логе.
    chmod +x ~/.config/hypr/scripts/*.py 2>/dev/null || true
    chmod +x ~/.config/waybar/scripts/*.py 2>/dev/null || true

    # Каталоги, в которые пишут кнопка записи экрана и hyprshot. Оба
    # инструмента их сами не создают: wf-recorder упадёт на открытии файла,
    # hyprshot сохранит снимок мимо.
    mkdir -p ~/records ~/Pictures/Screenshots

    log_info "Скрипты готовы"
}

# ==========================================
# 11. Установка zsh по умолчанию
# ==========================================
set_default_shell() {
    log_info "Установка zsh как shell по умолчанию..."

    if [[ "$SHELL" != *"zsh"* ]]; then
        sudo usermod -s /usr/bin/zsh "$USER"
        log_info "zsh установлен по умолчанию. Перелогинься для применения."
    else
        log_info "zsh уже установлен по умолчанию"
    fi
}

# ==========================================
# MAIN
# ==========================================
main() {
    setup_repo_guards
    install_yay
    install_pacman_packages
    install_aur_packages
    setup_nvidia          # до setup_gpu_fan: вентиляторами управляет драйвер
    setup_sddm
    install_fonts
    setup_gpu_fan
    setup_system_fan
    install_hk_translator
    install_kbd_layout_toggle
    install_ddcci_backlight
    enable_system_services
    setup_remote_ssh
    install_bt_audio      # после enable_system_services: ему нужны поднятые pipewire и bluetooth
    install_ohmyzsh
    # setup_voice_input — отключено. Голосовой ввод висел на голом F11 и
    # глобально съедал фуллскрин в браузерах и видеоплеерах. Venv на 2.7 ГБ
    # с CUDA-библиотеками ставился при каждом прогоне. Вернуть: раскомментировать
    # здесь и бинды F11 в .config/hypr/hyprland.lua.
    copy_configs
    install_ai_harnesses
    install_cship         # после copy_configs: ему нужен уже лежащий ~/.config/cship.toml
    setup_singbox
    make_scripts_executable
    install_lazyvim
    set_default_shell

    # Установка тёмной темы по умолчанию.
    # Имя темы — именно 'Adwaita-dark', а НЕ 'Adwaita:dark'. Суффикс ":dark"
    # GTK3 понимает только у переменной окружения GTK_THEME; через gsettings он
    # ищется как буквальное имя темы, не находится, и GTK3 молча остаётся на
    # светлой. Тема Adwaita-dark приезжает из gnome-themes-extra.
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
    gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    # Цель относительная, а не полный путь: оба каталога лежат в git, и
    # абсолютная ссылка зашила бы в репу /home/<текущий юзер>.
    ln -sfn "style-dark.css" "$HOME/.config/waybar/style.css"
    # swaync, в отличие от waybar, портал НЕ слушает: он читает ровно
    # ~/.config/swaync/style.css и ничего сам не выбирает. Поэтому активная
    # тема задаётся симлинком, а переключает его toggle-theme.sh с
    # последующим `swaync-client --reload-css`.
    ln -sfn "style-dark.css" "$HOME/.config/swaync/style.css"
    echo "dark" > "$HOME/.config/hypr/.theme-state"
    log_info "Тёмная тема установлена (переключение: Ctrl+Y)"

    # Перезагрузка Hyprland конфига и перезапуск панели/обоев
    hyprctl reload 2>/dev/null && log_info "Hyprland конфиг перезагружен" || true
    pkill -x waybar 2>/dev/null || true
    if [[ -x "$HOME/.local/bin/waybar" ]]; then
        "$HOME/.local/bin/waybar" &disown
    else
        waybar &disown
    fi
    # awww-daemon НЕ уходит в фон сам (ключа --daemonize у него нет), поэтому
    # `awww-daemon && awww img ...` зависал бы на первой команде и обои никогда
    # не ставились. Запускаем в фон явно.
    pkill -x awww-daemon 2>/dev/null || true; awww-daemon &disown; sleep 1
    WALL=$(cat ~/.cache/current_wallpaper 2>/dev/null || echo "$HOME/wallpapers/1.jpg")
    if [ -f "$WALL" ]; then
        awww img "$WALL" --transition-type none
    else
        log_warn "Обоев нет ($WALL) — рабочий стол останется чёрным. Положи файлы в ~/wallpapers/"
    fi
    log_info "waybar и awww перезапущены"

    echo ""
    echo "=========================================="
    if (( WARN_COUNT > 0 )); then
        echo -e "${YELLOW}  Установка завершена с предупреждениями: $WARN_COUNT${NC}"
    else
        echo -e "${GREEN}  Установка завершена без предупреждений!${NC}"
    fi
    echo "=========================================="
    echo ""
    echo "Следующие шаги:"
    echo "  1. Если были [WARN], исправь их и повтори соответствующий шаг"
    echo "  2. Добавь в параметры ядра: nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    echo "  3. ПЕРЕЗАГРУЗИСЬ — greeter SDDM, GPU fan control, zsh, кривая nct6798"
    echo "  4. Запусти nvim для установки LazyVim плагинов"
    echo "  5. sing-box VPN toggle: Alt+P (сервер настроить в ~/.config/sing-box/config.json)"
    echo "  6. Заполни ~/.config/agents/secrets.env и выполни mcp-sync"
    echo ""
    echo "Проверки после ребута:"
    echo "  nvidia-smi -q | grep 'GSP Firmware'                 # должно быть N/A"
    echo "  nvidia-smi --query-gpu=fan.speed --format=csv       # не 0%"
    echo "  systemctl is-active sddm gpu-fan system-fan bluetooth nvidia-persistenced"
    echo "  systemctl is-active hk-translator kbd-layout-toggle ddcci-bind"
    echo "  hyprctl monitors                                    # частоты мониторов"
    echo "  pactl info | grep 'Server Name'                     # должен быть PipeWire"
    echo "  ls /sys/class/backlight/                            # ddcciN — яркость монитора"
    echo "  journalctl -u sddm -b | grep -i qml                 # тема гритера не должна падать"
    echo ""
    echo "Если что-то из этого пусто — смотри соответствующий раздел README."
    echo ""

    if (( WARN_COUNT > 0 )); then
        return 1
    fi
}

main "$@"
