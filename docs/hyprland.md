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

Откат — без правок внутри файлов:

```bash
mv ~/.config/hypr/hyprland.lua ~/.config/hypr/hyprland.lua.off
# выйти и зайти в сессию — снова загрузится hyprland.conf
```

`toggle-mainmod.sh` (F10) научен работать с обоими форматами: он определяет
активный по Lua REPL (`hyprctl repl` отвечает только при lua-менеджере) и
правит именно тот файл, который Hyprland загрузил. Без этого F10 после
миграции молча правил бы неактивный конфиг.

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
