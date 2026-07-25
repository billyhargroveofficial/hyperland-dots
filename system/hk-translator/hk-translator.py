#!/usr/bin/env python3
"""
hk-translator — транслятор хоткеев для Hyprland + нелатинские раскладки

Перехватывает клавиатуры на уровне evdev (ядро Linux) и создаёт
два виртуальных устройства через uinput:

  hk-translator-main  — обычный ввод, раскладка пользователя (us,ru)
  hk-translator-latin — хоткеи с модификаторами, всегда US

Модификаторы идут ТОЛЬКО на main (чтобы переключение раскладки работало).
На latin модификаторы синхронизируются лениво — только когда реально
нужно отправить хоткей (Ctrl+буква и т.д.).

Архитектура: два потока.

  Горячий поток (main) ТОЛЬКО читает события захваченных клавиатур и пишет
  их в uinput. Он никогда не открывает, не закрывает и не сканирует
  устройства: open()/close() узла ввода — это реальные USB-транзакции
  (первый открывший будит устройство, последний закрывший его глушит),
  которые блокируются в неприрываемом сне на десятки-сотни мс. Прежняя
  версия делала полный рескан всех /dev/input/event* каждые 5 секунд прямо
  в цикле пересылки — клавиатура замирала на ~полсекунды каждые 5 секунд,
  а при чихе USB — на секунды.

  Рабочий поток (DeviceWorker) делает всё блокирующееся: сканирует,
  открывает, проверяет, захватывает и закрывает устройства. Готовые
  (уже захваченные) устройства он передаёт горячему потоку через очередь,
  мёртвые получает обратно на закрытие. Каждый путь /dev/input/eventX
  открывается для проверки один раз за время его жизни — вердикт
  кэшируется, в устоявшемся состоянии сканы не трогают устройства вообще.
"""

import argparse
import queue
import selectors
import signal
import socket
import sys
import threading

import evdev
from evdev import UInput, ecodes

# ── Классификация клавиш ──────────────────────────────────────────

# Модификаторы-триггеры: при их удержании буквы уходят через Latin
TRIGGER_MODS = {
    ecodes.KEY_LEFTCTRL, ecodes.KEY_RIGHTCTRL,
    ecodes.KEY_LEFTALT, ecodes.KEY_RIGHTALT,
    ecodes.KEY_LEFTMETA, ecodes.KEY_RIGHTMETA,
}

# Все модификаторы
ALL_MODS = TRIGGER_MODS | {ecodes.KEY_LEFTSHIFT, ecodes.KEY_RIGHTSHIFT}

# Клавиши, зависимые от раскладки — именно их перенаправляем
LAYOUT_KEYS = set()

for _n in [
    'Q','W','E','R','T','Y','U','I','O','P',
    'A','S','D','F','G','H','J','K','L',
    'Z','X','C','V','B','N','M',
    '1','2','3','4','5','6','7','8','9','0',
    'MINUS','EQUAL','LEFTBRACE','RIGHTBRACE',
    'SEMICOLON','APOSTROPHE','GRAVE','BACKSLASH',
    'COMMA','DOT','SLASH',
]:
    LAYOUT_KEYS.add(getattr(ecodes, f'KEY_{_n}'))


# ── Поиск клавиатур ───────────────────────────────────────────────

SELF_MARK = 'hk-translator'   # имя собственных виртуальных устройств
RESCAN_INTERVAL = 5.0         # секунд — подхват горячего подключения

# Обязательный набор для «настоящей» клавиатуры
NEED_KEYS = {ecodes.KEY_A, ecodes.KEY_Z, ecodes.KEY_LEFTCTRL,
             ecodes.KEY_LEFTSHIFT, ecodes.KEY_LEFTALT, ecodes.KEY_SPACE}

# Диапазон BTN_MISC..BTN_GEAR_UP — кнопки мышей/джойстиков.
# На виртуальной клавиатуре их быть не должно: одна такая кнопка,
# и libinput classифицирует устройство как указательное.
BTN_BLOCK = range(ecodes.BTN_MISC, ecodes.KEY_OK)   # 0x100..0x15f

# База для uinput: весь обычный клавиатурный диапазон KEY_ESC..KEY_MICMUTE.
# Объявляем его целиком, чтобы клавиатура, воткнутая ПОСЛЕ старта демона,
# не упёрлась в отсутствующий keycode на уже созданном виртуальном устройстве.
BASE_KEYS = set(range(ecodes.KEY_ESC, ecodes.KEY_MICMUTE + 1))


