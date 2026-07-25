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

Захватываются ВСЕ настоящие клавиатуры (у пользователя их две), горячее
подключение подхватывается раз в RESCAN_INTERVAL секунд.
"""

import argparse
import selectors
import signal
import sys
import time

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


# ── Транслятор ────────────────────────────────────────────────────

class Translator:
    def __init__(self, caps, only_paths=None):
        self.only = set(only_paths) if only_paths else None
        self.sel = selectors.DefaultSelector()
        self.devs = {}            # path → захваченный InputDevice
        self.down = {}            # path → set(зажатых кодов) для чистки
        self.route = {}           # (path, code) → 'main' | 'latin'
        self.trigger_held = set()
        self.mods_held = set()
        self.mods_on_latin = set()
        self.closed = False

        self.ui_main = UInput(caps, name='hk-translator-main')
        self.ui_latin = UInput(caps, name='hk-translator-latin')
        print('виртуальные устройства созданы: '
              f'{self.ui_main.device.path} / {self.ui_latin.device.path}',
              flush=True)

    # ── управление набором устройств ──

    def _wanted(self):
        out = {}
        for path in sorted(evdev.list_devices()):
            if self.only is not None and path not in self.only:
                continue
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            # при явном -d фильтр не применяем, но своё виртуальное
            # устройство не захватываем никогда — иначе петля
            ok = (SELF_MARK not in dev.name.lower()
                  if self.only is not None else is_keyboard(dev))
            if ok:
                out[path] = dev
            else:
                dev.close()
        return out

    def sync(self):
        current = self._wanted()

        for path in list(self.devs):
            if path not in current:
                self.drop(path, 'отключилась')

        for path, dev in current.items():
            if path in self.devs:
                dev.close()
                continue
            try:
                dev.grab()
            except OSError as e:
                print(f'не захватить {path} ({dev.name}): {e}',
                      file=sys.stderr, flush=True)
                dev.close()
                continue
            try:
                self.sel.register(dev, selectors.EVENT_READ)
            except Exception as e:
                print(f'не зарегистрировать {path}: {e}',
                      file=sys.stderr, flush=True)
                try:
                    dev.ungrab()
                except Exception:
                    pass
                dev.close()
                continue
            self.devs[path] = dev
            self.down[path] = set()
            print(f'захвачена: {path:18s} {dev.name}', flush=True)

    def drop(self, path, why):
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
            try:
                dev.ungrab()
            except Exception:
                pass
            try:
                dev.close()
            except Exception:
                pass
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
        last_scan = time.monotonic()
        while True:
            for key, _ in self.sel.select(timeout=RESCAN_INTERVAL):
                dev = key.fileobj
                path = dev.path
                try:
                    events = list(dev.read())
                except OSError as e:
                    self.drop(path, f'ошибка чтения ({e})')
                    continue
                for ev in events:
                    self.handle(path, ev.type, ev.code, ev.value)

            now = time.monotonic()
            if now - last_scan >= RESCAN_INTERVAL:
                last_scan = now
                self.sync()

    def close(self):
        if self.closed:
            return
        self.closed = True
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

    tr = Translator(caps, device_paths)

    def on_signal(*_):
        raise SystemExit(0)

    signal.signal(signal.SIGINT, on_signal)
    signal.signal(signal.SIGTERM, on_signal)

    try:
        tr.sync()
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
