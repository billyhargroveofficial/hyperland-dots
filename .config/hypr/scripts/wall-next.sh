#!/bin/bash

WALLDIR="$HOME/wallpapers"
CACHE_FILE="$HOME/.cache/current_wallpaper"

# Создаем кеш-файл если его нет
if [[ ! -f "$CACHE_FILE" ]]; then
    echo "" > "$CACHE_FILE"
fi

# Получаем текущую обоину из кеша
CURRENT=$(cat "$CACHE_FILE")

# Получаем список всех .jpg и .png файлов, отсортированных
readarray -t FILES < <(find "$WALLDIR" -type f \( -iname "*.jpg" -o -iname "*.png" -o -iname "*.jpeg" -o -iname "*.webp" \) | sort)

# Если список пуст — выходим
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "❌ Нет файлов в $WALLDIR"
  exit 1
fi

# Если текущая обоина не найдена — начать с первой
NEXT="${FILES[0]}"
for i in "${!FILES[@]}"; do
    if [[ "${FILES[$i]}" == "$CURRENT" ]]; then
        NEXT_INDEX=$(( (i + 1) % ${#FILES[@]} ))
        NEXT="${FILES[$NEXT_INDEX]}"
        break
    fi
done

# Сохраняем новую обоину в кеш
echo "$NEXT" > "$CACHE_FILE"

# Устанавливаем обоину через awww с переходом "grow" (кружок из центра) и 144 FPS
awww img "$NEXT" --transition-type grow --transition-duration 1 --transition-fps 144

echo "✅ Установлена обойка: $(basename "$NEXT")"
