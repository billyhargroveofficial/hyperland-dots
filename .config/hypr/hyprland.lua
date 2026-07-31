-- Hyprland config, перенесён с hyprland.conf на Lua (формат с 0.55).
--
-- Старый hyprland.conf остаётся рядом НЕТРОНУТЫМ и служит откатом: Hyprland
-- берёт .lua, только если файл существует, иначе грузит .conf. Значит откат —
-- это `mv hyprland.lua hyprland.lua.off && hyprctl reload`, без правок внутри.
--
-- Соответствие старого синтаксиса новому, чтобы не искать каждый раз:
--   exec-once          -> hl.on("hyprland.start", ...) + hl.exec_cmd
--   env = A, B         -> hl.env("A", "B")
--   general { }        -> hl.config({ general = { } })
--   bezier / animation -> hl.curve / hl.animation
--   windowrule         -> hl.window_rule({ match = { ... }, ... })
--   layerrule          -> hl.layer_rule({ match = { ... }, ... })
--   bind / binde/m/r/l -> hl.bind(keys, dsp, { repeating / mouse / release / locked })
--   $var               -> обычная переменная Lua

------------------------------------------------------------------- МОНИТОРЫ --

-- Два монитора, оба 2560x1440:
--
--   ┌───────────────┬───────────────┐
--   │     DP-3      │     DP-2      │
--   │     новый     │    старый     │
--   │   180.06 Гц   │    200 Гц     │
--   │  столы 11-20  │  столы 1-10   │
--   │      0x0      │    2560x0     │
--   └───────────────┴───────────────┘
--
-- Порты переехали, когда появился второй монитор: старый (серийник
-- 7041110026654 в EDID, тянет 200 Гц) теперь в DP-2, а в DP-3 сидит новый, у
-- которого потолок 180.06 Гц. Прежняя строка `DP-3, 2560x1440@200` целилась
-- уже в новый монитор и требовала от него режим, которого у него нет.
--
-- Отсюда highrr у обоих вместо явных частот: он берёт максимум из EDID (200 у
-- DP-2, 180.06 у DP-3) и переживает перетыкание кабелей между портами. И тем
-- более не preferred — preferred берёт из EDID предпочитаемый режим, а он у
-- большинства мониторов 60 Гц; именно из-за этого монитор когда-то висел на
-- 59.95.
hl.monitor({ output = "", mode = "highrr", position = "auto", scale = 1 })
hl.monitor({ output = "DP-3", mode = "highrr", position = "0x0", scale = 1 })
hl.monitor({ output = "DP-2", mode = "highrr", position = "2560x0", scale = 1 })

-- У каждого монитора свой десяток столов. База набора — это то, что бинды в
-- конце файла прибавляют к нажатой цифре, поэтому таблица одна и на правила, и
-- на бинды: курсор над DP-2 → Alt+1 это стол 1, курсор над DP-3 → Alt+1 это
-- стол 11.
local wsPerMonitor = 10
local wsBase = {
	["DP-2"] = 0, -- столы 1..10
	["DP-3"] = 10, -- столы 11..20
}

for name, base in pairs(wsBase) do
	for i = 1, wsPerMonitor do
		hl.workspace_rule({
			workspace = tostring(base + i),
			monitor = name,
			-- Первый стол набора — тот, который монитор показывает, когда
			-- появляется. Без default Hyprland выдаёт подключённому монитору
			-- первый свободный номер: DP-3 после перетыкания кабеля приезжал
			-- на пустой 11-й не потому, что так задумано, а по совпадению.
			default = (i == 1) or nil,
		})
	end
end

-------------------------------------------------------------------- ПРОГРАММЫ

local terminal = "ghostty"
local fileManager = "nautilus"
local menu = "rofi -show drun -show-icons -icon-theme Papirus-Dark -theme ~/.config/rofi/launcher.rasi"
local browser = "google-chrome-stable --enable-features=UseOzonePlatform --ozone-platform=wayland --gtk-version=4"

