extends Node3D
## Entry point: sets up controls, sky, sun, the world and the player,
## and handles saving and loading.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const SaveGame := preload("res://scripts/save_game.gd")
const InventoryScript := preload("res://scripts/inventory.gd")
const InventoryUIScript := preload("res://scripts/inventory_ui.gd")

## Seed for a brand-new world. A saved game keeps the seed it was started with.
@export var world_seed: int = 1337
@export var autosave_seconds := 30.0

var world  # world.gd
var player  # player.gd
var day_night  # day_night.gd
var inventory  # inventory.gd
var inventory_ui  # inventory_ui.gd

var _toast: Label
var _toast_tween: Tween
var _restart_armed_until := 0.0


func _ready() -> void:
	_setup_input()
	_build_toast()

	var save := SaveGame.read()
	if save.has("world_seed"):
		world_seed = int(save["world_seed"])

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	day_night = DayNightScript.new()
	day_night.name = "DayNight"
	day_night.sun = sun
	day_night.world_environment = env
	if save.has("time_of_day"):
		day_night.time_of_day = float(save["time_of_day"])
	add_child(day_night)

	world = WorldScript.new()
	world.name = "World"
	world.world_seed = world_seed
	add_child(world)

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	if save.has("player"):
		player.apply_save_data(save["player"])
		show_message("Welcome back!")
	else:
		player.global_position = world.find_spawn_point()

	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.changed.connect(_on_inventory_changed)
	if save.has("inventory"):
		inventory.apply_save_data(save["inventory"])
	else:
		inventory.give_starter_items()

	inventory_ui = InventoryUIScript.new()
	inventory_ui.name = "InventoryUI"
	inventory_ui.inventory = inventory
	inventory_ui.player = player
	add_child(inventory_ui)

	world.target = player
	world.generate_around(player.global_position, true)

	var timer := Timer.new()
	timer.wait_time = autosave_seconds
	timer.autostart = true
	timer.timeout.connect(save_game.bind(false))
	add_child(timer)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game(true)
	elif event.is_action_pressed("restart_game"):
		_request_restart()


func _notification(what: int) -> void:
	# Save when the window is closed.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(false)


func save_game(announce: bool) -> void:
	var data := {
		"world_seed": world_seed,
		"time_of_day": day_night.time_of_day,
		"player": player.get_save_data(),
		"inventory": inventory.get_save_data(),
		"saved_at": Time.get_datetime_string_from_system(),
	}
	var ok: bool = SaveGame.write(data)
	if announce or not ok:
		show_message("Game saved" if ok else "Could not save the game!")


## Press twice within 3 seconds to wipe the save and start over.
func _request_restart() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now > _restart_armed_until:
		_restart_armed_until = now + 3.0
		show_message("Press F9 again to start over (your save will be erased)")
		return
	# Reloading with no save starts fresh, using the world_seed set on this scene.
	SaveGame.delete()
	get_tree().reload_current_scene()


## Worn equipment changes how the player looks, runs and jumps.
func _on_inventory_changed() -> void:
	var stats: Dictionary = inventory.get_stats()
	player.speed_bonus = stats["speed"]
	player.jump_bonus = stats["jump"]
	var colors := {}
	for slot in inventory.ARMOR_SLOTS + inventory.ACCESSORY_SLOTS:
		var color = inventory.worn_color(slot)
		if color != null:
			colors[slot] = color
	player.set_look(colors)


func show_message(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_toast = Label.new()
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 24.0
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 26)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.modulate.a = 0.0
	layer.add_child(_toast)


func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("release_mouse", [KEY_ESCAPE])
	_add_keys("save_game", [KEY_F5])
	_add_keys("restart_game", [KEY_F9])
	_add_keys("inventory", [KEY_I, KEY_TAB])


func _add_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