def reject_reason(dev):
    """None — устройство годится, иначе строка с причиной отказа.

    Проверка на мышь обязательна: HID-интерфейс Logitech G102
    (/dev/input/event7) объявляет 273 «клавиши» — больше любой настоящей
    клавиатуры. Старый отбор сортировал кандидатов по числу клавиш и брал
    первого, поэтому grab() годами садился на мышь, а не на клавиатуру.
    """
    if SELF_MARK in dev.name.lower():
        return 'своё виртуальное устройство'
    caps = dev.capabilities()
    if ecodes.EV_KEY not in caps:
        return 'нет EV_KEY'
    keys = set(caps[ecodes.EV_KEY])
    if ecodes.EV_REL in caps:
        return 'есть EV_REL — указательное устройство'
    if ecodes.BTN_LEFT in keys:
        return 'есть BTN_LEFT — указательное устройство'
    missing = NEED_KEYS - keys
    if missing:
        names = ','.join(sorted(ecodes.KEY[k] for k in missing))
        return f'нет обязательных клавиш: {names}'
    return None


def is_keyboard(dev):
    return reject_reason(dev) is None


def find_keyboards():
    """Открытые (НЕ захваченные) InputDevice всех настоящих клавиатур."""
    found = []
    for path in sorted(evdev.list_devices()):
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        if is_keyboard(dev):
            found.append(dev)
        else:
            dev.close()
    return found


def build_caps(devs):
    """Возможности виртуальных устройств: объединение реальных клавиатур
    плюс базовый клавиатурный диапазон. EV_REL/EV_ABS не копируем никогда."""
    keys = set(BASE_KEYS)
    leds = set()
    msc = {ecodes.MSC_SCAN}
    for d in devs:
        c = d.capabilities()
        keys |= {k for k in c.get(ecodes.EV_KEY, ()) if k not in BTN_BLOCK}
        leds |= set(c.get(ecodes.EV_LED, ()))
        msc |= set(c.get(ecodes.EV_MSC, ()))
    caps = {ecodes.EV_KEY: sorted(keys), ecodes.EV_MSC: sorted(msc)}
    if leds:
        caps[ecodes.EV_LED] = sorted(leds)
    return caps


# ── Рабочий поток: всё, что может заблокироваться ─────────────────

class DeviceWorker(threading.Thread):
    """Сканы, open/probe/grab новых устройств и close мёртвых.

    Горячему потоку устройства отдаются уже захваченными (через
    Translator.post). Обратно мёртвые fd приходят в self.jobs на закрытие.
    """

    def __init__(self, translator, only_paths=None):
        super().__init__(daemon=True, name='dev-worker')
        self.tr = translator
        self.only = set(only_paths) if only_paths else None
        self.jobs = queue.Queue()   # ('close', path|None, dev)
        self.lock = threading.Lock()
        self.active = set()         # пути, отданные горячему потоку
        self.rejected = set()       # пути с отрицательным вердиктом

    # вызывается из горячего потока
    def submit_close(self, path, dev):
        self.jobs.put(('close', path, dev))

    def _close(self, dev):
        for m in ('ungrab', 'close'):
            try:
                getattr(dev, m)()
            except Exception:
                pass

    def scan(self):
        try:
            paths = set(evdev.list_devices())
        except OSError:
            return
        if self.only is not None:
            paths &= self.only

        with self.lock:
            gone_active = self.active - paths
            self.active -= gone_active
            self.rejected &= paths
            fresh = sorted(paths - self.active - self.rejected)

        # исчезнувшие: горячий поток отпустит зажатые клавиши и вернёт
        # fd сюда на закрытие
        for path in gone_active:
            self.tr.post('del', path)

        for path in fresh:
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                # узел ещё/уже не открывается — попробуем в следующий скан
                continue
            if self.only is not None:
                # при явном -d фильтр не применяем, но своё виртуальное
                # устройство не захватываем никогда — иначе петля
                why = ('своё виртуальное устройство'
                       if SELF_MARK in dev.name.lower() else None)
            else:
                why = reject_reason(dev)
            if why is not None:
                try:
                    dev.close()
                except Exception:
                    pass
                with self.lock:
                    self.rejected.add(path)
                continue
            try:
                dev.grab()
            except OSError as e:
                print(f'не захватить {path} ({dev.name}): {e}',
                      file=sys.stderr, flush=True)
                try:
                    dev.close()
                except Exception:
                    pass
                continue
            with self.lock:
                self.active.add(path)
            self.tr.post('add', dev)

    def run(self):
        self.scan()
        while True:
            try:
                kind, path, dev = self.jobs.get(timeout=RESCAN_INTERVAL)
            except queue.Empty:
                self.scan()
                continue
            if kind == 'close':
                with self.lock:
                    if path is not None:
                        self.active.discard(path)
                self._close(dev)


