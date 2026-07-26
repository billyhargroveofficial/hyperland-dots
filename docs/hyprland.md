# Hyprland

## Конфиг переведён на Lua

`hyprland.lua` — основной конфиг, `hyprland.conf` остаётся рядом нетронутым.
Hyprlang объявлен устаревшим в 0.55: авторы обещают поддерживать его «1–2
релиза начиная с 0.55» и новых возможностей в него уже не добавляют.

**Формат выбирается один раз при СТАРТЕ Hyprland, а не при `hyprctl reload`.**
В логе это одна строка, одиннадцатая сверху:

```
[cfg] Lua config not found, using legacy config at /home/billy/.config/hypr/hyprland.conf
```

Практический вывод: создал `.lua` — он не подхватится до перезахода в сессию,
и всё это время правки надо вносить в `.conf`. Легко потерять час, редактируя
файл, который никто не читает.

**Проверять конфиг перед перезаходом обязательно:**

```bash
Hyprland --verify-config -c ~/.config/hypr/hyprland.lua
```

Это не поверхностный линт: команда реально исполняет Lua, поэтому ловит и
опечатки в именах `hl.dsp.*` (обращение к несуществующей функции — сразу
ошибка), и неверные типы значений. На миграции она поймала три штуки:

| Ошибка | Правильно |
|---|---|
| `gaps_out = "5, 10, 10, 10"` | `gaps_out = { top = 5, right = 10, bottom = 10, left = 10 }` |
| `opacity = { active = 0.95, inactive = 0.95 }` | `opacity = "0.95 override 0.95 override"` |

`hyprland.conf` удалён — отката не планируется, а лежащий рядом мёртвый конфиг
только путает: он не читается, но выглядит рабочим. Если однажды понадобится,
он в истории git:

```bash
git show a7315ed:.config/hypr/hyprland.conf > ~/.config/hypr/hyprland.conf
```

## Что миграция сломала молча

Две вещи отвалились так, что скрипты продолжали «работать»: команда печатает
ошибку в stdout и возвращает НОЛЬ, поэтому `set -e` её не ловит.

**`hyprctl keyword` не работает при Lua вообще** — отвечает `keyword can't work
with non-legacy parsers. Use eval.` На нём держался `toggle-theme.sh`: Ctrl+Y
переключал бы GTK, waybar, swaync и nvim, но не цвет рамок Hyprland. Замена:

```bash
hyprctl eval 'hl.config({ general = { col = { active_border = "rgba(ffffffcc)" } } })'
```

**`hyprctl dispatch` со старым синтаксисом тоже мёртв** — аргумент
подставляется прямо в `hl.dispatch(...)` и парсится как Lua-код, так что
`workspace e+1` даёт `')' expected near 'e'`. Это ломало прокрутку воркспейсов
в панели и `hyprctl dispatch exit` в power menu. Замена:

```bash
hyprctl dispatch 'hl.dsp.focus({ workspace = "e+1" })'
hyprctl dispatch 'hl.dsp.exit()'
```

Продолжают работать без изменений: `hyprctl reload`, `setcursor`, `getoption`
и `switchxkblayout` — последнее важно, на нём висит переключение раскладки из
root-демона `kbd-layout-toggle`.

`toggle-mainmod.sh` (F10) правит теперь строку `local mainMod = "ALT"`.

Соответствие синтаксиса, чтобы не искать каждый раз:

| hyprlang | Lua |
|---|---|
| `exec-once = cmd` | `hl.on("hyprland.start", function() hl.exec_cmd("cmd") end)` |
| `env = A, B` | `hl.env("A", "B")` |
| `general { }` | `hl.config({ general = { } })` |
| `bezier` / `animation` | `hl.curve` / `hl.animation` |
| `windowrule` / `layerrule` | `hl.window_rule` / `hl.layer_rule` |
| `bind` / `binde` / `bindm` / `bindr` / `bindl` | `hl.bind(keys, dsp, { repeating / mouse / release / locked })` |
| `movefocus l` | `hl.dsp.focus({ direction = "left" })` |
| `workspace N` | `hl.dsp.focus({ workspace = "N" })` |
| `movetoworkspace N` | `hl.dsp.window.move({ workspace = "N" })` |
| `layoutmsg X` | `hl.dsp.layout("X")` |
| `$var` | обычная переменная Lua |

