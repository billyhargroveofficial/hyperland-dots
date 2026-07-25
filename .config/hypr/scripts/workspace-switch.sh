#!/bin/bash
# Переключение воркспейсов
# Usage: workspace-switch.sh <number> [move]
#
# Монитор в системе один (DP-3), и все воркспейсы 1..10 привязаны к нему в
# hyprland.conf, поэтому логики выбора монитора здесь нет и не требуется:
# `hyprctl dispatch workspace` сам переносит фокус на нужный монитор.
# Обёртка оставлена как единая точка правки на случай второго монитора.

set -euo pipefail

TARGET=${1:-}
ACTION=${2:-}

# Без проверки пустой или мусорный аргумент уезжал в hyprctl, а тот молча
# трактовал его как имя *именованного* воркспейса и создавал лишний стол.
if [[ ! "$TARGET" =~ ^[0-9]+$ ]]; then
    echo "usage: $(basename "$0") <номер воркспейса> [move]" >&2
    exit 1
fi

if [[ "$ACTION" == "move" ]]; then
    hyprctl dispatch movetoworkspace "$TARGET"
else
    hyprctl dispatch workspace "$TARGET"
fi