---------------------------------------------------------------------- ОБОИ --

-- Берём последние выбранные обои из кэша (его пишут wall-next.sh /
-- wall-select.sh), иначе — дефолт. Раньше дефолт прибивался жёстко и затирал
-- выбор после каждой перезагрузки.
--
-- Команда одна и на автозапуск, и на появление монитора, потому что awww
-- раздаёт картинку только по тем выходам, которые СУЩЕСТВОВАЛИ в момент
-- вызова. Сессия стартовала с одним монитором, второй подключили позже — и он
-- оставался с дефолтной заливкой: `awww query` показывал на нём
-- «currently displaying: color: 000000», а на первом — картинку.
local function wallpaperCmd(output)
	local cmd = 'awww img "$(cat ~/.cache/current_wallpaper 2>/dev/null || echo ~/wallpapers/1.jpg)"'
	if output then
		cmd = cmd .. ' --outputs "' .. output .. '"'
	end
	return cmd .. " --transition-type none"
end

-- sleep нужен: о новом выходе awww узнаёт от компоситора не мгновенно, и
-- команда без задержки уходит в никуда — молча, без ошибки.
hl.on("monitor.added", function(mon)
	local ok, name = pcall(function()
		return mon.name
	end)
	hl.exec_cmd("sleep 1 && " .. wallpaperCmd(ok and name or nil))
end)

------------------------------------------------------------------- АВТОЗАПУСК

hl.on("hyprland.start", function()
	hl.exec_cmd("pgrep -x waybar >/dev/null || { test ! -x \"$HOME/.local/bin/waybar\" || exec \"$HOME/.local/bin/waybar\"; exec waybar; }")
	-- awww-daemon НЕ уходит в фон (ключа --daemonize у него нет), поэтому
	-- `awww-daemon && awww img ...` никогда не доходило до второй команды: &&
	-- ждёт завершения демона. Обои не ставились вообще — `awww query` показывал
	-- «currently displaying: color: 000000». Разнесено на две команды.
	hl.exec_cmd("awww-daemon")
	hl.exec_cmd("sleep 1 && " .. wallpaperCmd())
	hl.exec_cmd("~/.config/hypr/scripts/gpu-fan-control.sh")
	hl.exec_cmd("sleep 2 && sudo sing-box run -c ~/.config/sing-box/config.json >> ~/.local/share/singbox.log 2>&1 &")
	hl.exec_cmd("pgrep -x swaync >/dev/null || exec swaync")
	hl.exec_cmd("nm-applet &")
	-- hl.exec_cmd("pavucontrol --tab=3 &")  -- убран: открывал микшер при каждом логине
	hl.exec_cmd("wl-paste --type text --watch cliphist store")
	hl.exec_cmd("wl-paste --type image --watch cliphist store")
	hl.exec_cmd("udiskie &")
	-- Док убран по просьбе пользователя — вылезал снизу и был не нужен.
	-- Вернуть: раскомментировать строку и layer-правила для nwg-dock ниже.
	-- hl.exec_cmd('sleep 3 && nwg-dock-hyprland -d -l overlay -p bottom -i 48 -nolauncher -o DP-3 -m -iw "1,2,3,4,5,6,7,8,9,10"')
	hl.exec_cmd("hyprctl setcursor mcmojave-cursors 20")
end)

-- hyprshell убран по просьбе: его оверлей вылезал на Alt+Tab и был не нужен.
-- Переключение окон теперь нативное, биндами ниже — без GUI и без лишнего
-- процесса в сессии.
--
-- Вернуть, если однажды понадобится галерея окон: поднять `hyprshell run` в
-- блоке выше, а перерегистрацию биндов — по событию перезагрузки конфига.
-- Свои бинды hyprshell вешает в рантайме через hyprctl, а reload сбрасывает
-- всё, что не описано в конфиге (замерено: 71 бинд -> 63, Alt+Tab пропадает).

--------------------------------------------------------------------- ОКРУЖЕНИЕ

