# system/ — то, что живёт вне `$HOME`

Здесь лежат демоны, systemd-юниты и udev-правила, которые ставятся в системные
каталоги. Они хранятся в репозитории, а не тянутся со стороны, по одной причине:
в апстриме их либо нет вовсе, либо там версия, которая на этой машине не работает.

Раскладка при установке:

| Здесь | Куда ставится |
|---|---|
| `hk-translator/hk-translator.py` | `/opt/hk-translator/` |
| `hk-translator/hk-translator.service` | `/etc/systemd/system/` |
| `kbd-layout-toggle/kbd-layout-toggle.py` | `/opt/kbd-layout-toggle/` |
| `kbd-layout-toggle/kbd-layout-toggle.service` | `/etc/systemd/system/` |
| `ddcci/ddcci-bind.sh` | `/usr/local/bin/` |
| `ddcci/ddcci-bind.service` | `/etc/systemd/system/` |
| `udev/99-ddcci-backlight.rules` | `/etc/udev/rules.d/` |
| `modules-load/ddcci.conf` | `/etc/modules-load.d/` |
| `searxng/settings.yml` | `/etc/searxng/settings.yml` |
| `searxng/searxng.service` | `/etc/systemd/system/` |

Всё это делает `restore-config.sh`, руками копировать не нужно.

## SearXNG — локальный поиск для AI

`system/searxng/install.sh` ставит pinned SearXNG в `/opt/searxng`, создаёт
отдельного системного пользователя и hardened unit. Backend слушает только
`127.0.0.1:8888`; к нему через `mcp-searxng` подключаются Qwen Code и Grok
Build. Секрет генерируется в `/etc/searxng/secret.env` и в Git не попадает.

```bash
sudo bash system/searxng/install.sh
systemctl status searxng
curl -fsS http://127.0.0.1:8888/healthz
```

## hk-translator — почему форк, а не клон апстрима

Транслятор хоткеев для нелатинских раскладок: перехватывает клавиатуру на уровне
evdev и переотправляет через два виртуальных устройства — `hk-translator-main`
(раскладка пользователя) и `hk-translator-latin` (всегда US, для хоткеев).

Раньше `restore-config.sh` клонировал его из `reflaxess123/hk-translator`. Этот
аккаунт больше не существует (отдаёт 301), а в самом коде был баг, из-за которого
транслятор **не работал никогда**:

```python
result.sort(key=lambda d: len(d.capabilities().get(ecodes.EV_KEY, [])), reverse=True)
kbd = kbds[0]
```

Отбор шёл по числу объявленных клавиш. HID-интерфейс мыши Logitech G102 объявляет
**273 «клавиши»** — больше любой настоящей клавиатуры, — поэтому `grab()`
доставался мыши. Проверено по `/proc/<pid>/fd`: держался `/dev/input/event7`
(мышь), тогда как клавиатуры были на `event3` и `event8`.

Второй слой той же проблемы: все `print()` шли без `flush=True`, а stdout в
journald — сокет, который Python буферизует поблочно. Демон честно писал в лог
«Клавиатура: Logitech G102 LIGHTSYNC Gaming Mouse Keyboard», но эта строка
попадала в журнал только при завершении процесса. Поэтому баг и жил годами.

Что исправлено в этой версии:

- отбор устройств по возможностям, а не по количеству клавиш: отсев по
  `EV_REL`/`BTN_LEFT` плюс обязательный набор `A, Z, LCTRL, LSHIFT, LALT, SPACE`;
- захват **всех** настоящих клавиатур, а не одной, с горячим подключением;
- capabilities виртуальных устройств больше не клонируются с исходного вслепую —
  иначе `EV_REL` мыши попадал в них и libinput не считал их клавиатурами;
- синтетический release зажатых клавиш при отключении устройства (анти-залипание);
- `flush=True` везде.

## kbd-layout-toggle — почему не `grp:alt_shift_toggle`

