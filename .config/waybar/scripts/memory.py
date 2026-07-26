#!/usr/bin/env python3
"""Модуль памяти для waybar: занято/всего в тексте, пожиратели в попапе.

Встроенный модуль `memory` показывает только проценты и не умеет
произвольный tooltip — отсюда custom-модуль.

Считаем занятое как MemTotal - MemAvailable, а не через MemFree. MemFree не
учитывает кэш и буферы, которые ядро отдаст под запрос в любой момент: по нему
выходило бы «занято 65 из 94 ГБ» при реально свободных 79.

Процессы группируются по имени и суммируются: один Chrome — это полсотни
процессов, и в поштучном списке он занял бы весь попап своими вкладками.

RSS завышает общую сумму (разделяемые страницы считаются каждому процессу),
поэтому сумма по списку не сойдётся с «занято» в тексте. Для ответа на вопрос
«кто жрёт больше всех» это неважно, а PSS пришлось бы читать из
/proc/*/smaps_rollup — это сотни файлов на каждый тик.
"""

import html
import json
import subprocess


def meminfo():
    values = {}
    with open("/proc/meminfo", encoding="utf-8") as file:
        for line in file:
            key, _, rest = line.partition(":")
            values[key] = int(rest.split()[0]) * 1024  # kB -> байты
    return values


def gib(value):
    return value / 1024 ** 3


def top_processes(limit=12):
    out = subprocess.run(
        ["ps", "-eo", "rss=,comm="],
        capture_output=True, text=True, check=False,
    ).stdout
    totals = {}
    for line in out.splitlines():
        rss, _, comm = line.strip().partition(" ")
        comm = comm.strip()
        if not comm:
            continue
        try:
            totals[comm] = totals.get(comm, 0) + int(rss) * 1024
        except ValueError:
            continue
    return sorted(totals.items(), key=lambda kv: kv[1], reverse=True)[:limit]


info = meminfo()
total = info["MemTotal"]
used = total - info["MemAvailable"]
cached = info.get("Cached", 0) + info.get("Buffers", 0)

swap_total = info.get("SwapTotal", 0)
swap_used = swap_total - info.get("SwapFree", 0)

rows = [
    f"<b>Память</b>  {gib(used):.1f} / {gib(total):.1f} GB"
    f"  ({used / total * 100:.0f}%)",
    f"Кэш и буферы: {gib(cached):.1f} GB — освободятся по требованию",
]
if swap_total:
    rows.append(f"Swap: {gib(swap_used):.1f} / {gib(swap_total):.1f} GB")
rows.append("")
rows.append("<b>Больше всего занимают</b>")

for name, size in top_processes():
    label = html.escape(name)[:22]
    rows.append(f"<tt>{gib(size):6.2f} GB  {label}</tt>")

print(json.dumps({
    "text": f"󰘚  {gib(used):.1f}/{gib(total):.0f}G",
    "tooltip": "\n".join(rows),
    "percentage": round(used / total * 100),
    "class": "critical" if used / total > 0.9 else "normal",
}, ensure_ascii=False))