-- hl.env("XCURSOR_THEME", "mcmojave-cursors")
-- hl.env("XCURSOR_SIZE", "28")

hl.env("GTK_USE_PORTAL", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("MALCONTENT_DISABLE", "1")

-- GTK_THEME убран — это была причина, по которой светлая тема не включалась.
-- GTK_THEME это жёсткий оверрайд уровня CSS-провайдера, приоритетнее всего
-- остального: любое GTK3-приложение наследовало его из сессии и оставалось
-- тёмным при любом положении gsettings. Замер: с GTK_THEME фон #353535 (тёмный)
-- при color-scheme=prefer-light, без него — #f6f5f4 (светлый), как и должно.
-- Тему теперь переключает toggle-theme.sh через gsettings + портал.
-- hl.env("GTK_THEME", "Adwaita:dark")

-- QT_STYLE_OVERRIDE убран — пакета kvantum в системе нет, каталога
-- /usr/lib/qt6/plugins/styles/ тоже, Qt молча падал на встроенный Fusion.
-- hl.env("QT_STYLE_OVERRIDE", "kvantum")

-- Иконки и Qt-портал оставлены — они корректны, libqxdgdesktopportal.so на месте.
hl.env("GTK_ICON_THEME", "Papirus-Dark")
hl.env("QT_QPA_PLATFORMTHEME", "xdgdesktopportal")

------------------------------------------------------------------- ВНЕШНИЙ ВИД

hl.config({
	general = {
		gaps_in = 5,
		-- В hyprlang это было `gaps_out = 5, 10, 10, 10` — порядок как в CSS:
		-- сверху, справа, снизу, слева. Lua требует либо число, либо таблицу
		-- с именованными полями; строка со списком не принимается.
		gaps_out = { top = 5, right = 10, bottom = 10, left = 10 },

		col = {
			active_border = "rgba(cba6f7ff)",
			inactive_border = "rgba(28282800)",
		},

		border_size = 1,
		resize_on_border = true,
		allow_tearing = false,

		-- dwindle — обычный тайлинг: окна делят экран между собой и все на нём
		-- помещаются.
		--
		-- Раскладка scrolling («лента»: окна не режут экран всё мельче, а
		-- уезжают за его край, и монитор ездит по ленте как камера) убрана по
		-- просьбе пользователя вместе с прокруткой колесом. Настройки ленты
		-- остались в секции scrolling ниже — они просто не применяются, пока
		-- здесь не scrolling, и ничего не стоят.
		-- Вернуть ленту: layout = "scrolling".
		layout = "dwindle",
	},

	decoration = {
		rounding = 15,
		rounding_power = 2,
		active_opacity = 1,
		inactive_opacity = 1,
		fullscreen_opacity = 0.95,
		dim_inactive = false,
		dim_strength = 0,

		shadow = {
			enabled = false,
			range = 4,
			render_power = 3,
			color = "rgba(1a1a1aee)",
		},

		blur = {
			enabled = true,
			size = 5,
			passes = 3,
			ignore_opacity = true,
			new_optimizations = true,
			noise = 0.04,
			vibrancy = 0,
			vibrancy_darkness = 0,
			popups = true,
			contrast = 0.5,
		},
	},

	animations = {
		enabled = true,
	},

	dwindle = {
		-- pseudotile — опцию убрали из Hyprland (в 0.56 её уже нет).
		-- Сам режим никуда не делся: диспетчер pseudo работает, бинд ниже.
		preserve_split = true,
	},

	master = {
		new_status = "master",
	},

	scrolling = {
		-- Ширина новой колонки — половина экрана. На 2560 это 1280, то есть два
		-- окна в поле зрения одновременно; смысл ленты как раз в том, чтобы окна
		-- держали читаемый размер, а не сжимались с каждым новым.
		column_width = 0.5,

		-- Набор ширин, по которым щёлкает `layoutmsg colresize +1` — треть,
		-- половина, две трети, весь экран.
		explicit_column_widths = "0.333, 0.5, 0.667, 1.0",

		-- Лента едет за фокусом сама. Без этого ALT+колесо переводило бы фокус
		-- на колонку за краем экрана, и она осталась бы невидимой.
		follow_focus = 1,

		-- Доля колонки, которая обязана остаться в кадре при прокрутке.
		follow_min_visible = 0.4,

		-- Фокус с последней колонки перескакивает на первую, а не упирается.
		wrap_focus = 1,

		-- Одна колонка на экране разворачивается во весь экран.
		fullscreen_on_one_column = 1,
	},

	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
	},

	cursor = {
		no_warps = true,
	},

	binds = {
		-- Дефолт — 300 мс: после срабатывания бинда на колесо Hyprland
		-- глушит следующие события ровно столько. При быстрой прокрутке
		-- проходил только первый тик, и чтобы уехать через две колонки,
		-- приходилось крутить с паузой. Ноль — обрабатывать каждый тик.
		scroll_event_delay = 0,
	},

	input = {
		kb_layout = "us,ru",
		kb_variant = "",
		kb_model = "",
		-- grp:alt_shift_toggle убран намеренно — переключение делает сервис
		-- kbd-layout-toggle. xkb меняет группу только у того устройства, на
		-- котором нажали, а здесь клавиатур восемь плюс две виртуальных от
		-- hk-translator, и они разъезжаются.
		kb_options = "",
		kb_rules = "",

		numlock_by_default = false,
		follow_mouse = 1,
		sensitivity = -0.7,
		accel_profile = "adaptive",

		-- 2, а не дефолтная 1: у G102 колесо шлёт hi-res события, и при 1
		-- Hyprland копит их до «полного щелчка» — бинды на mouse_up/mouse_down
		-- срабатывали примерно раз в несколько оборотов. 2 форсирует эмуляцию
		-- дискретного скролла, то есть одно событие на каждый физический тик.
		emulate_discrete_scroll = 2,

		touchpad = {
			natural_scroll = false,
		},
	},
})

