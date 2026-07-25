#!/bin/bash

# Restart script for Hyprland and related services
# Bind: $mainMod CTRL + W

export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t /run/user/1000/hypr/ 2>/dev/null | head -1)

echo "Restarting Hyprland services..."

# Restart waybar
pkill waybar 2>/dev/null
sleep 0.5
waybar &disown

# Restart wallpaper
pkill awww-daemon 2>/dev/null
sleep 0.5
awww-daemon &disown
sleep 1
WALLPAPER=$(grep 'awww img' ~/.config/hypr/hyprland.conf | sed 's/.*awww img //' | sed 's/ --.*//' | head -1)
eval awww img "$WALLPAPER" --transition-type none &

# Restart clipboard manager
pkill wl-paste 2>/dev/null
sleep 0.5
wl-paste --type text --watch cliphist store &
wl-paste --type image --watch cliphist store &

# Restart nwg-dock (per monitor, filtered by workspaces)
pkill nwg-dock-hyprla 2>/dev/null
sleep 0.5
nwg-dock-hyprland -d -l overlay -p bottom -i 48 -nolauncher -o DP-1 -m -iw "11,12,13,14,15,16,17,18,19,20" &disown
nwg-dock-hyprland -d -l overlay -p bottom -i 48 -nolauncher -o DP-2 -m -iw "1,2,3,4,5,6,7,8,9,10" &disown

# Restart hyprshell (alt-tab switcher)
hyprshell socat '"Restart"' 2>/dev/null || { hyprshell run & disown; }

# Reload Hyprland config
hyprctl reload

echo "Restart complete!"
