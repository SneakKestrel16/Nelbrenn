extends CanvasLayer
## The inventory screen. Press I or Tab to open and close it (Esc also closes).
## Drag items between slots, or right-click to equip / unequip.

const SlotScript := preload("res://scripts/inventory_slot.gd")
const Items := preload("res://scripts/items.gd")

const HINT := "Drag items to move them  •  Right-click to equip / unequip  •  I or Tab to close"

var inventory  # inventory.gd
var player  # player.gd

var _slots: Array = []
var _stats_label: Label
var _info_label: Label


func _ready() -> void:
	layer = 5
	_build()
	visible = false
	inventory.changed.connect(_refresh)


func is_open() -> bool:
	return visible


func set_open(open: bool) -> void:
	visible = open
	player.controls_enabled = not open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	if open:
		_info_label.text = ""
		_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		set_open(not visible)
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("pause"):
		set_open(false)
		get_viewport().set_input_as_handled()


func _refresh() -> void:
	for slot in _slots:
		slot.refresh()
	var stats: Dictionary = inventory.get_stats()
	_stats_label.text = "Armor  %d\nSpeed  %+d%%\nJump   %+d%%" % [stats["armor"], stats["speed"], stats["jump"]]


func _on_slot_hovered(ref) -> void:
	var entry = inventory.get_slot(ref)
	if entry != null:
		_info_label.text = Items.describe(entry["id"]).replace("\n", "  •  ")
	elif ref is int:
		_info_label.text = ""
	else:
		_info_label.text = "%s slot (empty)" % inventory.SLOT_LABELS[ref]


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	# Dark backdrop; also stops clicks from reaching the game behind.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)

	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.22, 0.18, 0.14, 0.97)
	style.border_color = Color(0.55, 0.45, 0.30)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	panel.add_child(column)

	var title := _label("Inventory", 30)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	column.add_child(row)

	# Left: worn equipment and stats.
	var gear := VBoxContainer.new()
	gear.add_theme_constant_override("separation", 8)
	row.add_child(gear)
	gear.add_child(_label("Armor", 20))
	gear.add_child(_equipment_grid(inventory.ARMOR_SLOTS))
	gear.add_child(_label("Accessories", 20))
	gear.add_child(_equipment_grid(inventory.ACCESSORY_SLOTS))
	_stats_label = _label("", 18)
	gear.add_child(_stats_label)

	row.add_child(VSeparator.new())

	# Right: the bag.
	var bag_box := VBoxContainer.new()
	bag_box.add_theme_constant_override("separation", 8)
	row.add_child(bag_box)
	bag_box.add_child(_label("Bag", 20))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	bag_box.add_child(grid)
	for i in inventory.BAG_SIZE:
		grid.add_child(_make_slot(i))

	_info_label = _label("", 17)
	_info_label.custom_minimum_size.y = 26
	_info_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	column.add_child(_info_label)

	var hint := _label(HINT, 15)
	hint.modulate = Color(1, 1, 1, 0.6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(hint)


func _equipment_grid(slot_names: Array[String]) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = slot_names.size()
	grid.add_theme_constant_override("h_separation", 6)
	for slot_name in slot_names:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		cell.add_child(_make_slot(slot_name))
		var name_label := _label(inventory.SLOT_LABELS[slot_name], 13)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.modulate = Color(1, 1, 1, 0.7)
		cell.add_child(name_label)
		grid.add_child(cell)
	return grid


func _make_slot(ref) -> Control:
	var slot := SlotScript.new()
	slot.inventory = inventory
	slot.ref = ref
	slot.hovered.connect(_on_slot_hovered)
	_slots.append(slot)
	return slot


func _label(text: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	return label