------------------------------------------------------------------- АНИМАЦИИ --

hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("almostLinear", { type = "bezier", points = { { 0.5, 0.5 }, { 0.75, 1.0 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })
hl.curve("myBezier", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.0 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.39, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.79, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.49, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.73, bezier = "almostLinear" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.46, bezier = "almostLinear" })
hl.animation({ leaf = "fade", enabled = true, speed = 3.03, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.81, bezier = "easeOutQuint" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4, bezier = "easeOutQuint", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.79, bezier = "almostLinear" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.39, bezier = "almostLinear" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "myBezier", style = "fade" })

------------------------------------------------------------------ УСТРОЙСТВА --

hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })

-- hk-translator: виртуальные клавиатуры для трансляции хоткеев
hl.device({ name = "hk-translator-main", kb_layout = "us,ru", kb_variant = "", kb_options = "" })
hl.device({ name = "hk-translator-latin", kb_layout = "us" })

---------------------------------------------------------------------- БИНДЫ --

-- Всё на Alt. Клавиатура была в Mac-режиме, где под большим пальцем лежит Cmd
-- (шлёт META); после выхода из него там Alt, и вся мышечная память — под него.
-- Переключалка ALT<->SUPER — toggle-mainmod.sh на F10, она правит эти две
-- строки. Формат строк менять нельзя, скрипт ищет их регулярным выражением.
local mainMod = "ALT"
local wsMod = "ALT"

