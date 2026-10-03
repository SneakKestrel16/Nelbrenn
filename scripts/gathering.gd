extends CanvasLayer
## Chopping trees, mining rocks and ore, and picking berries. Walk up to
## something and hold E (or the left mouse button) to gather from it.
## Shows a prompt over the thing you'd hit, and a list of what you picked up.

const Harvestables := preload("res://scripts/harvestables.gd")
const Items := preload("res://scripts/items.gd")
const SlotScript := preload("res://scripts/inventory_slot.gd")
const UI := preload("res://scripts/ui.gd")

const REACH := 2.2          ## Metres from the player to the edge of what they can reach.
const HIT_INTERVAL := 0.45  ## Seconds between hits while the button is held.
const FEED_SECONDS := 2.5   ## How long a "+3 Wood" line stays on screen.

var world  # world.gd
var player  # player.gd
var inventory  # inventory.gd
var game  # game.gd, for messages

var _target := {}
var _cooldown := 0.0
var _full_cooldown := 0.0
var _rng := RandomNumberGenerator.new()

var _prompt: PanelContainer
var _prompt_label: Label
var _hp_bar: ProgressBar
var _feed: VBoxContainer
var _feed_lines := {}  # item id -> {"row", "label", "count", "time"}

var _audio: AudioStreamPlayer
var _sounds := {}  # "chop" / "mine" / "pick" -> AudioStreamWAV


func _ready() -> void:
	layer = 4
	_rng.randomize()
	_build_ui()
	_audio = AudioStreamPlayer.new()
	_audio.bus = "Effects"
	_audio.max_polyphony = 4
	add_child(_audio)
	for kind in ["chop", "mine", "pick"]:
		_sounds[kind] = _make_sound(kind)


func _process(delta: float) -> void:
	_cooldown -= delta
	_full_cooldown -= delta
	var active: bool = player.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	_target = world.find_resource(player.global_position, player.get_look_direction(), REACH) if active else {}
	if not _target.is_empty() and _wants_gather() and _cooldown <= 0.0:
		_cooldown = HIT_INTERVAL
		_hit(_target)
		if not _target["alive"]:
			_target = {}
	_update_prompt()
	_update_feed(delta)


func _wants_gather() -> bool:
	return (InputMap.has_action("gather") and Input.is_action_pressed("gather")) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _hit(node: Dictionary) -> void:
	var info := Harvestables.get_info(node["kind"])
	var main := Harvestables.main_item(node["kind"])
	if main != "" and inventory.room_for(main) <= 0:
		_bag_full()
		return

	player.swing_at(node["pos"])
	_audio.stream = _sounds[info["sound"]]
	_audio.pitch_scale = _rng.randf_range(0.88, 1.12)
	_audio.play()

	var broke: bool = world.hit_resource(node, player.global_position)
	var drops := Harvestables.roll(info["per_hit"], _rng)
	if broke:
		var extra := Harvestables.roll(info["on_break"], _rng)
		for id in extra:
			drops[id] = drops.get(id, 0) + extra[id]
	for id in drops:
		var left: int = inventory.add_item(id, drops[id])
		if drops[id] - left > 0:
			_add_to_feed(id, drops[id] - left)
		if left > 0:
			_bag_full()


func _bag_full() -> void:
	if _full_cooldown <= 0.0:
		_full_cooldown = 2.5
		game.show_message("Your bag is full!")


# --- Prompt over the target ---------------------------------------------------

func _update_prompt() -> void:
	var camera: Camera3D = player.get_camera()
	var anchor: Vector3 = Vector3.ZERO if _target.is_empty() else _target["pos"] + Vector3.UP * (2.2 if _target["tree"] else 1.6)
	if _target.is_empty() or camera.is_position_behind(anchor):
		_prompt.visible = false
		return
	var info := Harvestables.get_info(_target["kind"])
	var key := Settings.key_name(Settings.get_binding("gather", 0)) if InputMap.has_action("gather") else "—"
	_prompt_label.text = "[%s]  %s %s" % ["Click" if key == "—" else key, info["action"], info["name"]]
	_hp_bar.visible = info["hits"] > 1
	_hp_bar.max_value = info["hits"]
	_hp_bar.value = _target["hp"]
	_prompt.visible = true
	_prompt.reset_size()
	_prompt.position = camera.unproject_position(anchor) - Vector2(_prompt.size.x * 0.5, _prompt.size.y)


