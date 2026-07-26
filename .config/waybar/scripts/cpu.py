#!/usr/bin/env python3
"""Модуль процессора для waybar: загрузка в тексте, пожиратели в попапе.

Главная тонкость — что считать «жрёт процессор». `ps -eo pcpu` и первая
итерация `top -bn1` дают среднее за ВСЁ время жизни процесса: браузер,
открытый десять часов назад, будет вечно висеть в топе с процентами, которые
он набрал ночью, а реальный текущий пожиратель — не виден.

Поэтому считаем дельту сами: запоминаем utime+stime каждого процесса и общее
время из /proc/stat, а на следующем тике делим приращения. Получается
загрузка ровно за промежуток между обновлениями модуля, то есть то, что
происходит прямо сейчас.

Снимок лежит в $XDG_RUNTIME_DIR и переживает между вызовами — sleep внутри
скрипта не нужен, waybar не блокируется ни на миллисекунду. Цена — первый
вызов после старта показать проценты не может, там ещё не с чем сравнивать.

Чтобы попап жил, пока на него смотрят, у модуля маленький interval: waybar
перерисовывает открытый tooltip на каждом обновлении.

Проценты нормированы на одно ядро, как в top: процесс, занявший два ядра
целиком, покажет 200%.
"""

import html
import json
import os
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
STATE = os.path.join(RUNTIME, "waybar-cpu-prev.json")
TOP_N = 12
CLOCK = os.sysconf("SC_CLK_TCK")
CORES = os.cpu_count() or 1


def total_jiffies():
    with open("/proc/stat", encoding="utf-8") as file:
        parts = file.readline().split()[1:]
    values = [int(v) for v in parts]
    idle = values[3] + (values[4] if len(values) > 4 else 0)
    return sum(values), idle


def process_times():
    """{pid: (имя, utime+stime в тиках)} для всех живых процессов."""
    result = {}
    for entry in os.scandir("/proc"):
        if not entry.name.isdigit():
            continue
        try:
            with open(f"/proc/{entry.name}/stat", encoding="utf-8") as file:
                data = file.read()
        except (OSError, ProcessLookupError):
            continue
        # Имя в скобках может содержать пробелы и скобки — режем по последней.
        open_paren, close_paren = data.find("("), data.rfind(")")
        if open_paren < 0 or close_paren < 0:
            continue
        name = data[open_paren + 1:close_paren]
        fields = data[close_paren + 2:].split()
        try:
            result[entry.name] = (name, int(fields[11]) + int(fields[12]))
        except (IndexError, ValueError):
            continue
    return result


now_total, now_idle = total_jiffies()
now_procs = process_times()
now_stamp = time.time()

previous = None
if os.path.exists(STATE):
    try:
        with open(STATE, encoding="utf-8") as file:
            previous = json.load(file)
    except (OSError, ValueError):
        previous = None

snapshot = {
    "stamp": now_stamp,
    "total": now_total,
    "idle": now_idle,
    "procs": {pid: [name, ticks] for pid, (name, ticks) in now_procs.items()},
}
tmp = STATE + ".tmp"
with open(tmp, "w", encoding="utf-8") as file:
    json.dump(snapshot, file)
os.replace(tmp, STATE)

busy_percent = None
top = []
if previous and now_total > previous["total"]:
    delta_total = now_total - previous["total"]
    delta_idle = now_idle - previous["idle"]
    busy_percent = max(0.0, min(100.0, (1 - delta_idle / delta_total) * 100))

    grouped = {}
    for pid, (name, ticks) in now_procs.items():
        old = previous["procs"].get(pid)
        if not old or old[0] != name:
            continue
        delta = ticks - old[1]
        if delta > 0:
            grouped[name] = grouped.get(name, 0) + delta
    # delta_total уже просуммировано по всем ядрам, поэтому умножаем на CORES,
    # чтобы получить привычную шкалу top: 100% = одно ядро.
    top = sorted(
        ((name, ticks / delta_total * 100 * CORES) for name, ticks in grouped.items()),
        key=lambda kv: kv[1], reverse=True,
    )[:TOP_N]

load1, load5, load15 = os.getloadavg()

if busy_percent is None:
    text = "󰻠  …"
    rows = ["<b>Процессор</b>", "первое измерение — проценты появятся через тик"]
else:
    text = f"󰻠  {busy_percent:.0f}%"
    rows = [
        f"<b>Процессор</b>  {busy_percent:.1f}%  ({CORES} потоков)",
        f"Средняя нагрузка: {load1:.2f} / {load5:.2f} / {load15:.2f}",
        "",
        "<b>Больше всего забирают сейчас</b>",
    ]
    if top:
        for name, percent in top:
            rows.append(f"<tt>{percent:6.1f}%  {html.escape(name)[:22]}</tt>")
    else:
        rows.append("<tt>простой — заметных потребителей нет</tt>")

print(json.dumps({
    "text": text,
    "tooltip": "\n".join(rows),
    "percentage": round(busy_percent) if busy_percent is not None else 0,
    "class": "critical" if busy_percent is not None and busy_percent > 90 else "normal",
}, ensure_ascii=False))
