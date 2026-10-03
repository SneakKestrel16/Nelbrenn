extends Node3D
## The game itself: sets up the sky, sun, world, player, inventory and menus
## for the world picked in the main menu, and handles saving it.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const SaveGame := preload("res://scripts/save_game.gd")
const InventoryScript := preload("res://scripts/inventory.gd")
const InventoryUIScript := preload("res://scripts/inventory_ui.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const AmbienceScript := preload("res://scripts/ambience.gd")
const GatheringScript := preload("res://scripts/gathering.gd")
const VitalsScript := preload("res://scripts/vitals.gd")
const HudScript := preload("res://scripts/hud.gd")
const CraftingUIScript := preload("res://scripts/crafting_ui.gd")
const HorrorScript := preload("res://scripts/horror.gd")
const Items := preload("res://scripts/items.gd")

@export var autosave_seconds := 30.0

var world_id := ""
var world_name := ""
var world_seed := 0
var horror := false  ## Horror mode: fog, dark nights and monsters (see horror.gd).

var world  # world.gd
var player  # player.gd
var day_night  # day_night.gd
var inventory  # inventory.gd
var inventory_ui  # inventory_ui.gd
var pause_menu  # pause_menu.gd
var vitals  # vitals.gd
var crafting_ui  # crafting_ui.gd

var _sun: DirectionalLight3D
var _save_info := {}  # The world's name and dates, kept when saving.
var _toast: Label
var _toast_tween: Tween


func _ready() -> void:
	_build_toast()

	world_id = SaveGame.current_world_id
	if not SaveGame.exists(world_id):
		# Started straight from the editor (F6) without the main menu:
		# use the last played world, or make one.
		var worlds := SaveGame.list_worlds()
		world_id = worlds[0]["id"] if not worlds.is_empty() else SaveGame.create_world("Test World", SaveGame.seed_from_text(""))
		SaveGame.current_world_id = world_id
	var save := SaveGame.read(world_id)
	world_seed = int(save.get("world_seed", 1337))
	world_name = String(save.get("name", "World"))
	horror = bool(save.get("horror", false))
	for key in ["name", "world_seed", "horror", "created_at"]:
		if save.has(key):
			_save_info[key] = save[key]

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	add_child(env)

	_sun = DirectionalLight3D.new()
	_sun.name = "Sun"
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)

	day_night = DayNightScript.new()
	day_night.name = "DayNight"
	day_night.sun = _sun
	day_night.world_environment = env
	day_night.horror = horror
	if save.has("time_of_day"):
		day_night.time_of_day = float(save["time_of_day"])
	add_child(day_night)

	world = WorldScript.new()
	world.name = "World"
	world.world_seed = world_seed
	world.view_radius = Settings.get_value("graphics", "view_distance")
	add_child(world)
	if save.has("world"):  # Trees and rocks that were harvested and are still growing back.
		world.apply_save_data(save["world"])

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	var is_new := not save.has("player")
	if is_new:
		player.global_position = world.find_spawn_point()
	else:
		player.apply_save_data(save["player"])
		# The terrain may have changed since this was saved; never start inside the ground.
		var ground: float = world.get_height(player.global_position.x, player.global_position.z)
		if player.global_position.y < ground + 0.5:
			player.global_position.y = ground + 1.0

	inventory = InventoryScript.new()
	inventory.name = "Inventory"
	add_child(inventory)
	inventory.changed.connect(_on_inventory_changed)
	if save.has("inventory"):
		inventory.apply_save_data(save["inventory"])
	else:
		inventory.give_starter_items(horror)

	vitals = VitalsScript.new()
	vitals.name = "Vitals"
	vitals.player = player
	vitals.world = world
	vitals.game = self
	if save.has("vitals"):
		vitals.apply_save_data(save["vitals"])
	add_child(vitals)

	var hud := HudScript.new()
	hud.name = "HUD"
	hud.inventory = inventory
	hud.player = player
	hud.vitals = vitals
	hud.world = world
	hud.game = self
	add_child(hud)

	inventory_ui = InventoryUIScript.new()
	inventory_ui.name = "InventoryUI"
	inventory_ui.inventory = inventory
	inventory_ui.player = player
	add_child(inventory_ui)

	var gathering := GatheringScript.new()
	gathering.name = "Gathering"
	gathering.world = world
	gathering.player = player
	gathering.inventory = inventory
	gathering.game = self
	add_child(gathering)

	crafting_ui = CraftingUIScript.new()
	crafting_ui.name = "CraftingUI"
	crafting_ui.inventory = inventory
	crafting_ui.player = player
	crafting_ui.world = world
	crafting_ui.game = self
	crafting_ui.gathering = gathering
	add_child(crafting_ui)
	gathering.use_structure.connect(crafting_ui.open)

	if horror:
		var director := HorrorScript.new()
		director.name = "Horror"
		director.world = world
		director.player = player
		director.vitals = vitals
		director.day_night = day_night
		director.game = self
		add_child(director)

	var ambience := AmbienceScript.new()
	ambience.name = "Ambience"
	ambience.listener = player
	add_child(ambience)

	pause_menu = PauseMenuScript.new()
	pause_menu.name = "PauseMenu"
	pause_menu.game = self
	add_child(pause_menu)

	world.target = player
	world.generate_around(player.global_position, true)

	Settings.changed.connect(_apply_settings)
	_apply_settings()

	var timer := Timer.new()
	timer.wait_time = autosave_seconds
	timer.autostart = true
	timer.timeout.connect(save_game.bind(false))
	add_child(timer)

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if is_new:
		save_game(false)
		show_message("Welcome to %s... you are not alone here." % world_name if horror else "Welcome to %s!" % world_name)
	else:
		show_message("Welcome back to %s!" % world_name)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("save_game"):
		save_game(true)


func _notification(what: int) -> void:
	# Save when the window is closed.
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game(false)


func save_game(announce: bool) -> void:
	var data := _save_info.duplicate()
	data.merge({
		"world_seed": world_seed,
		"time_of_day": day_night.time_of_day,
		"player": player.get_save_data(),
		"inventory": inventory.get_save_data(),
		"world": world.get_save_data(),
		"vitals": vitals.get_save_data(),
		"saved_at": Time.get_datetime_string_from_system(),
	}, true)
	var ok: bool = SaveGame.write(world_id, data)
	if announce or not ok:
		show_message("Game saved" if ok else "Could not save the game!")


## Settings the game reads itself (the rest are handled by the Settings autoload).
func _apply_settings() -> void:
	player.set_fov(Settings.get_value("graphics", "fov"))
	world.view_radius = Settings.get_value("graphics", "view_distance")
	_sun.shadow_enabled = Settings.get_value("graphics", "shadows") > 0


## Worn equipment changes how the player looks, runs and jumps, and the
## picked hotbar item shows in their hand.
func _on_inventory_changed() -> void:
	var held: String = inventory.selected_id()
	player.set_held(held, Items.get_info(held))
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
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)  # Also fades while paused.
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.8)


func _build_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20
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
