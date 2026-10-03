extends Control
## One square in the inventory screen. Draws its item, and handles
## drag-and-drop and right-click (equip / unequip).

signal hovered(ref)

const Items := preload("res://scripts/items.gd")
const SIZE := 64.0

var inventory  # inventory.gd
var ref  # int for a bag slot, String for a hotbar or equipment slot
## Small number drawn in the corner (hotbar keys).
var number := ""
## Drawn with a bright frame (the hotbar slot in your hand).
var selected := false:
	set(value):
		selected = value
		queue_redraw()

var _count_label: Label
var _hover := false
var _drop_ok := false


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	_count_label = Label.new()
	_count_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_count_label.offset_right = -4.0
	_count_label.add_theme_font_size_override("font_size", 14)
	_count_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_count_label.add_theme_constant_override("outline_size", 4)
	_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_count_label)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	refresh()


func _on_mouse_entered() -> void:
	_hover = true
	hovered.emit(ref)
	queue_redraw()


func _on_mouse_exited() -> void:
	_hover = false
	_drop_ok = false
	queue_redraw()


func refresh() -> void:
	var entry = inventory.get_slot(ref)
	_count_label.text = str(entry["count"]) if entry != null and entry["count"] > 1 else ""
	tooltip_text = Items.describe(entry["id"]) if entry != null else ""
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		inventory.quick_move(ref)
		accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var entry = inventory.get_slot(ref)
	if entry == null:
		return null
	var preview := Control.new()
	var icon := Control.new()
	icon.size = Vector2(SIZE, SIZE)
	icon.position = -icon.size * 0.5
	icon.modulate.a = 0.8
	icon.draw.connect(func(): draw_icon(icon, entry["id"], "", Rect2(Vector2.ZERO, icon.size)))
	preview.add_child(icon)
	set_drag_preview(preview)
	return {"inventory_ref": ref}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and data.has("inventory_ref") and inventory.can_move(data["inventory_ref"], ref)
	if ok != _drop_ok:
		_drop_ok = ok
		queue_redraw()
	return ok


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	_drop_ok = false
	inventory.move(data["inventory_ref"], ref)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _drop_ok:
		_drop_ok = false
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var bg := Color(0.13, 0.12, 0.11, 0.92) if inventory.is_storage(ref) else Color(0.17, 0.14, 0.10, 0.92)
	draw_rect(rect, bg)
	var border := Color(0.45, 0.40, 0.32)
	if _drop_ok:
		border = Color(0.45, 0.85, 0.40)
	elif _hover or selected:
		border = Color(0.95, 0.85, 0.55)
	draw_rect(rect.grow(-1.0), border, false, 4.0 if selected else 2.0)

	var entry = inventory.get_slot(ref)
	if entry != null:
		draw_icon(self, entry["id"], "", rect)
	elif not inventory.is_storage(ref):
		# Faint outline of what belongs here.
		draw_icon(self, "", inventory.slot_type(ref), rect)
	if number != "":
		draw_string(get_theme_default_font(), Vector2(5, 16), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
				Color(1, 1, 1, 0.9 if selected else 0.5))