Переключение раскладки по Alt+Shift. Казалось бы, для этого есть штатная
xkb-опция, но на этой машине она работать не может: **в Hyprland раскладка живёт
отдельно у каждого устройства ввода**, а их здесь тринадцать, включая две
виртуальные клавиатуры от `hk-translator`. xkb переключает группу только у того
устройства, на котором нажали, а печать идёт через другое — устройства
разъезжаются. Наблюдалось напрямую: после одного переключения
`hyprctl devices` показывал одновременно `English (US)` и `Russian`.

Демон читает evdev **без `grab()`** — он физически не может отобрать или потерять
ввод, только слушает — и дёргает `hyprctl switchxkblayout all next`, который
переключает все устройства разом.

Срабатывание — на **отпускании** и только если Alt+Shift нажали вхолостую. Это
обязательно: `$mainMod = ALT`, и без такой проверки каждый `Alt+Shift+H`
(перенос окна) заодно менял бы язык.

Биндом Hyprland это сделать нельзя: на голые модификаторы бинды не срабатывают.

## ddcci — яркость внешнего монитора

У десктопа нет `/sys/class/backlight`: это интерфейс подсветки ноутбучных матриц.
Внешний монитор управляется по DDC/CI через i2c прямо по кабелю.

Можно дёргать `ddcutil` из скрипта, но это **~600 мс на вызов** — для модуля
waybar, который опрашивает устройство, неприемлемо. Драйвер `ddcci-backlight`
регистрирует монитор как обычный `/sys/class/backlight/ddcciN`: чтение
становится мгновенным, запись — 165 мс, и начинает работать нативный модуль
waybar `backlight/slider`.

Две особенности, из-за которых нужен `ddcci-bind.sh`:

1. **Стабильный AUR-пакет `ddcci-driver-linux-dkms` не собирается** на ядрах
   7.x — в ядре добавили `const` в сигнатуру `device_driver` и выпилили
   `I2C_CLASS_SPD`. Нужен форк `ddcci-driver-linux-clemax-dkms-git`.
2. **С ядра 6.8 в драйвере отключена авто-проба дисплеев** (в `dmesg`:
   `Auto-probing of displays is not available on kernel 6.8 and later`).
   Устройство надо создавать вручную через `new_device`, а номер i2c-шины между
   загрузками не фиксирован — поэтому скрипт перебирает шины и пробует
   привязать адрес `0x37`. Промахи безвредны: где никто не отвечает, драйвер не
   привяжется.

   Перебираются **только шины видеокарты** (их родитель — PCI-устройство из
   `/sys/class/drm/card*/device`). Слать `0x37` во все подряд нельзя: на
   SMBus-шинах чипсета живут SPD-EEPROM модулей памяти, и мусорные клиенты там
   остаются висеть — след старой версии скрипта до сих пор торчит как
   `/sys/bus/i2c/devices/4-0037`.

Грабли, на которые уже наступили (26.07.2026): в юните стояло
`After=graphical.target` при `WantedBy=multi-user.target`. Target неявно
получает `After=` на всё, что в него входит, — вышел цикл, и systemd на каждой
загрузке молча выбрасывал сервис:

```
multi-user.target: Found ordering cycle: ddcci-bind.service/start after graphical.target/start
multi-user.target: Job ddcci-bind.service/start deleted to break ordering cycle
```

Снаружи это выглядит как «сломалась яркость»: `/sys/class/backlight/` пуст,
скрипт панели отдаёт «нет ddcci-устройства». Ждать графику незачем — i2c-шины
поднимает модуль видеокарты, а скрипт сам крутит ретраи до 60 с. **Если яркость
не работает — первым делом `systemctl status ddcci-bind`, а не железо.**

Из той же серии: номер шины не фиксирован, поэтому хардкодить `ddcci3` в
скриптах нельзя — и `brightness.sh`, и функция `bright` берут первое реально
созданное `/sys/class/backlight/ddcci*`.

Права на `/sys/class/backlight/*/brightness` даёт udev-правило (группа `video`),
пользователь добавляется в эту группу. **Членство в группе подхватывается только
при следующем логине.**