# --- "+3 Wood" pickup list ------------------------------------------------------

func _add_to_feed(id: String, count: int) -> void:
	if not _feed_lines.has(id):
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		row.add_theme_constant_override("separation", 6)
		var label := _outlined_label(18)
		row.add_child(label)
		var icon := Control.new()
		icon.custom_minimum_size = Vector2(30, 30)
		icon.draw.connect(func(): SlotScript.draw_icon(icon, id, "", Rect2(Vector2.ZERO, icon.size)))
		row.add_child(icon)
		_feed.add_child(row)
		_feed_lines[id] = {"row": row, "label": label, "count": 0, "time": 0.0}
	var line: Dictionary = _feed_lines[id]
	line["count"] += count
	line["time"] = FEED_SECONDS
	line["label"].text = "+%d %s  (%d)" % [line["count"], Items.get_info(id)["name"], _total(id)]
	line["row"].modulate.a = 1.0


func _update_feed(delta: float) -> void:
	for id in _feed_lines.keys():
		var line: Dictionary = _feed_lines[id]
		line["time"] -= delta
		line["row"].modulate.a = clampf(line["time"] / 0.5, 0.0, 1.0)
		if line["time"] <= 0.0:
			line["row"].queue_free()
			_feed_lines.erase(id)


## How many of `id` are in the bag altogether.
func _total(id: String) -> int:
	var n := 0
	for entry in inventory.bag:
		if entry != null and entry["id"] == id:
			n += entry["count"]
	return n


func _build_ui() -> void:
	_prompt = PanelContainer.new()
	var style := UI.panel_style()
	style.bg_color = Color(0.12, 0.10, 0.08, 0.75)
	style.set_border_width_all(2)
	style.set_content_margin_all(8)
	_prompt.add_theme_stylebox_override("panel", style)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	add_child(_prompt)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_prompt.add_child(column)
	_prompt_label = _outlined_label(17)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_prompt_label)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(0, 7)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = UI.HIGHLIGHT_COLOR
	fill.set_corner_radius_all(3)
	_hp_bar.add_theme_stylebox_override("background", bg)
	_hp_bar.add_theme_stylebox_override("fill", fill)
	column.add_child(_hp_bar)

	_feed = VBoxContainer.new()
	_feed.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_feed.offset_right = -24.0
	_feed.offset_bottom = -24.0
	_feed.alignment = BoxContainer.ALIGNMENT_END
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_feed)


func _outlined_label(font_size: int) -> Label:
	var label := UI.label("", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


# --- Sounds, made in code so there are no sound files -------------------------

func _make_sound(kind: String) -> AudioStreamWAV:
	var rate := 22050
	var length: float = {"chop": 0.2, "mine": 0.25, "pick": 0.15}[kind]
	var samples := int(rate * length)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	var data := PackedByteArray()
	data.resize(samples * 2)
	var smooth := 0.0
	for i in samples:
		var t := float(i) / rate
		var noise := rng.randf_range(-1.0, 1.0)
		var s := 0.0
		match kind:
			"chop":  # A dull wooden thunk.
				var pitch := lerpf(170.0, 90.0, t / length)
				s = sin(TAU * pitch * t) * exp(-t * 28.0) * 0.6 + noise * exp(-t * 60.0) * 0.35
			"mine":  # A bright metal-on-stone clink.
				s = (sin(TAU * 1850.0 * t) * 0.5 + sin(TAU * 2790.0 * t) * 0.3) * exp(-t * 30.0) * 0.45
				s += noise * exp(-t * 90.0) * 0.4
			"pick":  # A leafy rustle.
				smooth = lerpf(smooth, noise, 0.25)
				s = smooth * sin(PI * t / length) * 0.5
		data.encode_s16(i * 2, int(clampf(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
