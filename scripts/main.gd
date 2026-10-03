extends Node3D
## Entry point: sets up controls, sky, sun, the world and the player.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const DayNightScript := preload("res://scripts/day_night.gd")

## Change this to get a completely different world.
@export var world_seed: int = 1337

var world  # world.gd
var player  # player.gd


func _ready() -> void:
	_setup_input()

	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	var day_night := DayNightScript.new()
	day_night.name = "DayNight"
	day_night.sun = sun
	day_night.world_environment = env
	add_child(day_night)

	world = WorldScript.new()
	world.name = "World"
	world.world_seed = world_seed
	add_child(world)

	player = PlayerScript.new()
	player.name = "Player"
	add_child(player)
	player.global_position = world.find_spawn_point()

	world.target = player
	world.generate_around(player.global_position, true)


func _setup_input() -> void:
	_add_keys("move_forward", [KEY_W, KEY_UP])
	_add_keys("move_back", [KEY_S, KEY_DOWN])
	_add_keys("move_left", [KEY_A, KEY_LEFT])
	_add_keys("move_right", [KEY_D, KEY_RIGHT])
	_add_keys("jump", [KEY_SPACE])
	_add_keys("sprint", [KEY_SHIFT])
	_add_keys("release_mouse", [KEY_ESCAPE])


func _add_keys(action: StringName, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
