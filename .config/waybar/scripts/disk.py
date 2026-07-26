#!/usr/bin/env python3
"""Модуль диска для waybar: занято/всего в тексте, пожиратели в попапе.

Текст показывает /home — там лежат все данные. Корень (/) держит только
систему и живёт на втором NVMe, его размер в тексте был бы бесполезен: 17 из
915 ГБ, вечные 2%. Оба раздела и /boot видно в попапе.

Список крупнейших каталогов считает `du`, а это десятки секунд по сотне
гигабайт — в горячем пути модуля такому не место, waybar встал бы колом на
каждом тике. Поэтому результат кэшируется, а пересчёт уходит в фон:

  * попап всегда рисуется мгновенно из кэша;
  * кэш старше TTL запускает фоновый пересчёт и показывает пока прежние цифры;
  * lock-файл не даёт наплодить несколько `du` разом.

`du -x` обязателен: без него счёт уходит в /home/billy/.cache/gvfs и прочие
чужие точки монтирования, и цифры перестают относиться к этому разделу.
"""

import html
import json
import os
import shutil
import subprocess
import sys
import time

TARGET = sys.argv[1] if len(sys.argv) > 1 else "/home"
SCAN_DIR = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
CACHE = os.path.join(RUNTIME, "waybar-disk-top.json")
LOCK = os.path.join(RUNTIME, "waybar-disk-top.lock")
TTL = 30 * 60
TOP_N = 12


def gib(value):
    return value / 1024 ** 3


def usage(path):
    stat = os.statvfs(path)
    total = stat.f_blocks * stat.f_frsize
    free = stat.f_bavail * stat.f_frsize
    return total - free, total


def mounts():
    result = []
    seen = set()
    with open("/proc/mounts", encoding="utf-8") as file:
        for line in file:
            device, point = line.split()[0], line.split()[1]
            if not device.startswith("/dev/") or point in seen:
                continue
            seen.add(point)
            try:
                result.append((point, *usage(point)))
            except OSError:
                continue
    return sorted(result)


def spawn_scan():
    """Фоновый пересчёт каталогов. Ничего не ждём и не блокируемся."""
    if os.path.exists(LOCK) and time.time() - os.path.getmtime(LOCK) < 3600:
        return
    open(LOCK, "w").close()
    script = (
        f"du -x -d1 {SCAN_DIR!r} 2>/dev/null | sort -rn > {CACHE}.tmp "
        f"&& mv {CACHE}.tmp {CACHE}; rm -f {LOCK}"
    )
    subprocess.Popen(["sh", "-c", script], start_new_session=True,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def cached_top():
    if not os.path.exists(CACHE):
        spawn_scan()
        return None, True
    stale = time.time() - os.path.getmtime(CACHE) > TTL
    if stale:
        spawn_scan()
    rows = []
    with open(CACHE, encoding="utf-8") as file:
        for line in file:
            size, _, path = line.strip().partition("\t")
            if not path or os.path.realpath(path) == os.path.realpath(SCAN_DIR):
                continue
            try:
                rows.append((int(size) * 1024, path))
            except ValueError:
                continue
    return rows[:TOP_N], stale


used, total = usage(TARGET)
lines = [f"<b>Диски</b>"]
for point, point_used, point_total in mounts():
    percent = point_used / point_total * 100 if point_total else 0
    lines.append(
        f"<tt>{point:<8} {gib(point_used):6.1f} / {gib(point_total):6.1f} GB"
        f"  ({percent:.0f}%)</tt>"
    )

rows, stale = cached_top()
lines.append("")
if rows is None:
    lines.append("<b>Больше всего занимают</b> — считается, попап обновится сам")
else:
    suffix = " (обновляется…)" if stale else ""
    lines.append(f"<b>Больше всего занимают в ~{suffix}</b>")
    for size, path in rows:
        name = html.escape(os.path.basename(path.rstrip("/")) or path)[:22]
        lines.append(f"<tt>{gib(size):6.1f} GB  {name}</tt>")

print(json.dumps({
    "text": f"󰋊  {gib(used):.0f}/{gib(total):.0f}G",
    "tooltip": "\n".join(lines),
    "percentage": round(used / total * 100) if total else 0,
    "class": "critical" if total and used / total > 0.9 else "normal",
}, ensure_ascii=False))
