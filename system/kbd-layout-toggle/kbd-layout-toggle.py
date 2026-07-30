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

Архитектура: как в hk-translator — всё блокирующееся вынесено из цикла
чтения событий. Сканы /dev/input (open узла — это реальные USB-транзакции,
зависающие на десятки-сотни мс) и вызовы hyprctl (до 5 секунд по таймауту)
живут в рабочем потоке; цикл чтения только читает события и шлёт задания.
Каждый путь проверяется один раз за время его жизни — вердикт кэшируется.
"""

import glob
import os
import queue
import selectors
import socket
import subprocess
import sys
import threading

import evdev
from evdev import ecodes

ALT = {ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT}
SHIFT = {ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT}

RESCAN_INTERVAL = 5.0  # секунд — подхват горячего подключения клавиатур


def hyprctl(*args):
    """Вызвать hyprctl. Демон работает от root, поэтому сокет ищем сами:
    HYPRLAND_INSTANCE_SIGNATURE меняется при каждом рестарте Hyprland."""
    dirs = glob.glob('/run/user/*/hypr/*')
    dirs = [d for d in dirs if os.path.isdir(d)]
    if not dirs:
        return
    instance_dir = max(dirs, key=os.path.getmtime)
    his = os.path.basename(instance_dir)
    runtime_dir = os.path.dirname(os.path.dirname(instance_dir))
    env = dict(os.environ,
               HYPRLAND_INSTANCE_SIGNATURE=his,
               XDG_RUNTIME_DIR=runtime_dir)
    try:
        subprocess.run(['hyprctl', *args], env=env,
                       capture_output=True, timeout=5)
    except subprocess.TimeoutExpired:
        print('hyprctl: таймаут', file=sys.stderr, flush=True)


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


class Worker(threading.Thread):
    """Сканы устройств, close мёртвых fd и вызовы hyprctl."""

    def __init__(self, post):
        super().__init__(daemon=True, name='worker')
        self.post = post            # (kind, obj) → в цикл чтения
        self.jobs = queue.Queue()   # ('close', path, dev) | ('hyprctl', args)
        self.lock = threading.Lock()
        self.active = set()         # пути, отданные циклу чтения
        self.rejected = set()       # пути с отрицательным вердиктом

    def submit(self, kind, path=None, obj=None):
        self.jobs.put((kind, path, obj))

    def scan(self):
        try:
            paths = set(evdev.list_devices())
        except OSError:
            return
        with self.lock:
            gone = self.active - paths
            self.active -= gone
            self.rejected &= paths
            fresh = sorted(paths - self.active - self.rejected)
        for path in gone:
            self.post('del', path)
        for path in fresh:
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            if not is_keyboard(dev):
                try:
                    dev.close()
                except Exception:
                    pass
                with self.lock:
                    self.rejected.add(path)
                continue
            with self.lock:
                self.active.add(path)
            self.post('add', dev)

    def run(self):
        self.scan()
        while True:
            try:
                kind, path, obj = self.jobs.get(timeout=RESCAN_INTERVAL)
            except queue.Empty:
                self.scan()
                continue
            if kind == 'close':
                with self.lock:
                    if path is not None:
                        self.active.discard(path)
                try:
                    obj.close()
                except Exception:
                    pass
            elif kind == 'hyprctl':
                hyprctl(*obj)


def main():
    sel = selectors.DefaultSelector()
    watched = {}

    inbox = queue.Queue()
    notify_r, notify_w = socket.socketpair()
    notify_r.setblocking(False)
    sel.register(notify_r, selectors.EVENT_READ)

    def post(kind, obj):
        inbox.put((kind, obj))
        try:
            notify_w.send(b'x')
        except OSError:
            pass

    worker = Worker(post)

    held = set()
    armed = False    # Alt+Shift зажаты прямо сейчас
    tainted = False  # во время удержания нажали ещё клавишу → это хоткей

    def reset_state():
        held.clear()
        nonlocal armed, tainted
        armed = tainted = False

    def eject(path, why):
        dev = watched.pop(path, None)
        if dev is not None:
            try:
                sel.unregister(dev)
            except Exception:
                pass
            worker.submit('close', path, dev)
        # Состояние удержания могло остаться от исчезнувшего устройства
        # (выдернули клавиатуру с зажатым Alt → held навсегда с ALT →
        # следующий же Shift даёт ложное переключение раскладки).
        reset_state()
        print(f'{why}: {path}', flush=True)

    def drain_inbox():
        try:
            while True:
                notify_r.recv(4096)
        except BlockingIOError:
            pass
        while True:
            try:
                kind, obj = inbox.get_nowait()
            except queue.Empty:
                return
            if kind == 'add':
                path = obj.path
                if path in watched:
                    eject(path, 'заменена')
                try:
                    sel.register(obj, selectors.EVENT_READ)
                except Exception:
                    worker.submit('close', path, obj)
                    continue
                watched[path] = obj
                print(f'слушаю: {path:18s} {obj.name}', flush=True)
            elif kind == 'del':
                if obj in watched:
                    eject(obj, 'отключилась')

    worker.start()

    while True:
        for key, _ in sel.select():
            fobj = key.fileobj
            if fobj is notify_r:
                drain_inbox()
                continue
            dev = fobj
            try:
                events = list(dev.read())
            except OSError:
                # Устройство исчезло. Мёртвый fd нельзя оставлять в селекторе:
                # он навсегда «готов к чтению», и цикл крутился бы вхолостую,
                # съедая ядро CPU.
                eject(dev.path, 'ошибка чтения')
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
                        worker.submit('hyprctl',
                                      obj=('switchxkblayout', 'all', 'next'))
                        print('Alt+Shift → переключил', flush=True)


if __name__ == '__main__':
    main()
