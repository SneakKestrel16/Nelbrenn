extends RefCounted
## The shared look of all menus, and small helpers for building them in code.

const PANEL_COLOR := Color(0.22, 0.18, 0.14, 0.97)
const BORDER_COLOR := Color(0.55, 0.45, 0.30)
const HIGHLIGHT_COLOR := Color(0.95, 0.85, 0.55)
const SOFT_TEXT_COLOR := Color(1, 1, 1, 0.65)


static func make_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 20
	theme.set_stylebox("normal", "Button", _box(Color(0.32, 0.25, 0.18), BORDER_COLOR))
	theme.set_stylebox("hover", "Button", _box(Color(0.42, 0.33, 0.22), HIGHLIGHT_COLOR))
	theme.set_stylebox("pressed", "Button", _box(Color(0.25, 0.19, 0.13), HIGHLIGHT_COLOR))
	theme.set_stylebox("hover_pressed", "Button", _box(Color(0.25, 0.19, 0.13), HIGHLIGHT_COLOR))
	theme.set_stylebox("disabled", "Button", _box(Color(0.25, 0.22, 0.20, 0.6), Color(0.4, 0.37, 0.33)))
	var focus := _box(Color.TRANSPARENT, HIGHLIGHT_COLOR)
	focus.draw_center = false
	theme.set_stylebox("focus", "Button", focus)
	theme.set_stylebox("normal", "LineEdit", _box(Color(0.12, 0.10, 0.08), BORDER_COLOR))
	theme.set_stylebox("focus", "LineEdit", focus)
	theme.set_stylebox("panel", "PanelContainer", panel_style())
	theme.set_stylebox("panel", "TabContainer", _box(Color(0.17, 0.14, 0.11), BORDER_COLOR))
	theme.set_stylebox("panel", "PopupPanel", panel_style())
	theme.set_stylebox("panel", "AcceptDialog", panel_style())
	theme.set_constant("separation", "VBoxContainer", 10)
	theme.set_constant("separation", "HBoxContainer", 10)
	return theme


static func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	return style


## A full-screen centred panel; returns the VBoxContainer to put things in.
static func centered_panel(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	return column


static func button(text: String, on_pressed: Callable, width := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(width, 46)
	b.pressed.connect(func(): _click())
	b.pressed.connect(on_pressed)
	return b


static func label(text: String, font_size := 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


static func title(text: String, font_size := 40) -> Label:
	var l := label(text, font_size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	return l


static func _click() -> void:
	var settings = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("Settings")
	if settings:
		settings.play_click()


static func _box(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