hl.bind(mainMod .. " + W", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
-- Выход из сессии перевешен с Alt+M на Alt+CTRL+M. На mainMod = ALT одиночный
-- Alt+M — это мнемоника меню в любом GTK/Qt-приложении и рабочее сочетание в
-- части редакторов; случайное нажатие мгновенно убивало сессию без подтверждения.
hl.bind(mainMod .. " + CTRL + M", hl.dsp.exit())
hl.bind(mainMod .. " + CTRL + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/restart_hyprland.sh"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
-- hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + SHIFT + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + CTRL + T", hl.dsp.exec_cmd("missioncenter"))
-- obs в системе не установлен — бинд только съедал бы Alt+O глобально.
-- hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("obs"))
-- action = "toggle" обязателен. Без него диспетчер только УСТАНАВЛИВАЕТ
-- состояние, и повторное нажатие на уже развёрнутом окне ничего не делает —
-- выйти из фуллскрина становится нечем. В hyprlang `fullscreenstate 2 0`
-- переключал сам, в Lua это отдельный параметр.
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen_state({ internal = 2, client = 0, action = "toggle" }))
hl.bind(mainMod .. " + D", hl.dsp.window.pseudo())
-- Alt+S — закрепить окно поверх всех воркспейсов.
--
-- Голый pin применим ТОЛЬКО к плавающим окнам: на тайловом Hyprland отвечает
-- «Window does not qualify to be pinned» и не делает ничего — снаружи бинд
-- выглядит сломанным. Поэтому тайловое окно сначала переводим в floating, а
-- при откреплении возвращаем в тайлинг — но лишь то, которое сами оттуда и
-- вынимали: окно, бывшее плавающим изначально, так и останется плавающим.
--
-- Это возможно потому, что hl.bind принимает не только диспетчер, но и
-- обычную функцию Lua — в hyprlang такую логику пришлось бы выносить в скрипт
-- и дёргать hyprctl.
local pinnedFromTiled = {}

hl.bind(mainMod .. " + S", function()
	local w = hl.get_active_window()
	if not w then
		return
	end
	local id = tostring(w.address)

	if w.pinned then
		hl.dispatch(hl.dsp.window.pin())
		if pinnedFromTiled[id] then
			hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
			pinnedFromTiled[id] = nil
		end
	else
		if not w.floating then
			hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
			pinnedFromTiled[id] = true
		end
		hl.dispatch(hl.dsp.window.pin())
	end
end)

hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu))

-- cliphist прибит к SUPER, а не к mainMod: на mainMod = ALT он занимал Alt+V и
-- съедал его до терминала, а Alt+V нужен совместимым CLI-агентам: ghostty
-- шлёт по нему сырой ^V, по которому агент забирает из буфера
-- картинку. Явный SUPER переживает переключение mainMod по F10.
hl.bind("SUPER + V", hl.dsp.exec_cmd("cliphist list | rofi -dmenu | cliphist decode | wl-copy"))

-- Переключение раскладки по Alt+Shift делает сервис kbd-layout-toggle
-- (/opt/kbd-layout-toggle, читает evdev без перехвата и дёргает
-- `hyprctl switchxkblayout all next`). Бинда здесь нет намеренно: Hyprland не
-- срабатывает на бинды из одних модификаторов.

-- Alt+Tab — нативное переключение окон, без оверлея (раньше это делал
-- hyprshell, его галерея была не нужна). Два диспетчера на одно сочетание:
-- cycle_next только меняет фокус, а bring_to_top поднимает окно — без второго
-- в плавающем режиме фокус уходит под соседнее окно.
-- Модификатор прибит к ALT явно, а не к mainMod: Alt+Tab должен оставаться
-- Alt+Tab и после переключения mainMod на SUPER по F10.
hl.bind("ALT + Tab", hl.dsp.window.cycle_next())
hl.bind("ALT + Tab", hl.dsp.window.bring_to_top())
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.cycle_next({ next = false }))
hl.bind("ALT + SHIFT + Tab", hl.dsp.window.bring_to_top())

-- Фокус стрелками
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Фокус по vim-клавишам
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))

-- Перемещение окон по vim-клавишам
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.move({ direction = "right" }))

-- Размер окон по vim-клавишам
hl.bind(mainMod .. " + CTRL + h", hl.dsp.window.resize({ x = -20, y = 0 }))
hl.bind(mainMod .. " + CTRL + j", hl.dsp.window.resize({ x = 0, y = 20 }))
hl.bind(mainMod .. " + CTRL + k", hl.dsp.window.resize({ x = 0, y = -20 }))
hl.bind(mainMod .. " + CTRL + l", hl.dsp.window.resize({ x = 20, y = 0 }))

