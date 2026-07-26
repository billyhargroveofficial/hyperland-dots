#!/bin/bash

# ============================================
# NVIDIA GPU Fan Control Setup for Wayland/Hyprland
# ============================================
#
# Проблема: На Wayland (Hyprland) нельзя управлять вентиляторами GPU через
# nvidia-settings, т.к. он требует X сервер с NV-CONTROL extension.
# XWayland не подходит - он не читает xorg.conf и не имеет Coolbits.
#
# Решение: Systemd сервис который запускается ДО display manager,
# поднимает временный X сервер, настраивает вентиляторы и убивает X.
# Настройки вентиляторов сохраняются после закрытия X сервера.
#
# Требования:
# - nvidia-settings
# - xorg-server (не xvfb!)
# - Coolbits=4 в xorg.conf
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo -e "${GREEN}=== NVIDIA GPU Fan Control Setup ===${NC}"

# Проверка nvidia
if ! lspci | grep -qi nvidia; then
    echo -e "${RED}NVIDIA GPU not found. Exiting.${NC}"
    exit 1
fi

# Получаем BusID видеокарты
BUS_ID=$(lspci | grep -i 'vga.*nvidia' | awk '{print $1}' | head -1)
if [[ -z "$BUS_ID" ]]; then
    BUS_ID=$(lspci | grep -i nvidia | awk '{print $1}' | head -1)
fi

# Конвертируем BusID в формат для xorg (09:00.0 -> PCI:9:0:0)
BUS_ID_XORG=$(echo "$BUS_ID" | awk -F'[:.]' '{printf "PCI:%d:%d:%d", "0x"$1, "0x"$2, $3}')
echo "Detected NVIDIA GPU at: $BUS_ID -> $BUS_ID_XORG"

# 1. Устанавливаем необходимые пакеты
echo "Installing required packages..."
sudo pacman -S --needed --noconfirm nvidia-settings xorg-server

# 2. Создаём xorg.conf с Coolbits
echo "Creating xorg.conf with Coolbits..."
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

# 3. Создаём скрипт настройки вентиляторов
echo "Creating fan control script..."
sudo tee /usr/local/bin/gpu-fan-setup.sh > /dev/null << 'SCRIPT'
#!/bin/bash
LOG="/var/log/gpu-fan.log"
FAN_SPEED="${GPU_FAN_SPEED:-62}"

echo "[$(date)] Starting GPU fan setup (target: ${FAN_SPEED}%)..." >> $LOG

# Запускаем временный X
X :99 -config /etc/X11/xorg.conf.d/20-nvidia.conf -sharevts -noreset &
XPID=$!
sleep 3

if kill -0 $XPID 2>/dev/null; then
    echo "[$(date)] X server started on :99" >> $LOG

    # Настраиваем вентиляторы
    DISPLAY=:99 nvidia-settings -a "[gpu:0]/GPUFanControlState=1" >> $LOG 2>&1
    DISPLAY=:99 nvidia-settings -a "[fan:0]/GPUTargetFanSpeed=$FAN_SPEED" >> $LOG 2>&1
    DISPLAY=:99 nvidia-settings -a "[fan:1]/GPUTargetFanSpeed=$FAN_SPEED" >> $LOG 2>&1

    SPEED=$(DISPLAY=:99 nvidia-settings -q "[fan:0]/GPUTargetFanSpeed" -t 2>/dev/null)
    echo "[$(date)] Fan speed set to: ${SPEED}%" >> $LOG

    # Убиваем X - настройки сохранятся
    kill $XPID 2>/dev/null
    echo "[$(date)] X server stopped, fan settings preserved" >> $LOG
else
    echo "[$(date)] ERROR: Failed to start X server" >> $LOG
    exit 1
fi
SCRIPT

sudo chmod +x /usr/local/bin/gpu-fan-setup.sh

# 4. Создаём systemd сервис
echo "Creating systemd service..."
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

# 5. Включаем сервис
echo "Enabling systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable gpu-fan.service

# 6. Добавляем sudoers правило для динамического контроля через XWayland
echo "Adding sudoers rule for nvidia-settings..."
echo "$USER ALL=(ALL) NOPASSWD: /usr/bin/nvidia-settings" | sudo tee /etc/sudoers.d/nvidia-settings > /dev/null
sudo chmod 440 /etc/sudoers.d/nvidia-settings

echo ""
echo -e "${GREEN}=== Setup Complete ===${NC}"
echo ""
echo "GPU Fan Control настроен:"
echo ""
echo "1. Systemd сервис (oneshot):"
echo "   - Устанавливает 62% при загрузке (до запуска Hyprland)"
echo "   - Изменить: sudo nano /etc/systemd/system/gpu-fan.service"
echo ""
echo "2. Демон gpu-fan-control.sh (динамическая кривая):"
echo "   - Запускается из hyprland.lua: hl.exec_cmd в hl.on(\"hyprland.start\")"
echo "   - 40% при ≤35°C -> 100% при ≥85°C"
echo "   - Логи: ~/.local/share/gpu-fan.log"
echo ""
echo "Commands:"
echo "  Check logs:    tail -f ~/.local/share/gpu-fan.log"
echo "  Check speed:   nvidia-smi --query-gpu=fan.speed,temperature.gpu --format=csv"
echo ""
echo "Reboot to apply!"
