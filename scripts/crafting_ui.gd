extends CanvasLayer
## The crafting menu, opened by pressing E (or clicking) at a crafting bench.
## Pick a recipe on the left; the right side shows what it needs and what you
## have. Esc, E, I or Tab closes it.

const Items := preload("res://scripts/items.gd")
const Recipes := preload("res://scripts/recipes.gd")
const SlotScript := preload("res://scripts/inventory_slot.gd")
const UI := preload("res://scripts/ui.gd")

const HAVE_COLOR := Color(0.55, 0.9, 0.45)
const MISSING_COLOR := Color(1.0, 0.5, 0.42)

var inventory  # inventory.gd
var player  # player.gd
var world  # world.gd
var game  # game.gd
var gathering  # gathering.gd

var _bench := {}
var _selected := 0
var _buttons: Array[Button] = []
var _detail_id := ""
var _detail_icon: Control
var _detail_name: Label
var _detail_desc: Label
var _needs_box: VBoxContainer
var _craft_button: Button
var _status: Label


func _ready() -> void:
	layer = 6
	_build()
	visible = false
	inventory.changed.connect(_refresh)


func is_open() -> bool:
	return visible


func open(bench: Dictionary) -> void:
	_bench = bench
	visible = true
	player.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_status.text = ""
	_refresh()


func close() -> void:
	visible = false
	player.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	gathering.block_until_msec = Time.get_ticks_msec() + 300


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") \
			or (InputMap.has_action("gather") and event.is_action_pressed("gather")):
		close()
		get_viewport().set_input_as_handled()


func can_craft(recipe: Dictionary) -> bool:
	return Recipes.can_craft(recipe, inventory)


func _craft() -> void:
	var recipe: Dictionary = Recipes.RECIPES[_selected]
	var problem := Recipes.craft(recipe, inventory)
	if problem != "":
		_status.text = problem
		_status.modulate = MISSING_COLOR
		return
	var made: int = recipe.get("count", 1)
	gathering.play_sound("mine")
	var item_name: String = Items.get_info(recipe["id"])["name"]
	_status.text = "Made %s%s!" % ["%d× " % made if made > 1 else "", item_name]
	_status.modulate = HAVE_COLOR


func _pick_up_bench() -> void:
	if inventory.room_for("crafting_bench") <= 0:
		_status.text = "No room in your bag for the bench."
		_status.modulate = MISSING_COLOR
		return
	world.remove_structure(_bench)
	inventory.add_item("crafting_bench")
	close()
	game.show_message("Picked up the Crafting Bench.")


func _select(index: int) -> void:
	_selected = index
	_status.text = ""
	_refresh()


func _refresh() -> void:
	if not visible:
		return
	for i in _buttons.size():
		var ok := can_craft(Recipes.RECIPES[i])
		_buttons[i].button_pressed = i == _selected
		_buttons[i].add_theme_color_override("font_color", Color.WHITE if ok else Color(1, 1, 1, 0.45))

	var recipe: Dictionary = Recipes.RECIPES[_selected]
	_detail_id = recipe["id"]
	_detail_icon.queue_redraw()
	var made: int = recipe.get("count", 1)
	_detail_name.text = Items.get_info(_detail_id)["name"] + (" ×%d" % made if made > 1 else "")
	_detail_desc.text = _describe_without_name(_detail_id)

	for child in _needs_box.get_children():
		child.queue_free()
	for id in recipe["needs"]:
		var need: int = recipe["needs"][id]
		var have: int = inventory.count_of(id)
		var row := HBoxContainer.new()
		row.add_child(_icon(id, 30))
		var name_label := UI.label(Items.get_info(id)["name"], 18)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var count_label := UI.label("need %d  •  have %d" % [need, have], 18)
		count_label.add_theme_color_override("font_color", HAVE_COLOR if have >= need else MISSING_COLOR)
		row.add_child(count_label)
		_needs_box.add_child(row)
	_craft_button.disabled = not can_craft(recipe)


## The item's stats and description, without the name line (that's shown above).
func _describe_without_name(id: String) -> String:
	var lines := Items.describe(id).split("\n")
	lines.remove_at(0)
	return "\n".join(lines)


func _icon(id: String, icon_size: float) -> Control:
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.draw.connect(func(): SlotScript.draw_icon(icon, id, "", Rect2(Vector2.ZERO, icon.size)))
	return icon


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = UI.make_theme()
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)

	var column := UI.centered_panel(root)
	column.get_parent().get_parent().offset_top = 50.0  # Leave room for messages at the top.
	column.add_child(UI.title("Crafting Bench", 32))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	column.add_child(row)

	# Left: every recipe, under its group heading.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var group := ButtonGroup.new()
	var heading := ""
	for i in Recipes.RECIPES.size():
		var recipe: Dictionary = Recipes.RECIPES[i]
		if recipe["group"] != heading:
			heading = recipe["group"]
			var label := UI.label(heading, 16)
			label.modulate = UI.SOFT_TEXT_COLOR
			list.add_child(label)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		line.add_child(_icon(recipe["id"], 36))
		var button := Button.new()
		button.text = Items.get_info(recipe["id"])["name"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 40
		button.pressed.connect(_select.bind(i))
		line.add_child(button)
		list.add_child(line)
		_buttons.append(button)

	row.add_child(VSeparator.new())

	# Right: the picked recipe.
	var detail := VBoxContainer.new()
	detail.custom_minimum_size.x = 380
	row.add_child(detail)
	var top := HBoxContainer.new()
	detail.add_child(top)
	_detail_icon = Control.new()
	_detail_icon.custom_minimum_size = Vector2(72, 72)
	_detail_icon.draw.connect(func(): SlotScript.draw_icon(_detail_icon, _detail_id, "", Rect2(Vector2.ZERO, _detail_icon.size)))
	top.add_child(_detail_icon)
	_detail_name = UI.label("", 26)
	_detail_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_detail_name)
	_detail_desc = UI.label("", 17)
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.custom_minimum_size = Vector2(380, 70)
	_detail_desc.modulate = Color(1.0, 0.92, 0.7)
	detail.add_child(_detail_desc)
	detail.add_child(UI.label("Needs", 20))
	_needs_box = VBoxContainer.new()
	_needs_box.add_theme_constant_override("separation", 4)
	detail.add_child(_needs_box)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail.add_child(spacer)
	_craft_button = UI.button("Craft", _craft, 380)
	detail.add_child(_craft_button)
	_status = UI.label("", 18)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.y = 28
	detail.add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_child(UI.button("Pick Up Bench", _pick_up_bench, 220))
	buttons.add_child(UI.button("Close", close, 160))
	column.add_child(buttons)
	var hint := UI.label("Click a recipe, then Craft  •  Esc or E to close", 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = UI.SOFT_TEXT_COLOR
	column.add_child(hint)
