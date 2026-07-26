# Hyprland

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