hl.bind(mainMod .. " + i", hl.dsp.exec_cmd("~/.config/hypr/scripts/socks-toggle.sh"))
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/singbox-toggle.sh"))
hl.bind("CTRL + Y", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-theme.sh"))

-- Переключалка главного модификатора (ALT <-> SUPER)
hl.bind("F10", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggle-mainmod.sh"))

-- Яркость монитора по DDC/CI. repeating — автоповтор при удержании; скрипт
-- копит цель и пишет в монитор один раз, так что удержание безопасно.
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh up"), { repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh down"), { repeating = true })
hl.bind(
	mainMod .. " + XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh up"),
	{ repeating = true }
)
hl.bind(
	mainMod .. " + XF86AudioLowerVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness.sh down"),
	{ repeating = true }
)

-- Голосовой ввод удалён по просьбе пользователя. Он висел на голом F11 и
-- глобально съедал фуллскрин в браузерах и видеоплеерах. Скрипт voice-input.sh
-- и его venv остались на диске — вернуть можно так:
-- hl.bind("F11", hl.dsp.exec_cmd("~/.config/hypr/scripts/voice-input.sh start"))
-- hl.bind("F11", hl.dsp.exec_cmd("~/.config/hypr/scripts/voice-input.sh stop"), { release = true })

-- Обои
hl.bind("CTRL + ALT + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/wall-next.sh"))
hl.bind("CTRL + SHIFT + ALT + A", hl.dsp.exec_cmd("~/.config/hypr/scripts/wall-select.sh"))

-- Скриншоты
hl.bind("Print", hl.dsp.exec_cmd("hyprshot -m region -c -o ~/Pictures/Screenshots"))
hl.bind(mainMod .. " + CTRL + S", hl.dsp.exec_cmd("hyprshot -m region -c -o ~/Pictures/Screenshots"))

-- Воркспейсы. Набор выбирается по монитору ПОД КУРСОРОМ, а не по тому, где
-- сейчас клавиатурный фокус: при follow_mouse = 1 они почти всегда совпадают,
-- но курсор — это то, на что человек смотрит, и после Alt+Tab, всплывшего
-- уведомления или окна, открывшегося на соседнем экране, цифры продолжают
-- работать по взгляду, а не по невидимому фокусу.
--
-- Функции глобальные, а не local, намеренно: те же самые дёргает waybar через
-- `hyprctl dispatch` при прокрутке колесом над баром. Lua-состояние у конфига
-- и у dispatch одно, поэтому таблица наборов не дублируется ещё и в JSON
-- waybar — а дублировалась бы, будь она заперта в локальной области.

-- База набора столов для монитора под курсором. Второе возвращаемое значение —
-- сам монитор, чтобы вызывающему не дёргать API повторно. Монитор, которого нет
-- в wsBase (третий экран, для которого правил не написано), получает набор
-- 1..10 — это лучше, чем не сработавший бинд.
function hyprWsBaseAtCursor()
	local m = hl.get_monitor_at_cursor()
	return (m and wsBase[m.name]) or 0, m
end

function hyprWsFocus(i)
	hl.dispatch(hl.dsp.focus({ workspace = tostring(hyprWsBaseAtCursor() + i) }))
end

-- Переносит окно на стол того монитора, над которым курсор. За счёт этого он же
-- работает как «перекинь окно на соседний экран»: увёл курсор на DP-3, нажал
-- Alt+Ctrl+1 — окно уехало на стол 11, то есть на DP-3.
function hyprWsMoveWindow(i)
	hl.dispatch(hl.dsp.window.move({ workspace = tostring(hyprWsBaseAtCursor() + i) }))
end

