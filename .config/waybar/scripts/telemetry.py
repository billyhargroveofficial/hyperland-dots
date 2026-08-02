#!/usr/bin/env python3
"""Cached hardware telemetry for the SVG-based center Waybar island."""

from __future__ import annotations

import fcntl
import json
import math
import os
import re
import subprocess
import sys
import time
from pathlib import Path


GIB = 1024 ** 3
CACHE_TTL_SECONDS = 4.25
METRICS = {"cpu", "gpu", "ram", "vram", "ssd"}


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


def degree(value: float | None) -> str:
    return "?" if value is None else str(rounded(value))


def amount(value: float | None) -> str:
    return "?" if value is None else str(rounded(value))


def collect_snapshot() -> dict[str, float | int | None]:
    cpu = cpu_temperature()
    gpu, vram_used, vram_total = gpu_status()
    ram_used, ram_actual_total, ram_installed_total = memory_status()
    ssd_used, ssd_total = disk_status()
    return {
        "cpu": cpu,
        "gpu": gpu,
        "ram_used": ram_used,
        "ram_actual_total": ram_actual_total,
        "ram_installed_total": ram_installed_total,
        "vram_used": vram_used,
        "vram_total": vram_total,
        "ssd_used": ssd_used,
        "ssd_total": ssd_total,
    }


def load_snapshot() -> dict[str, float | int | None]:
    runtime_dir = Path(os.environ.get("XDG_RUNTIME_DIR", f"/tmp/waybar-{os.getuid()}"))
    runtime_dir.mkdir(parents=True, exist_ok=True)
    cache_file = runtime_dir / "waybar-telemetry.json"
    lock_file = runtime_dir / "waybar-telemetry.lock"

    with lock_file.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            if time.time() - cache_file.stat().st_mtime <= CACHE_TTL_SECONDS:
                cached = json.loads(cache_file.read_text(encoding="utf-8"))
                if isinstance(cached, dict) and "ram_used" in cached:
                    return cached
        except (FileNotFoundError, json.JSONDecodeError, OSError, TypeError):
            pass

        snapshot = collect_snapshot()
        temporary = cache_file.with_name(f".{cache_file.name}.{os.getpid()}.tmp")
        temporary.write_text(json.dumps(snapshot), encoding="utf-8")
        os.replace(temporary, cache_file)
        return snapshot


def metric_payload(
    metric: str, snapshot: dict[str, float | int | None]
) -> dict[str, str]:
    cpu = snapshot["cpu"]
    gpu = snapshot["gpu"]
    ram_used = float(snapshot["ram_used"])
    ram_actual_total = float(snapshot["ram_actual_total"])
    ram_installed_total = int(snapshot["ram_installed_total"])
    vram_used = snapshot["vram_used"]
    vram_total = snapshot["vram_total"]
    ssd_used = float(snapshot["ssd_used"])
    ssd_total = float(snapshot["ssd_total"])

    if metric == "cpu":
        return {
            "text": f"{degree(cpu)}°C",
            "tooltip": f"CPU: {cpu:.1f} °C" if cpu is not None else "CPU: нет данных",
            "class": "normal" if cpu is not None else "unavailable",
        }
    if metric == "gpu":
        return {
            "text": f"{degree(gpu)}°C",
            "tooltip": f"GPU: {gpu:.0f} °C" if gpu is not None else "GPU: нет данных",
            "class": "normal" if gpu is not None else "unavailable",
        }
    if metric == "ram":
        return {
            "text": f"{rounded(ram_used)}/{ram_installed_total}",
            "tooltip": f"RAM: {ram_used:.1f} / {ram_actual_total:.1f} GiB",
            "class": "normal",
        }
    if metric == "vram":
        available = vram_used is not None and vram_total is not None
        return {
            "text": f"{amount(vram_used)}/{amount(vram_total)}",
            "tooltip": (
                f"VRAM: {vram_used:.1f} / {vram_total:.1f} GiB"
                if available
                else "VRAM: нет данных"
            ),
            "class": "normal" if available else "unavailable",
        }
    return {
        "text": f"{rounded(ssd_used)}/{rounded(ssd_total)}",
        "tooltip": f"SSD /home: {ssd_used:.1f} / {ssd_total:.1f} GiB",
        "class": "normal",
    }


def combined_payload(snapshot: dict[str, float | int | None]) -> dict[str, str]:
    parts = [metric_payload(metric, snapshot) for metric in ("cpu", "gpu", "ram", "vram", "ssd")]
    return {
        "text": (
            f"cpu: {parts[0]['text']}  gpu: {parts[1]['text']}  |  "
            f"ram: {parts[2]['text']}  vram: {parts[3]['text']}  |  "
            f"ssd: {parts[4]['text']}"
        ),
        "tooltip": "\n".join(part["tooltip"] for part in parts),
    }


requested_metric = sys.argv[1] if len(sys.argv) > 1 else "all"
if requested_metric != "all" and requested_metric not in METRICS:
    raise SystemExit(f"unknown metric: {requested_metric}")

data = load_snapshot()
payload = combined_payload(data) if requested_metric == "all" else metric_payload(requested_metric, data)
print(json.dumps(payload, ensure_ascii=False))
