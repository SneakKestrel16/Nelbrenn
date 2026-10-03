extends Node
## Player settings (audio, graphics, controls and key bindings), stored in
## %APPDATA%\Godot\app_userdata\Nelbrenn\settings.cfg
##
## Loaded at startup as the "Settings" autoload, so any script can call e.g.
## Settings.get_value("graphics", "fov"). Emits `changed` when anything changes.

signal changed

const PATH := "user://settings.cfg"

const DEFAULTS := {
	"audio": {"master": 0.8, "music": 0.7, "effects": 0.8, "ambience": 0.6},
	"graphics": {
		"fullscreen": false, "vsync": true, "max_fps": 0, "render_scale": 1.0,
		"msaa": 2, "shadows": 2, "view_distance": 5, "fov": 70.0,
	},
	"controls": {"mouse_sensitivity": 1.0, "invert_y": false},
}

## Volume setting -> audio bus.
const AUDIO_BUSES := {"master": "Master", "music": "Music", "effects": "Effects", "ambience": "Ambience"}

## Actions players can rebind: [action, name shown in settings, default keys].
const ACTIONS := [
	["move_forward", "Move forward", [KEY_W, KEY_UP]],
	["move_back", "Move back", [KEY_S, KEY_DOWN]],
	["move_left", "Move left", [KEY_A, KEY_LEFT]],
	["move_right", "Move right", [KEY_D, KEY_RIGHT]],
	["jump", "Jump / swim up", [KEY_SPACE]],
	["sprint", "Sprint", [KEY_SHIFT]],
	["inventory", "Inventory", [KEY_I, KEY_TAB]],
	["save_game", "Quick save", [KEY_F5]],
]
## Esc always opens the pause menu and can't be rebound, so you can never lock yourself out.
const PAUSE_KEY := KEY_ESCAPE
const SLOTS_PER_ACTION := 2

var _values := {}
var _bindings := {}  # action -> [physical keycode, physical keycode], 0 = unbound
var _click_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_audio_buses()
	_click_player = AudioStreamPlayer.new()
	_click_player.stream = _make_click_sound()
	_click_player.bus = "Effects"
	add_child(_click_player)
	_load()
	for section in _values:
		for key in _values[section]:
			_apply(section, key)
	_apply_bindings()


func get_value(section: String, key: String) -> Variant:
	return _values[section][key]


func set_value(section: String, key: String, value: Variant) -> void:
	if _values[section][key] == value:
		return
	_values[section][key] = value
	_apply(section, key)
	changed.emit()


func reset_section(section: String) -> void:
	_values[section] = DEFAULTS[section].duplicate()
	for key in _values[section]:
		_apply(section, key)
	if section == "controls":
		_bindings = _default_bindings()
		_apply_bindings()
	changed.emit()


## The key in `slot` (0 or 1) for `action`, or 0 if there is none.
func get_binding(action: String, slot: int) -> int:
	return _bindings[action][slot]


## Binds `keycode` to `action`. If another action used that key, it loses it.
## Returns the name of the action the key was taken from, or "".
func set_binding(action: String, slot: int, keycode: int) -> String:
	var taken_from := ""
	for entry in ACTIONS:
		var keys: Array = _bindings[entry[0]]
		for i in keys.size():
			if keycode != 0 and keys[i] == keycode and not (entry[0] == action and i == slot):
				keys[i] = 0
				taken_from = entry[1]
	_bindings[action][slot] = keycode
	_apply_bindings()
	changed.emit()
	return taken_from


static func key_name(keycode: int) -> String:
	if keycode == 0:
		return "—"
	return OS.get_keycode_string(DisplayServer.keyboard_get_keycode_from_physical(keycode))


func play_click() -> void:
	_click_player.play()


func save() -> void:
	var cfg := ConfigFile.new()
	for section in _values:
		for key in _values[section]:
			cfg.set_value(section, key, _values[section][key])
	for action in _bindings:
		cfg.set_value("keybinds", action, _bindings[action])
	cfg.save(PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()


func _load() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH)  # A missing file just means everything stays at its default.
	for section in DEFAULTS:
		_values[section] = {}
		for key in DEFAULTS[section]:
			var default = DEFAULTS[section][key]
			var value = cfg.get_value(section, key, default)
			if typeof(value) != typeof(default):
				value = type_convert(value, typeof(default))
			_values[section][key] = value
	_bindings = _default_bindings()
	for action in _bindings:
		var saved = cfg.get_value("keybinds", action) if cfg.has_section_key("keybinds", action) else null
		if saved is Array and saved.size() == SLOTS_PER_ACTION:
			_bindings[action] = [int(saved[0]), int(saved[1])]


func _default_bindings() -> Dictionary:
	var result := {}
	for entry in ACTIONS:
		var keys: Array = entry[2].duplicate()
		keys.resize(SLOTS_PER_ACTION)
		result[entry[0]] = keys.map(func(k): return 0 if k == null else k)
	return result


func _apply_bindings() -> void:
	var all := {"pause": [PAUSE_KEY]}
	all.merge(_bindings)
	for action in all:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for keycode in all[action]:
			if keycode != 0:
				var ev := InputEventKey.new()
				ev.physical_keycode = keycode
				InputMap.action_add_event(action, ev)


## Applies a setting that the engine handles directly. The rest (FOV, view
## distance, mouse sensitivity, shadows on/off) are read by the game itself.
func _apply(section: String, key: String) -> void:
	var value = _values[section][key]
	if section == "audio":
		var bus := AudioServer.get_bus_index(AUDIO_BUSES[key])
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.0001)))
		AudioServer.set_bus_mute(bus, value <= 0.001)
		return
	if section != "graphics":
		return
	match key:
		"fullscreen":
			var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED
			if DisplayServer.window_get_mode() != mode:
				DisplayServer.window_set_mode(mode)
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if value else DisplayServer.VSYNC_DISABLED)
		"max_fps":
			Engine.max_fps = value
		"render_scale":
			get_tree().root.scaling_3d_scale = value
		"msaa":
			var msaa := {0: Viewport.MSAA_DISABLED, 2: Viewport.MSAA_2X, 4: Viewport.MSAA_4X, 8: Viewport.MSAA_8X}
			get_tree().root.msaa_3d = msaa.get(value, Viewport.MSAA_2X)
		"shadows":
			RenderingServer.directional_shadow_atlas_set_size(4096 if value >= 2 else 2048, true)


func _setup_audio_buses() -> void:
	for bus_name in AUDIO_BUSES.values():
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")


## A short, soft "tick" for menu buttons, made in code so there's no sound file.
func _make_click_sound() -> AudioStreamWAV:
	var rate := 22050
	var length := 0.06
	var samples := int(rate * length)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / rate
		var pitch := lerpf(900.0, 500.0, t / length)
		var s := sin(TAU * pitch * t) * exp(-t * 70.0) * 0.35
		data.encode_s16(i * 2, int(s * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.data = data
	return wav