# ── Транслятор ────────────────────────────────────────────────────

class Translator:
    def __init__(self, caps):
        self.sel = selectors.DefaultSelector()
        self.devs = {}            # path → захваченный InputDevice
        self.down = {}            # path → set(зажатых кодов) для чистки
        self.route = {}           # (path, code) → 'main' | 'latin'
        self.trigger_held = set()
        self.mods_held = set()
        self.mods_on_latin = set()
        self.closed = False
        self.worker = None        # назначается в run()

        # канал «рабочий поток → горячий»: сообщение в очереди,
        # байт в сокете будит select
        self.inbox = queue.Queue()
        self.notify_r, self.notify_w = socket.socketpair()
        self.notify_r.setblocking(False)
        self.sel.register(self.notify_r, selectors.EVENT_READ)

        self.ui_main = UInput(caps, name='hk-translator-main')
        self.ui_latin = UInput(caps, name='hk-translator-latin')
        print('виртуальные устройства созданы: '
              f'{self.ui_main.device.path} / {self.ui_latin.device.path}',
              flush=True)

    # ── связь с рабочим потоком ──

    def post(self, kind, obj):
        """Вызывается из DeviceWorker."""
        self.inbox.put((kind, obj))
        try:
            self.notify_w.send(b'x')
        except OSError:
            pass

    def _drain_inbox(self):
        try:
            while True:
                self.notify_r.recv(4096)
        except BlockingIOError:
            pass
        while True:
            try:
                kind, obj = self.inbox.get_nowait()
            except queue.Empty:
                return
            if kind == 'add':
                path = obj.path
                if path in self.devs:
                    # тот же путь пере-занят новым устройством:
                    # старый fd мёртв — отпустить зажатое и закрыть
                    self.eject(path, 'заменена')
                try:
                    self.sel.register(obj, selectors.EVENT_READ)
                except Exception as e:
                    print(f'не зарегистрировать {path}: {e}',
                          file=sys.stderr, flush=True)
                    self.worker.submit_close(path, obj)
                    continue
                self.devs[path] = obj
                self.down.setdefault(path, set())
                print(f'захвачена: {path:18s} {obj.name}', flush=True)
            elif kind == 'del':
                if obj in self.devs:
                    self.eject(obj, 'отключилась')

    # ── управление набором устройств ──

    def eject(self, path, why):
        """Убрать устройство из горячего пути. Ничего блокирующегося:
        отпустить его зажатые клавиши, снять с select и отдать fd
        рабочему потоку на закрытие."""
        dev = self.devs.pop(path, None)
        # отпустить всё, что осталось зажатым, иначе клавиша залипнет
        stuck = sorted(self.down.pop(path, set()),
                       key=lambda c: (c in ALL_MODS, c))
        for code in stuck:
            self.handle(path, ecodes.EV_KEY, code, 0)
        if dev is not None:
            try:
                self.sel.unregister(dev)
            except Exception:
                pass
            self.worker.submit_close(path, dev)
        print(f'{why}: {path}', flush=True)

    # ── обработка событий ──

    def handle(self, path, etype, code, val):
        if etype == ecodes.EV_SYN:
            return

        if etype != ecodes.EV_KEY:
            # MSC_SCAN и прочее — всегда на main
            self.ui_main.write(etype, code, val)
            self.ui_main.syn()
            return

        # физическое состояние устройства (нужно при отключении)
        if val == 1:
            self.down.setdefault(path, set()).add(code)
        elif val == 0:
            self.down.get(path, set()).discard(code)

        # ── Модификаторы ──
        if code in ALL_MODS:
            if val == 1:
                self.mods_held.add(code)
            elif val == 0:
                self.mods_held.discard(code)

            if code in TRIGGER_MODS:
                if val in (1, 2):
                    self.trigger_held.add(code)
                elif val == 0:
                    self.trigger_held.discard(code)

            # Отпускание: если был на latin — отпустить там ПЕРВЫМ
            if val == 0 and code in self.mods_on_latin:
                self.ui_latin.write(ecodes.EV_KEY, code, 0)
                self.ui_latin.syn()
                self.mods_on_latin.discard(code)

            # Всегда на main ПОСЛЕДНИМ (main = активная клавиатура)
            self.ui_main.write(ecodes.EV_KEY, code, val)
            self.ui_main.syn()
            return

        # ── Обычные клавиши: маршрутизация ──
        key = (path, code)
        if val == 1:                       # нажатие
            if self.trigger_held and code in LAYOUT_KEYS:
                route = 'latin'
                # Ленивая синхронизация модификаторов на latin
                for mod in sorted(self.mods_held):
                    if mod not in self.mods_on_latin:
                        self.ui_latin.write(ecodes.EV_KEY, mod, 1)
                        self.ui_latin.syn()
                        self.mods_on_latin.add(mod)
            else:
                route = 'main'
            self.route[key] = route
        elif val == 0:                     # отпускание → туда же куда нажатие
            route = self.route.pop(key, 'main')
        else:                              # val == 2, повтор
            route = self.route.get(key, 'main')

        ui = self.ui_latin if route == 'latin' else self.ui_main
        ui.write(ecodes.EV_KEY, code, val)
        ui.syn()

    # ── главный цикл ──

    def loop(self):
        while True:
            for key, _ in self.sel.select():
                fobj = key.fileobj
                if fobj is self.notify_r:
                    self._drain_inbox()
                    continue
                path = fobj.path
                try:
                    events = list(fobj.read())
                except OSError as e:
                    self.eject(path, f'ошибка чтения ({e})')
                    continue
                for ev in events:
                    self.handle(path, ev.type, ev.code, ev.value)

    def close(self):
        if self.closed:
            return
        self.closed = True
        # процесс завершается — здесь блокировки уже не страшны
        for path in list(self.devs):
            dev = self.devs.pop(path)
            try:
                self.sel.unregister(dev)
            except Exception:
                pass
            try:
                dev.ungrab()
            except Exception:
                pass
            try:
                dev.close()
            except Exception:
                pass
        for ui in (self.ui_main, self.ui_latin):
            try:
                ui.close()
            except Exception:
                pass


