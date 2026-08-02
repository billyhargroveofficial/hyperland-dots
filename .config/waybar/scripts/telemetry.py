#!/usr/bin/env python3
"""Compact icon-free hardware telemetry for the center Waybar island."""

from __future__ import annotations

import json
import math
import os
import re
import subprocess


GIB = 1024 ** 3


def rounded(value: float) -> int:
    return int(value + 0.5)


def cpu_temperature() -> float | None:
    result = subprocess.run(
        ["sensors", "k10temp-pci-00c3"],
        capture_output=True,
        text=True,
        check=False,
    )
    match = re.search(r"^Tctl:\s+\+?([0-9.]+)°C", result.stdout, re.MULTILINE)
    return float(match.group(1)) if match else None


def gpu_status() -> tuple[float | None, float | None, float | None]:
    result = subprocess.run(
        [
            "nvidia-smi",
            "--query-gpu=temperature.gpu,memory.used,memory.total",
            "--format=csv,noheader,nounits",
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    try:
        temperature, used_mib, total_mib = (
            float(value.strip()) for value in result.stdout.splitlines()[0].split(",")
        )
    except (IndexError, ValueError):
        return None, None, None
    return temperature, used_mib / 1024, total_mib / 1024


def memory_status() -> tuple[float, float, int]:
    values: dict[str, int] = {}
    with open("/proc/meminfo", encoding="utf-8") as meminfo:
        for line in meminfo:
            key, _, rest = line.partition(":")
            values[key] = int(rest.split()[0]) * 1024
    actual_total = values["MemTotal"] / GIB
    used = (values["MemTotal"] - values["MemAvailable"]) / GIB
    # Ядро резервирует часть памяти, поэтому 96 GiB модулей видны как ~94 GiB.
    # В короткой строке показываем понятный установленный объём.
    installed_total = math.ceil(actual_total / 8) * 8
    return used, actual_total, installed_total


def disk_status(path: str = "/home") -> tuple[float, float]:
    stat = os.statvfs(path)
    total = stat.f_blocks * stat.f_frsize / GIB
    used = (stat.f_blocks - stat.f_bavail) * stat.f_frsize / GIB
    return used, total


cpu = cpu_temperature()
gpu, vram_used, vram_total = gpu_status()
ram_used, ram_actual_total, ram_installed_total = memory_status()
ssd_used, ssd_total = disk_status()


def degree(value: float | None) -> str:
    return "?" if value is None else str(rounded(value))


def amount(value: float | None) -> str:
    return "?" if value is None else str(rounded(value))


text = (
    f"cpu: {degree(cpu)}°C  gpu: {degree(gpu)}°C"
    f"  |  ram: {rounded(ram_used)}/{ram_installed_total}"
    f"  vram: {amount(vram_used)}/{amount(vram_total)}"
    f"  |  ssd: {rounded(ssd_used)}/{rounded(ssd_total)}"
)

tooltip = (
    f"CPU: {cpu:.1f} °C\n" if cpu is not None else "CPU: нет данных\n"
)
tooltip += f"GPU: {gpu:.0f} °C\n" if gpu is not None else "GPU: нет данных\n"
tooltip += f"RAM: {ram_used:.1f} / {ram_actual_total:.1f} GiB\n"
if vram_used is not None and vram_total is not None:
    tooltip += f"VRAM: {vram_used:.1f} / {vram_total:.1f} GiB\n"
tooltip += f"SSD /home: {ssd_used:.1f} / {ssd_total:.1f} GiB"

print(json.dumps({"text": text, "tooltip": tooltip}, ensure_ascii=False))
