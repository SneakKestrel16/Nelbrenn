extends CanvasLayer
## The always-on-screen HUD: the hotbar along the bottom with health and
## food bars above it. Keys 1–8 or the mouse wheel pick the hotbar slot in
## your hand; F or right click eats the food you're holding.

const SlotScript := preload("res://scripts/inventory_slot.gd")
const Items := preload("res://scripts/items.gd")
const UI := preload("res://scripts/ui.gd")

const HEALTH_COLOR := Color(0.85, 0.25, 0.25)
const FOOD_COLOR := Color(0.92, 0.62, 0.25)

var inventory  # inventory.gd
var player  # player.gd
var vitals  # vitals.gd

var _slots: Array = []
var _health_bar: ProgressBar
var _food_bar: ProgressBar
var _name_label: Label
var _name_tween: Tween
var _audio: AudioStreamPlayer
var _last_selected := -1


func _ready() -> void:
	layer = 3
	_build()
	_audio = AudioStreamPlayer.new()
	_audio.bus = "Effects"
	_audio.stream = _make_crunch()
	add_child(_audio)
	inventory.changed.connect(_refresh)
	_refresh()


func _process(_delta: float) -> void:
	_health_bar.value = vitals.health
	_food_bar.value = vitals.hunger
	# Blink the food bar when it's nearly empty.
	_food_bar.modulate.a = 0.55 + 0.45 * absf(sin(Time.get_ticks_msec() * 0.005)) if vitals.hunger < 20.0 else 1.0


func _unhandled_input(event: InputEvent) -> void:
	if not player.controls_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode >= KEY_1 and event.physical_keycode < KEY_1 + inventory.HOTBAR_SIZE:
		inventory.select(event.physical_keycode - KEY_1)
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				inventory.select(inventory.selected - 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				inventory.select(inventory.selected + 1)
			MOUSE_BUTTON_RIGHT:
				use_held_item()
	elif InputMap.has_action("use_item") and event.is_action_pressed("use_item"):
		use_held_item()


## Eats the held food. (Tools are used by gathering.gd instead.)
func use_held_item() -> void:
	var id: String = inventory.selected_id()
	if Items.get_info(id).get("food", 0) > 0 and vitals.eat(id):
		inventory.consume_selected()
		player.eat_animation()
		_audio.pitch_scale = randf_range(0.9, 1.1)
		_audio.play()


func _refresh() -> void:
	for i in _slots.size():
		_slots[i].selected = i == inventory.selected
		_slots[i].refresh()
	if inventory.selected != _last_selected:
		if _last_selected != -1:
			_show_name()
		_last_selected = inventory.selected


## Briefly shows the name of the item you just switched to.
func _show_name() -> void:
	var id: String = inventory.selected_id()
	_name_label.text = Items.get_info(id)["name"] if id != "" else "Empty hand"
	_name_label.modulate.a = 1.0
	if _name_tween:
		_name_tween.kill()
	_name_tween = create_tween()
	_name_tween.tween_interval(1.2)
	_name_tween.tween_property(_name_label, "modulate:a", 0.0, 0.5)


func _build() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	column.grow_horizontal = Control.GROW_DIRECTION_BOTH
	column.grow_vertical = Control.GROW_DIRECTION_BEGIN
	column.offset_bottom = -14.0
	column.add_theme_constant_override("separation", 6)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_name_label = UI.label("", 18)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_name_label.add_theme_constant_override("outline_size", 5)
	_name_label.modulate.a = 0.0
	column.add_child(_name_label)

	var bars := HBoxContainer.new()
	bars.add_theme_constant_override("separation", 20)
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bars)
	_health_bar = _bar(bars, "heart", HEALTH_COLOR)
	_food_bar = _bar(bars, "apple", FOOD_COLOR)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(row)
	for i in inventory.HOTBAR_SIZE:
		var slot := SlotScript.new()
		slot.inventory = inventory
		slot.ref = inventory.hotbar_ref(i)
		slot.number = str(i + 1)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE  # Just a display; drag items in the inventory screen.
		row.add_child(slot)
		_slots.append(slot)


func _bar(parent: Control, icon_kind: String, color: Color) -> ProgressBar:
	var box := HBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)
	var icon := Control.new()
	icon.custom_minimum_size = Vector2(24, 24)
	var draw_icon := func() -> void:
		if icon_kind == "heart":
			icon.draw_circle(Vector2(8, 9), 6, color)
			icon.draw_circle(Vector2(16, 9), 6, color)
			icon.draw_colored_polygon(PackedVector2Array([Vector2(2.5, 11), Vector2(21.5, 11), Vector2(12, 22)]), color)
		else:
			SlotScript.draw_icon(icon, "apple", "", Rect2(Vector2.ZERO, icon.size))
	icon.draw.connect(draw_icon)
	box.add_child(icon)
	var bar := ProgressBar.new()
	bar.max_value = vitals.MAX
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.border_color = Color(0, 0, 0, 0.7)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	box.add_child(bar)
	return bar


## A short crunchy bite, made in code so there's no sound file.
func _make_crunch() -> AudioStreamWAV:
	var rate := 22050
	var length := 0.22
	var samples := int(rate * length)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / rate
		# Three quick crackly bursts.
		var burst := 0.0
		for start in [0.0, 0.06, 0.13]:
			if t >= start:
				burst += exp(-(t - start) * 70.0)
		var s := rng.randf_range(-1.0, 1.0) * burst * 0.35
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