## Draws a simple shape for an item (or a faint placeholder for an empty slot type).
static func draw_icon(canvas: CanvasItem, id: String, placeholder: String, rect: Rect2) -> void:
	var info := Items.get_info(id)
	var shape: String = info.get("icon", info.get("slot", "")) if id != "" else placeholder
	var color: Color = info.get("color", Color.WHITE) if id != "" else Color(1, 1, 1, 0.12)
	var dark := color.darkened(0.45) if id != "" else Color(0, 0, 0, 0)
	var o := rect.position + rect.size * 0.15
	var s := rect.size.x * 0.7
	var p := func(points: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for pt in points:
			out.append(o + pt * s)
		return out

	match shape:
		"head":
			canvas.draw_colored_polygon(p.call([Vector2(0.1, 0.75), Vector2(0.15, 0.4), Vector2(0.3, 0.15),
					Vector2(0.5, 0.08), Vector2(0.7, 0.15), Vector2(0.85, 0.4), Vector2(0.9, 0.75)]), color)
			canvas.draw_rect(Rect2(o + Vector2(0.02, 0.72) * s, Vector2(0.96, 0.12) * s), dark if id != "" else color)
		"chest":
			canvas.draw_colored_polygon(p.call([Vector2(0.3, 0.05), Vector2(0.42, 0.15), Vector2(0.58, 0.15),
					Vector2(0.7, 0.05), Vector2(1.0, 0.25), Vector2(0.88, 0.45), Vector2(0.78, 0.4),
					Vector2(0.78, 0.95), Vector2(0.22, 0.95), Vector2(0.22, 0.4), Vector2(0.12, 0.45),
					Vector2(0.0, 0.25)]), color)
		"hands":
			canvas.draw_colored_polygon(p.call([Vector2(0.25, 0.95), Vector2(0.25, 0.25), Vector2(0.38, 0.12),
					Vector2(0.72, 0.12), Vector2(0.72, 0.5), Vector2(0.92, 0.35), Vector2(0.98, 0.45),
					Vector2(0.75, 0.75), Vector2(0.75, 0.95)]), color)
			canvas.draw_rect(Rect2(o + Vector2(0.22, 0.8) * s, Vector2(0.56, 0.15) * s), dark if id != "" else color)
		"legs":
			canvas.draw_colored_polygon(p.call([Vector2(0.18, 0.05), Vector2(0.82, 0.05), Vector2(0.9, 0.95),
					Vector2(0.6, 0.95), Vector2(0.5, 0.35), Vector2(0.4, 0.95), Vector2(0.1, 0.95)]), color)
		"feet":
			canvas.draw_colored_polygon(p.call([Vector2(0.3, 0.05), Vector2(0.65, 0.05), Vector2(0.65, 0.6),
					Vector2(0.95, 0.75), Vector2(0.95, 0.92), Vector2(0.25, 0.92), Vector2(0.3, 0.6)]), color)
		"neck":
			canvas.draw_arc(o + Vector2(0.5, 0.2) * s, 0.35 * s, 0.15, PI - 0.15, 16, color, 0.06 * s)
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.48), Vector2(0.68, 0.68), Vector2(0.5, 0.92),
					Vector2(0.32, 0.68)]), color)
		"ring":
			canvas.draw_arc(o + Vector2(0.5, 0.58) * s, 0.3 * s, 0.0, TAU, 24, color, 0.1 * s)
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.08), Vector2(0.64, 0.2), Vector2(0.5, 0.32),
					Vector2(0.36, 0.2)]), color.lightened(0.3) if id != "" else color)
		"charm":
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.0), Vector2(0.62, 0.38), Vector2(1.0, 0.5),
					Vector2(0.62, 0.62), Vector2(0.5, 1.0), Vector2(0.38, 0.62), Vector2(0.0, 0.5),
					Vector2(0.38, 0.38)]), color)
		"round":
			canvas.draw_circle(o + Vector2(0.5, 0.58) * s, 0.36 * s, color)
			canvas.draw_line(o + Vector2(0.5, 0.25) * s, o + Vector2(0.56, 0.05) * s, dark, 0.06 * s)
		"rock":
			canvas.draw_colored_polygon(p.call([Vector2(0.15, 0.85), Vector2(0.05, 0.5), Vector2(0.3, 0.2),
					Vector2(0.65, 0.15), Vector2(0.95, 0.45), Vector2(0.85, 0.85)]), color)
		"axe", "pickaxe":
			var wood := Color(0.55, 0.38, 0.22)
			canvas.draw_line(o + Vector2(0.2, 0.95) * s, o + Vector2(0.72, 0.15) * s, wood, 0.1 * s)
			if shape == "axe":
				canvas.draw_colored_polygon(p.call([Vector2(0.55, 0.12), Vector2(0.95, 0.05), Vector2(1.0, 0.5),
						Vector2(0.72, 0.42)]), color)
			else:
				canvas.draw_colored_polygon(p.call([Vector2(0.2, 0.12), Vector2(0.62, 0.02), Vector2(1.0, 0.25),
						Vector2(0.98, 0.42), Vector2(0.68, 0.24), Vector2(0.3, 0.28)]), color)
		"bar":  # An ingot.
			canvas.draw_colored_polygon(p.call([Vector2(0.05, 0.75), Vector2(0.95, 0.75), Vector2(0.8, 0.4),
					Vector2(0.2, 0.4)]), color)
			canvas.draw_colored_polygon(p.call([Vector2(0.2, 0.4), Vector2(0.8, 0.4), Vector2(0.72, 0.3),
					Vector2(0.28, 0.3)]), color.lightened(0.3))
		"bench":
			canvas.draw_rect(Rect2(o + Vector2(0.05, 0.3) * s, Vector2(0.9, 0.14) * s), color)
			for x in [0.12, 0.78]:
				canvas.draw_rect(Rect2(o + Vector2(x, 0.44) * s, Vector2(0.1, 0.5) * s), dark)
			canvas.draw_rect(Rect2(o + Vector2(0.55, 0.15) * s, Vector2(0.25, 0.15) * s), Color(0.6, 0.6, 0.6))
		"lantern":
			canvas.draw_arc(o + Vector2(0.5, 0.18) * s, 0.12 * s, PI, TAU, 10, Color(0.35, 0.33, 0.3), 0.05 * s)
			canvas.draw_rect(Rect2(o + Vector2(0.25, 0.25) * s, Vector2(0.5, 0.65) * s), Color(0.3, 0.28, 0.26))
			canvas.draw_rect(Rect2(o + Vector2(0.32, 0.33) * s, Vector2(0.36, 0.48) * s), color)
			canvas.draw_circle(o + Vector2(0.5, 0.6) * s, 0.1 * s, Color(1.0, 0.95, 0.7))
		"campfire":
			for x in [0.15, 0.55]:
				canvas.draw_line(o + Vector2(x, 0.95) * s, o + Vector2(x + 0.3, 0.75) * s, Color(0.5, 0.33, 0.2), 0.12 * s)
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.1), Vector2(0.75, 0.6), Vector2(0.62, 0.85),
					Vector2(0.38, 0.85), Vector2(0.25, 0.6)]), color)
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.4), Vector2(0.62, 0.7), Vector2(0.5, 0.85),
					Vector2(0.38, 0.7)]), Color(1.0, 0.9, 0.4))
		"bowl":
			canvas.draw_circle(o + Vector2(0.32, 0.45) * s, 0.14 * s, color)
			canvas.draw_circle(o + Vector2(0.55, 0.4) * s, 0.12 * s, Color(0.80, 0.12, 0.22))
			canvas.draw_circle(o + Vector2(0.68, 0.48) * s, 0.12 * s, Color(0.95, 0.75, 0.3))
			canvas.draw_colored_polygon(p.call([Vector2(0.05, 0.5), Vector2(0.95, 0.5), Vector2(0.8, 0.85),
					Vector2(0.2, 0.85)]), Color(0.62, 0.45, 0.27))
		"lump":
			canvas.draw_colored_polygon(p.call([Vector2(0.2, 0.85), Vector2(0.08, 0.55), Vector2(0.25, 0.25),
					Vector2(0.55, 0.18), Vector2(0.9, 0.35), Vector2(0.92, 0.7), Vector2(0.7, 0.9)]), color)
			canvas.draw_colored_polygon(p.call([Vector2(0.3, 0.35), Vector2(0.5, 0.28), Vector2(0.45, 0.45)]),
					color.lightened(0.35))
		"ore":  # Grey rock with flecks of the ore's colour.
			canvas.draw_colored_polygon(p.call([Vector2(0.15, 0.85), Vector2(0.05, 0.5), Vector2(0.3, 0.2),
					Vector2(0.65, 0.15), Vector2(0.95, 0.45), Vector2(0.85, 0.85)]), Color(0.45, 0.43, 0.41))
			for fleck in [Vector2(0.35, 0.4), Vector2(0.65, 0.35), Vector2(0.5, 0.65), Vector2(0.25, 0.68), Vector2(0.75, 0.65)]:
				canvas.draw_circle(o + fleck * s, 0.09 * s, color)
		"log":
			canvas.draw_colored_polygon(p.call([Vector2(0.1, 0.35), Vector2(0.75, 0.35), Vector2(0.75, 0.8),
					Vector2(0.1, 0.8)]), color)
			canvas.draw_circle(o + Vector2(0.75, 0.575) * s, 0.225 * s, color.lightened(0.3))
			canvas.draw_arc(o + Vector2(0.75, 0.575) * s, 0.12 * s, 0.0, TAU, 16, dark, 0.03 * s)
		"gem":
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.05), Vector2(0.8, 0.35), Vector2(0.5, 0.95),
					Vector2(0.2, 0.35)]), color)
			canvas.draw_colored_polygon(p.call([Vector2(0.5, 0.05), Vector2(0.62, 0.35), Vector2(0.5, 0.95),
					Vector2(0.38, 0.35)]), color.lightened(0.4))
		"berries":
			for berry in [Vector2(0.35, 0.6), Vector2(0.65, 0.6), Vector2(0.5, 0.35)]:
				canvas.draw_circle(o + berry * s, 0.18 * s, color)
			canvas.draw_line(o + Vector2(0.5, 0.2) * s, o + Vector2(0.62, 0.05) * s, Color(0.3, 0.55, 0.25), 0.06 * s)
		_:
			canvas.draw_circle(o + Vector2(0.5, 0.5) * s, 0.3 * s, color)
