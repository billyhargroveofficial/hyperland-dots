# Уведомления — swaync

SwayNC использует тот же `SF Pro Display` 14/600 и тот же выбранный акцент, что
Waybar и Rofi. `scripts/accent.sh` атомарно обновляет
`~/.config/swaync/accent.css` и просит SwayNC перечитать CSS. Светлая и тёмная
темы отличаются поверхностью карточек, но оттенок текста и элементов берут из
общего переключателя purple/blue/teal/amber.

## swaync не следует за системной темой

waybar с 0.15 сам слушает `xdg-desktop-portal` и берёт `style-<appearance>.css`.
**swaync так не умеет** — он читает ровно `~/.config/swaync/style.css` и ничего
не выбирает.

Поэтому здесь две темы держатся файлами `style-dark.css` / `style-light.css`, а
`style.css` — симлинк на активную. Переключает его `toggle-theme.sh` (секция 3b)
и сразу просит перечитать CSS:

```bash
ln -sf "$SWAYNC_DIR/style-${MODE}.css" "$SWAYNC_DIR/style.css"
swaync-client --reload-css
```

**Без `--reload-css` смена симлинка не даёт ничего** до перезапуска демона.

Симлинк создаёт и `restore-config.sh` при установке — иначе на свежей системе
уведомления останутся без стиля вообще.

## Структура CSS

`style-light.css` и `style-dark.css` только импортируют динамический акцент,
свою поверхность `theme-{light,dark}.css` и общий `style-common.css`. Поэтому
структурные правила карточек меняются в одном месте, а темы не расходятся.

Кнопки действий скрывает штатный `notification-action-filter` с regex `.*`;
2FA-action и inline replies также выключены. Поэтому Telegram `Mark as read`
и аналогичные полосы не меняют геометрию чистой карточки.

## Иерархия классов

В swaync 0.12 карточка лежит глубже, чем кажется:

```
.notification-row
  .notification-background
    .notification
      .notification-default-action
        .notification-content > .summary / .body / .time
      .notification-action
    .close-button
```

Стилизовать `.notification` без родителей работает не всегда — надёжнее писать
полный путь, как в `/etc/xdg/swaync/style.css`. Актуальный список селекторов
всегда там же.

Проверить стиль, не дожидаясь реального уведомления:

```bash
notify-send -a "Test" "Заголовок" "Текст"
swaync-client -t          # открыть/закрыть центр уведомлений
```
