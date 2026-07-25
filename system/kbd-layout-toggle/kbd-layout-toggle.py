#!/usr/bin/env python3
"""
kbd-layout-toggle — переключение раскладки по Alt+Shift на уровне evdev.

Зачем отдельный демон, а не kb_options = grp:alt_shift_toggle:
раскладка в Hyprland живёт ОТДЕЛЬНО у каждого устройства, а ввод здесь идёт
через виртуальные клавиатуры hk-translator. xkb переключал группу только у
того устройства, на котором нажали, и устройства разъезжались.
`hyprctl switchxkblayout all` переключает разом все.

Клавиатуры читаются БЕЗ grab() — этот демон не может отобрать или потерять
ввод, он только слушает. Захваченные кем-то ещё устройства просто молчат.
"""

import glob
import os
import selectors
import subprocess
import sys
import time

import evdev
from evdev import ecodes

ALT = {ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT}
SHIFT = {ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT}

RESCAN_INTERVAL = 5.0  # секунд — подхват горячего подключения клавиатур


def hyprctl(*args):
    """Вызвать hyprctl. Демон работает от root, поэтому сокет ищем сами:
    HYPRLAND_INSTANCE_SIGNATURE меняется при каждом рестарте Hyprland."""
    dirs = glob.glob('/run/user/1000/hypr/*')
    dirs = [d for d in dirs if os.path.isdir(d)]
    if not dirs:
        return
    his = os.path.basename(max(dirs, key=os.path.getmtime))
    env = dict(os.environ,
               HYPRLAND_INSTANCE_SIGNATURE=his,
               XDG_RUNTIME_DIR='/run/user/1000')
    subprocess.run(['hyprctl', *args], env=env,
                   capture_output=True, timeout=5)


def is_keyboard(dev):
    """Настоящая клавиатура: буквы + модификаторы и НЕ указательное устройство.
    Проверка на мышь обязательна — HID-интерфейс Logitech G102 объявляет
    273 «клавиши» и притворяется клавиатурой убедительнее настоящей."""
    caps = dev.capabilities()
    if ecodes.EV_KEY not in caps:
        return False
    keys = set(caps[ecodes.EV_KEY])
    if ecodes.EV_REL in caps or ecodes.BTN_LEFT in keys:
        return False
    need = {ecodes.KEY_A, ecodes.KEY_Z, ecodes.KEY_LEFTCTRL,
            ecodes.KEY_LEFTSHIFT, ecodes.KEY_LEFTALT, ecodes.KEY_SPACE}
    return need <= keys


def scan():
    found = {}
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        if is_keyboard(dev):
            found[path] = dev
        else:
            dev.close()
    return found


def main():
    sel = selectors.DefaultSelector()
    watched = {}

    def sync_devices():
        current = scan()
        for path in list(watched):
            if path not in current:
                try:
                    sel.unregister(watched[path])
                    watched[path].close()
                except Exception:
                    pass
                del watched[path]
                print(f'отключилась: {path}', flush=True)
        for path, dev in current.items():
            if path in watched:
                dev.close()
                continue
            try:
                sel.register(dev, selectors.EVENT_READ)
            except Exception:
                dev.close()
                continue
            watched[path] = dev
            print(f'слушаю: {path:18s} {dev.name}', flush=True)

    sync_devices()
    if not watched:
        print('клавиатур не найдено', file=sys.stderr, flush=True)

    held = set()
    armed = False    # Alt+Shift зажаты прямо сейчас
    tainted = False  # во время удержания нажали ещё клавишу → это хоткей
    last_scan = time.monotonic()

    while True:
        for key, _ in sel.select(timeout=RESCAN_INTERVAL):
            dev = key.fileobj
            try:
                events = list(dev.read())
            except OSError:
                # Устройство исчезло. Мёртвый fd нельзя оставлять в селекторе:
                # он навсегда «готов к чтению», и до ближайшего пересканирования
                # цикл крутится вхолостую, съедая ядро CPU.
                path = dev.path
                try:
                    sel.unregister(dev)
                except Exception:
                    pass
                try:
                    dev.close()
                except Exception:
                    pass
                watched.pop(path, None)
                held.clear()
                armed = tainted = False
                print(f'отключилась: {path}', flush=True)
                continue
            for ev in events:
                if ev.type != ecodes.EV_KEY:
                    continue

                if ev.code in ALT | SHIFT:
                    if ev.value == 1:
                        held.add(ev.code)
                    elif ev.value == 0:
                        held.discard(ev.code)
                elif ev.value == 1 and armed:
                    # Пока держали Alt+Shift, нажали ещё клавишу — значит это
                    # хоткей (Alt+Shift+H — перенос окна, и такого много,
                    # $mainMod теперь ALT). Раскладку не трогаем.
                    tainted = True

                combo = bool(held & ALT) and bool(held & SHIFT)
                if combo and not armed:
                    armed = True
                    tainted = False
                elif not combo and armed:
                    # Сработка на ОТПУСКАНИИ и только если Alt+Shift нажали
                    # вхолостую. Иначе каждый хоткей менял бы язык.
                    armed = False
                    if not tainted:
                        hyprctl('switchxkblayout', 'all', 'next')
                        print('Alt+Shift → переключил', flush=True)

        if time.monotonic() - last_scan >= RESCAN_INTERVAL:
            last_scan = time.monotonic()
            before = set(watched)
            sync_devices()
            if set(watched) != before:
                # Набор клавиатур изменился. Состояние удержания могло остаться
                # от исчезнувшего устройства (выдернули клавиатуру с зажатым
                # Alt → held навсегда с ALT → следующий же Shift даёт ложное
                # переключение раскладки). Сбрасываем.
                held.clear()
                armed = tainted = False


if __name__ == '__main__':
    main()
