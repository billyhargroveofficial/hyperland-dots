#!/usr/bin/env bash
# Мост между хуками Hermes и tmux-agent-indicator.
#
# Зачем отдельный скрипт, а не прямой вызов agent-state.sh из config.yaml:
#   • Hermes запускает команду через shlex.split с shell=False — перенаправления
#     и $HOME в строке команды не сработают, путь должен быть абсолютным;
#   • stdout хука Hermes читает как JSON, поэтому вывод agent-state.sh надо
#     проглотить и вернуть пустой объект.
#
# Аргумент — состояние для индикатора: running | needs-input | done.

state="${1:-}"
if [ -n "$state" ]; then
    "$HOME/.tmux/plugins/tmux-agent-indicator/scripts/agent-state.sh" \
        --agent hermes --state "$state" >/dev/null 2>&1 || true
fi
printf '{}'