-- Колесо крутит столы того монитора, над которым курсор, и не выходит за
-- пределы его десятка — с последнего перескакивает на первый. Прежний `e+1`
-- так не умеет: он просто увеличивает номер, и на одиннадцатом щелчке уехал бы
-- в набор соседнего экрана, утащив за собой фокус.
function hyprWsCycle(step)
	local base, m = hyprWsBaseAtCursor()
	if not m then
		return
	end
	local cur = m.active_workspace
	local idx = cur and (cur.id - base) or 1
	-- Стол не из набора этого монитора: так бывает, пока второй экран
	-- отключён и его столы 11..20 временно переехали сюда. Считаем от первого.
	if idx < 1 or idx > wsPerMonitor then
		idx = 1
	end
	idx = (idx - 1 + step) % wsPerMonitor + 1
	hl.dispatch(hl.dsp.focus({ workspace = tostring(base + idx) }))
end

for i = 1, wsPerMonitor do
	local key = i % 10 -- 10 висит на клавише 0
	hl.bind(wsMod .. " + " .. key, function()
		hyprWsFocus(i)
	end)
	hl.bind(wsMod .. " + CTRL + " .. key, function()
		hyprWsMoveWindow(i)
	end)
end

-- Колесо: вниз — следующий стол, вверх — предыдущий, как было до scrolling.
hl.bind(wsMod .. " + mouse_down", function()
	hyprWsCycle(1)
end)
hl.bind(wsMod .. " + mouse_up", function()
	hyprWsCycle(-1)
end)

-- Горизонтальная прокрутка ленты колесом удалена по просьбе пользователя. Она
-- висела на ALT+колесе, при возврате воркспейсов на колесо переехала было на
-- ALT+CTRL — и убрана совсем. Колесо теперь занято только воркспейсами.
--
-- Сама scrolling-раскладка на месте: колонки ходят по Alt+H/L, лента едет за
-- фокусом сама (scrolling.follow_focus). Убрать и раскладку — general.layout.
--
-- Вернуть прокрутку колесом:
--   hl.bind(mainMod .. " + CTRL + mouse_down", hl.dsp.focus({ direction = "left" }))
--   hl.bind(mainMod .. " + CTRL + mouse_up",   hl.dsp.focus({ direction = "right" }))
--
-- Именно movefocus, а НЕ layoutmsg: `hl.dsp.layout("focus", "next")` в 0.56
-- соседнюю колонку не находит и на каждый вызов отвечает «no window to focus» —
-- при четырёх колонках подряд и фокусе посередине тоже. Снаружи это выглядело
-- как полностью мёртвый бинд, хотя сам он срабатывал (проверено счётчиком на
-- exec_cmd: 28 прокруток вниз, 38 вверх дошли).

-- Таскать и растягивать окна мышью с зажатым модификатором
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

------------------------------------------------------------ ПРАВИЛА ОКОН ----

-- opacity принимает строку ровно в том же виде, что и старый windowrule:
-- «активная [override] неактивная [override]». Таблица с полями active /
-- inactive не проходит — проверено --verify-config.
hl.window_rule({
	name = "global-opacity",
	match = { class = ".*" },
	opacity = "0.95 override 0.95 override",
})

hl.window_rule({
	name = "vscode-opacity",
	match = { class = "code" },
	opacity = "0.85 override 0.85 override",
})

----------------------------------------------------------- ПРАВИЛА СЛОЁВ ----

hl.layer_rule({ name = "rofi-xray", match = { namespace = "rofi" }, xray = true })
hl.layer_rule({ name = "rofi-alpha", match = { namespace = "rofi" }, ignore_alpha = 0.5 })
hl.layer_rule({ name = "eww-xray", match = { namespace = "eww" }, xray = true })

-- nwg-dock: blur + slide (док отключён, правила без него не работают)
-- hl.layer_rule({ name = "dock-blur",  match = { namespace = "nwg-dock" }, blur = true })
-- hl.layer_rule({ name = "dock-alpha", match = { namespace = "nwg-dock" }, ignore_alpha = 0.3 })
-- hl.layer_rule({ name = "dock-anim",  match = { namespace = "nwg-dock" }, animation = "slide bottom" })