# ── Запуск ────────────────────────────────────────────────────────

def run(device_paths=None):
    probe = find_keyboards()
    if device_paths:
        for d in probe:
            d.close()
        probe = []
        for p in device_paths:
            try:
                probe.append(evdev.InputDevice(p))
            except OSError as e:
                print(f'{p}: {e}', file=sys.stderr, flush=True)

    if not probe and not device_paths:
        print('клавиатур не найдено — жду горячего подключения',
              file=sys.stderr, flush=True)

    caps = build_caps(probe)
    names = ', '.join(f'{d.path} ({d.name})' for d in probe) or '—'
    for d in probe:
        d.close()

    tr = Translator(caps)
    tr.worker = DeviceWorker(tr, device_paths)

    def on_signal(*_):
        raise SystemExit(0)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    try:
        tr.worker.start()
        print(f'кандидаты на старте: {names}', flush=True)
        print('перехват запущен', flush=True)
        tr.loop()
    finally:
        tr.close()


def main():
    p = argparse.ArgumentParser(description='Транслятор хоткеев для Hyprland')
    p.add_argument('-d', '--device', action='append',
                   help='Путь к устройству (/dev/input/eventX), можно несколько')
    p.add_argument('-l', '--list', action='store_true',
                   help='Показать отбор устройств и выйти (ничего не захватывает)')
    args = p.parse_args()

    if args.list:
        print(f'{"УСТРОЙСТВО":20s} {"КЛАВИШ":>7s}  ВЕРДИКТ')
        for path in sorted(evdev.list_devices(),
                           key=lambda p: int(p.rsplit('event', 1)[1])):
            try:
                dev = evdev.InputDevice(path)
            except OSError as e:
                print(f'{path:20s} {"":>7s}  ошибка: {e}')
                continue
            n = len(dev.capabilities().get(ecodes.EV_KEY, ()))
            why = reject_reason(dev)
            verdict = 'ЗАХВАТИТЬ' if why is None else f'пропуск — {why}'
            print(f'{path:20s} {n:7d}  {verdict}   [{dev.name}]')
            dev.close()
    else:
        run(args.device)


if __name__ == '__main__':
    main()
