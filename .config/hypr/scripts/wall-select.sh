#!/bin/bash

# Wallpaper selector with rofi and image previews (Catppuccin style)

WALLDIR="$HOME/wallpapers"
CACHE_DIR="$HOME/.cache/wallpaper-thumbs"
CACHE_FILE="$HOME/.cache/current_wallpaper"
ROFI_THEME="$HOME/.config/rofi/wallpaper.rasi"

# Create cache directory
mkdir -p "$CACHE_DIR"

# Generate larger thumbnails for better preview
for img in $(find "$WALLDIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \)); do
    [[ -f "$img" ]] || continue
    name=$(basename "$img")
    thumb="$CACHE_DIR/$name"

    if [[ ! -f "$thumb" ]] || [[ "$img" -nt "$thumb" ]]; then
        magick "$img" -thumbnail 280x160^ -gravity center -extent 280x160 "$thumb" 2>/dev/null
    fi
done

# Build menu with images
build_menu() {
    find "$WALLDIR" -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.webp" \) | sort | while read -r img; do
        name=$(basename "$img")
        thumb="$CACHE_DIR/$name"

        if [[ -f "$thumb" ]]; then
            echo -en "$name\0icon\x1f$thumb\n"
        else
            echo "$name"
        fi
    done
}

# Show rofi menu with Catppuccin theme
selected=$(build_menu | rofi -dmenu \
    -p "🖼️ Wallpaper" \
    -show-icons \
    -theme "$ROFI_THEME")

# Exit if nothing selected
[[ -z "$selected" ]] && exit 0

# Full path
fullpath="$WALLDIR/$selected"

# Check if file exists
if [[ ! -f "$fullpath" ]]; then
    notify-send "Wallpaper" "❌ Файл не найден: $selected" -i dialog-error
    exit 1
fi

# Save to cache
echo "$fullpath" > "$CACHE_FILE"

# Set wallpaper with cool animation
awww img "$fullpath" \
    --transition-type grow \
    --transition-pos center \
    --transition-duration 0.8 \
    --transition-fps 144

notify-send "Wallpaper" "✅ $selected" -i preferences-desktop-wallpaper
