#!/usr/bin/env bash
# Иконка AI-агента для КОНКРЕТНОГО окна tmux. Вызывается из
# window-status-format как #(~/.config/tmux/agent-win.sh #{window_id}).
# Печатает пустоту, если в окне нет агента.
#
# Зачем свой скрипт, а не #{agent_indicator} от tmux-agent-indicator:
#   • тот показывает агента только для окна, где сейчас клиент, — а нужно
#     видеть все вкладки разом;
#   • состояние он отображает через window-status-style, но тема macdots
#     задаёт цвета инлайн внутри window-status-format, а инлайн перебивает
#     style — штатная подсветка вкладок с ней не видна.
# Источник данных общий с плагином: глобальный tmux environment, куда
# локальные hooks пишут состояние агентов.

set -uo pipefail

win="${1:-}"
[ -n "$win" ] || exit 0

ICONS=$(tmux show-option -gqv "@agent-indicator-icons" 2>/dev/null)
PROCS=$(tmux show-option -gqv "@agent-indicator-processes" 2>/dev/null)
[ -n "$ICONS" ] || ICONS="default=🤖"
[ -n "$PROCS" ] || exit 0

icon_for() {
    local agent="$1" pair key val default="🤖"
    local -a pairs
    IFS=',' read -r -a pairs <<< "$ICONS"
    for pair in "${pairs[@]}"; do
        key="${pair%%=*}"; val="${pair#*=}"
        key="${key// /}"; val="${val// /}"
        [ "$key" = "default" ] && default="$val"
        [ "$key" = "$agent" ] && { printf '%s' "$val"; return; }
    done
    printf '%s' "$default"
}

# Один снимок env на всё окно — дешевле, чем вызов tmux на каждый пан.
env_snapshot=$(tmux show-environment -g 2>/dev/null | grep '^TMUX_AGENT_PANE_' || true)
get_env() { printf '%s\n' "$env_snapshot" | grep -m1 -F "$1=" | sed 's/^[^=]*=//'; }

# Окно с несколькими агентами показывает самый «громкий»: ждёт ввода важнее,
# чем просто работает, работа важнее завершения.
rank_of() {
    case "$1" in
        needs-input) echo 4 ;;
        running)     echo 3 ;;
        done)        echo 2 ;;
        *)           echo 1 ;;
    esac
}

best_rank=0; best_agent=""; best_state=""

while IFS=' ' read -r pane tty; do
    [ -n "$pane" ] || continue
    state=$(get_env "TMUX_AGENT_PANE_${pane}_STATE")
    agent=$(get_env "TMUX_AGENT_PANE_${pane}_AGENT")

    if [ -z "$state" ] || [ "$state" = "off" ]; then
        # Если hook ещё не прислал состояние — ищем настроенный локально
        # процесс среди всех процессов на tty пана. Проверяется полная
        # командная строка, поэтому работают и команды-обёртки.
        state=""; agent=""
        if [ -n "$tty" ]; then
            cmds=$(ps -t "$(basename "$tty")" -o command= 2>/dev/null || true)
            IFS=',' read -r -a plist <<< "$PROCS"
            for p in "${plist[@]}"; do
                p="${p// /}"
                [ -n "$p" ] || continue
                if printf '%s' "$cmds" | grep -qw -- "$p"; then
                    agent="$p"; state="present"; break
                fi
            done
        fi
    fi

    [ -n "$agent" ] || continue
    r=$(rank_of "$state")
    if [ "$r" -gt "$best_rank" ]; then
        best_rank=$r; best_agent="$agent"; best_state="$state"
    fi
done < <(tmux list-panes -t "$win" -F '#{pane_id} #{pane_tty}' 2>/dev/null)

[ -n "$best_agent" ] || exit 0

# Точка состояния рядом с иконкой: у эмодзи свой цвет, fg на них не влияет,
# поэтому состояние несёт отдельный глиф.
#
# Палитра зависит от того, активна ли вкладка: у активной фон светло-сиреневый
# (#cba6f7), у остальных тёмный (#313244). Один цвет на оба фона не ложится —
# светлые маркеры Catppuccin Mocha на сиреневом просто исчезают, поэтому для
# активной берутся тёмные насыщенные тона.
active=$(tmux display-message -p -t "$win" '#{window_active}' 2>/dev/null)

if [ "$active" = "1" ]; then
    case "$best_state" in
        needs-input) mark="#[fg=#8f4700]▲" ;;  # тёмно-янтарный — ждёт тебя
        running)     mark="#[fg=#14622a]●" ;;  # тёмно-зелёный — работает
        done)        mark="#[fg=#123a8f]✓" ;;  # тёмно-синий — закончил
        *)           mark="#[fg=#3d3f52]○" ;;  # графитовый — просто запущен
    esac
else
    case "$best_state" in
        needs-input) mark="#[fg=#f9e2af]▲" ;;
        running)     mark="#[fg=#a6e3a1]●" ;;
        done)        mark="#[fg=#89b4fa]✓" ;;
        *)           mark="#[fg=#7f849c]○" ;;
    esac
fi

printf '  %s %s' "$(icon_for "$best_agent")" "$mark"
