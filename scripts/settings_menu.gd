extends Control
## The settings screen, used by both the main menu and the pause menu.
## Changes apply straight away and are saved when you press Back.

signal closed

const UI := preload("res://scripts/ui.gd")
const SECTIONS := ["graphics", "audio", "controls"]

var _tabs: TabContainer
var _notice: Label
var _key_buttons: Array = []  # [Button, action, slot]
var _waiting: Array = []  # [Button, action, slot] while waiting for a key press


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := UI.centered_panel(self)
	column.add_child(UI.title("Settings", 34))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(760, 470)
	column.add_child(_tabs)
	_notice = UI.label("", 17)
	_notice.add_theme_color_override("font_color", UI.HIGHLIGHT_COLOR)
	_notice.custom_minimum_size.y = 24
	column.add_child(_notice)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Reset this tab", _reset_tab, 230))
	buttons.add_child(UI.button("Back", close, 230))
	column.add_child(buttons)
	_fill_tabs()


func open() -> void:
	visible = true
	_notice.text = ""
	_fill_tabs()


func close() -> void:
	_stop_waiting()
	Settings.save()
	visible = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if not _waiting.is_empty():
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
			if code != KEY_ESCAPE:
				var taken: String = Settings.set_binding(_waiting[1], _waiting[2], code)
				_notice.text = "%s was also used for \"%s\", so it was removed there." % [Settings.key_name(code), taken] if taken != "" else ""
			_stop_waiting()
		elif event is InputEventMouseButton and event.pressed:
			_stop_waiting()
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _reset_tab() -> void:
	Settings.reset_section(SECTIONS[_tabs.current_tab])
	_notice.text = "%s settings reset to defaults." % _tabs.get_tab_title(_tabs.current_tab)
	_fill_tabs()


func _fill_tabs() -> void:
	_stop_waiting()
	var current := maxi(_tabs.current_tab, 0)
	for child in _tabs.get_children():
		_tabs.remove_child(child)
		child.queue_free()
	_key_buttons.clear()

	var g := _page("Graphics")
	_add_check(g, "Fullscreen", "graphics", "fullscreen")
	_add_check(g, "VSync", "graphics", "vsync")
	_add_options(g, "Frame rate limit", "graphics", "max_fps",
			[["Unlimited", 0], ["30", 30], ["60", 60], ["120", 120], ["144", 144], ["240", 240]])
	_add_slider(g, "Render scale", "graphics", "render_scale", 0.5, 1.0, 0.05, func(v): return "%d%%" % roundi(v * 100))
	_add_options(g, "Anti-aliasing", "graphics", "msaa", [["Off", 0], ["2x", 2], ["4x", 4], ["8x", 8]])
	_add_options(g, "Shadows", "graphics", "shadows", [["Off", 0], ["Low", 1], ["High", 2]])
	_add_slider(g, "View distance", "graphics", "view_distance", 3, 8, 1, func(v): return "%d m" % roundi(v * 48))
	_add_slider(g, "Field of view", "graphics", "fov", 50, 100, 1, func(v): return "%d°" % roundi(v))

	var a := _page("Audio")
	var percent := func(v): return "%d%%" % roundi(v * 100)
	_add_slider(a, "Master volume", "audio", "master", 0, 1, 0.01, percent)
	_add_slider(a, "Music", "audio", "music", 0, 1, 0.01, percent)
	_add_slider(a, "Effects", "audio", "effects", 0, 1, 0.01, percent)
	_add_slider(a, "Ambience (wind)", "audio", "ambience", 0, 1, 0.01, percent)
	_add_hint(a, "There's no music yet; this slider is ready for when there is.")

	var c := _page("Controls")
	_add_slider(c, "Mouse sensitivity", "controls", "mouse_sensitivity", 0.2, 3.0, 0.05, func(v): return "%.2fx" % v)
	_add_check(c, "Invert mouse Y", "controls", "invert_y")
	_add_hint(c, "Click a key box, then press the new key. Esc cancels, right-click clears.")
	for entry in Settings.ACTIONS:
		var keys := HBoxContainer.new()
		for slot in Settings.SLOTS_PER_ACTION:
			keys.add_child(_key_button(entry[0], slot))
		_add_row(c, entry[1], keys)
	var pause_key := Button.new()
	pause_key.text = Settings.key_name(Settings.PAUSE_KEY)
	pause_key.disabled = true
	pause_key.custom_minimum_size = Vector2(150, 40)
	pause_key.tooltip_text = "Esc always opens the pause menu."
	_add_row(c, "Pause menu", pause_key)

	_tabs.current_tab = mini(current, _tabs.get_tab_count() - 1)


## A scrolling tab page; returns the 2-column grid that rows go into.
func _page(title: String) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 12)
	margin.add_child(grid)
	return grid


func _add_row(grid: GridContainer, text: String, control: Control) -> void:
	var l := UI.label(text)
	l.custom_minimum_size.x = 260
	grid.add_child(l)
	grid.add_child(control)


func _add_hint(grid: GridContainer, text: String) -> void:
	grid.add_child(Control.new())
	var l := UI.label(text, 16)
	l.modulate = UI.SOFT_TEXT_COLOR
	grid.add_child(l)


func _add_check(grid: GridContainer, text: String, section: String, key: String) -> void:
	var check := CheckButton.new()
	check.button_pressed = Settings.get_value(section, key)
	check.toggled.connect(func(on: bool) -> void:
		Settings.play_click()
		Settings.set_value(section, key, on)
	)
	var box := HBoxContainer.new()
	box.add_child(check)
	_add_row(grid, text, box)


func _add_options(grid: GridContainer, text: String, section: String, key: String, options: Array) -> void:
	var menu := OptionButton.new()
	menu.custom_minimum_size = Vector2(200, 40)
	for option in options:
		menu.add_item(option[0])
		if option[1] == Settings.get_value(section, key):
			menu.select(menu.item_count - 1)
	menu.item_selected.connect(func(index: int) -> void:
		Settings.play_click()
		Settings.set_value(section, key, options[index][1])
	)
	var box := HBoxContainer.new()
	box.add_child(menu)
	_add_row(grid, text, box)


func _add_slider(grid: GridContainer, text: String, section: String, key: String,
		min_value: float, max_value: float, step: float, format: Callable) -> void:
	var box := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = Settings.get_value(section, key)
	slider.custom_minimum_size = Vector2(280, 32)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var value_label := UI.label(format.call(slider.value))
	value_label.custom_minimum_size.x = 80
	var is_int: bool = Settings.DEFAULTS[section][key] is int
	slider.value_changed.connect(func(v: float) -> void:
		value_label.text = format.call(v)
		Settings.set_value(section, key, roundi(v) if is_int else v)
	)
	box.add_child(slider)
	box.add_child(value_label)
	_add_row(grid, text, box)


func _key_button(action: String, slot: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 40)
	b.pressed.connect(func() -> void:
		Settings.play_click()
		_stop_waiting()
		_waiting = [b, action, slot]
		b.text = "Press a key…"
	)
	b.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			Settings.set_binding(action, slot, 0)
			_refresh_keys()
	)
	_key_buttons.append([b, action, slot])
	b.text = Settings.key_name(Settings.get_binding(action, slot))
	return b


func _stop_waiting() -> void:
	_waiting = []
	_refresh_keys()


func _refresh_keys() -> void:
	for entry in _key_buttons:
		if is_instance_valid(entry[0]):
			entry[0].text = Settings.key_name(Settings.get_binding(entry[1], entry[2]))