## Scrolling — раскладка лентой

Включена глобально (`general.layout = "scrolling"`), прокрутка на **ALT+колесо**
вместо прежнего переключения воркспейсов.

Встроена в Hyprland с 0.54, раньше была плагином `hyprscrolling`. Окна не режут
экран всё мельче, а уезжают за его край — монитор ездит по ленте как камера.

### Быстрая прокрутка глотала тики — два троттла подряд

Симптом: крутишь колесо привычно быстро, а фокус переезжает на одну колонку.
Чтобы уехать через две, надо крутить с паузой. Виноваты две независимые
настройки, и лечить надо обе:

| Опция | Дефолт | Что делает |
|---|---|---|
| `binds.scroll_event_delay` | `300` | после срабатывания бинда на колесо глушит следующие события ровно столько миллисекунд |
| `input.emulate_discrete_scroll` | `1` | копит hi-res события мыши до «полного щелчка»; у G102 колесо как раз hi-res |

Стоят `0` и `2` соответственно — тогда обрабатывается каждый физический тик.

### Прокрутку двигает movefocus, а не layoutmsg

`hl.dsp.layout("focus", "next")` в 0.56 соседнюю колонку **не находит**: на
каждый вызов отвечает `no window to focus`, даже когда колонок четыре и фокус
посередине. Снаружи это выглядит как полностью мёртвый бинд.

Проверять надо не бинд, а диспетчер: бинд легко проверяется счётчиком —

```bash
hyprctl eval 'hl.bind("ALT + mouse_down", hl.dsp.exec_cmd("echo tick >> /tmp/t"))'
```

— и в моём случае показал, что события доходят все до единого.

Рабочий вариант — обычный `hl.dsp.focus({ direction = "left"|"right" })`: по тем
же колонкам он ходит безошибочно, а лента едет за фокусом сама.

Команды, которые layout реально принимает (проверено перебором через
`hyprctl dispatch layoutmsg`, остальные отвечают «no such layoutmsg for
scrolling»):

```
focus <prev|next>     colresize <±N>    fit      promote
move <offset>         swapcol           center
```

`focus next/prev` двигает фокус по колонкам, а лента едет следом сама — за это
отвечает `scrolling.follow_focus`. Поставишь ноль — фокус уедет за край экрана
и колонка останется невидимой.

Вернуть прежнее поведение: `layout = "dwindle"` плюс раскомментировать в конфиге
два бинда колеса на переключение воркспейсов.

## Alt+Tab — нативный, hyprshell убран

Раньше переключением окон занимался `hyprshell`: он вешал свои бинды в рантайме
и показывал оверлей-галерею окон. Оверлей был не нужен, поэтому пакет убран из
автозапуска, из `restart_hyprland.sh`, из `toggle-mainmod.sh` и из списка AUR в
`restore-config.sh`.

Сейчас в `hyprland.conf`:

```
bind = ALT, Tab, cyclenext
bind = ALT, Tab, bringactivetotop
bind = ALT SHIFT, Tab, cyclenext, prev
bind = ALT SHIFT, Tab, bringactivetotop
```

Два диспетчера на один бинд не избыточность: `cyclenext` только переносит
фокус, а `bringactivetotop` поднимает окно — без него в плавающем режиме
сфокусированное окно остаётся под соседним.

Модификатор прибит к `ALT` явно, а не к `$mainMod`: Alt+Tab должен оставаться
Alt+Tab и после переключения главного модификатора на SUPER по `F10`.

**Если будешь возвращать hyprshell** — учти то, из-за чего он однажды перестал
работать: свои бинды он регистрирует через `hyprctl` в рантайме, а
`hyprctl reload` сбрасывает всё, чего нет в конфиге (замерено: 71 бинд → 63,
Alt+Tab пропадает). Поэтому в конфиге нужны обе строки, и вторая именно с
`exec`, а не `exec-once` — `exec` выполняется на каждом reload:

```
exec-once = hyprshell run
exec = sleep 1 && hyprshell socat '"Restart"'
```

Нативные бинды этой болезни лишены: они описаны в конфиге, и reload их не
теряет.
