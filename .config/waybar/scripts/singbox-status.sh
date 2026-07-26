#!/bin/bash

LOG_FILE="$HOME/.local/share/singbox-traffic.log"
DIRECT_DOMAINS="*.ru (все .ru домены)"

get_recent_traffic() {
    if [[ ! -f "$LOG_FILE" ]]; then
        echo "Нет данных"
        return
    fi

    local direct_list=""
    local proxy_list=""
    local seen_direct=""
    local seen_proxy=""

    # Get .ru domains (direct)
    while IFS= read -r line; do
        if [[ "$line" =~ dns:\ exchanged\ [A-Z]+\ ([a-zA-Z0-9.-]+\.ru)\. ]]; then
            local domain="${BASH_REMATCH[1]}"
            if [[ ! "$seen_direct" =~ "$domain" ]]; then
                [[ -n "$direct_list" ]] && direct_list="${direct_list}, "
                direct_list="${direct_list}${domain}"
                seen_direct="$seen_direct $domain"
            fi
        fi
    done < <(tail -200 "$LOG_FILE" 2>/dev/null | grep "dns: exchanged" | tail -10)

    # Get non-.ru domains (proxy)
    while IFS= read -r line; do
        if [[ "$line" =~ dns:\ exchanged\ [A-Z]+\ ([a-zA-Z0-9.-]+\.[a-zA-Z]{2,})\. ]]; then
            local domain="${BASH_REMATCH[1]}"
            if [[ ! "$domain" =~ \.ru$ ]] && [[ "$domain" != *"arpa"* ]] && [[ "$domain" != *"local"* ]]; then
                if [[ ! "$seen_proxy" =~ "$domain" ]]; then
                    [[ -n "$proxy_list" ]] && proxy_list="${proxy_list}, "
                    proxy_list="${proxy_list}${domain}"
                    seen_proxy="$seen_proxy $domain"
                fi
            fi
        fi
    done < <(tail -200 "$LOG_FILE" 2>/dev/null | grep "dns: exchanged" | tail -10)

    # Truncate if too long
    [[ ${#direct_list} -gt 60 ]] && direct_list="${direct_list:0:57}..."
    [[ ${#proxy_list} -gt 60 ]] && proxy_list="${proxy_list:0:57}..."

    local result=""
    [[ -n "$direct_list" ]] && result="Direct: ${direct_list}"
    if [[ -n "$proxy_list" ]]; then
        [[ -n "$result" ]] && result="${result}\\nProxy: ${proxy_list}"
        [[ -z "$result" ]] && result="Proxy: ${proxy_list}"
    fi

    [[ -z "$result" ]] && result="Ожидание трафика..."
    echo "$result"
}

if pgrep -x sing-box > /dev/null; then
    recent=$(get_recent_traffic)
    tooltip="VLESS VPN активен\\nРоуты: ${DIRECT_DOMAINS}\\n\\n${recent}"
    echo "{\"text\": \"󰌾  On\", \"class\": \"connected\", \"tooltip\": \"${tooltip}\"}"
else
    echo "{\"text\": \"󰌾  Off\", \"class\": \"disconnected\", \"tooltip\": \"VPN выключен\"}"
fi
