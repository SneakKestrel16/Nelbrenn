extends Node3D
## The main menu: continue, pick or create a world, change settings, or quit.
## A freshly generated world slowly turns in the background.

const UI := preload("res://scripts/ui.gd")
const SaveGame := preload("res://scripts/save_game.gd")
const WorldScript := preload("res://scripts/world.gd")
const DayNightScript := preload("res://scripts/day_night.gd")
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const GAME_SCENE := "res://scenes/game.tscn"
## Where the downloadable game is published. Released builds check it for updates.
const RELEASES_API := "https://api.github.com/repos/SneakKestrel16/Nelbrenn/releases/latest"
const RELEASES_PAGE := "https://github.com/SneakKestrel16/Nelbrenn/releases/latest"

var _world  # world.gd
var _camera: Camera3D
var _focus := Vector3.ZERO
var _angle := 0.0

var _ui: Control
var _title: Label
var _pages := {}  # page name -> Control
var _current_page := ""
var _continue_button: Button
var _world_list: VBoxContainer
var _name_edit: LineEdit
var _seed_edit: LineEdit
var _settings: Control
var _confirm: ConfirmationDialog
var _update_button: Button
var _pending_delete := ""


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_background()
	_build_ui()
	_show_page("main")
	_check_for_update()


func _process(delta: float) -> void:
	_angle += delta * 0.04
	var pos := _focus + Vector3(cos(_angle), 0, sin(_angle)) * 90.0
	# Stay well above the ground so the camera never dips into a hill.
	pos.y = maxf(_focus.y + 45.0, _world.get_height(pos.x, pos.z) + 30.0)
	_camera.global_position = _camera.global_position.lerp(pos, 1.0 - exp(-delta * 2.0)) if delta > 0.0 else pos
	_camera.look_at(_focus + Vector3(0, 5, 0))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		match _current_page:
			"worlds":
				_show_page("main")
			"create":
				_show_page("worlds")


func _show_page(page: String) -> void:
	_current_page = page
	for page_name in _pages:
		_pages[page_name].visible = page_name == page
	_title.visible = page == "main"
	match page:
		"main":
			var worlds := SaveGame.list_worlds()
			_continue_button.visible = not worlds.is_empty()
			if not worlds.is_empty():
				_continue_button.text = "Continue \"%s\"" % worlds[0]["name"]
				_continue_button.set_meta("world_id", worlds[0]["id"])
		"worlds":
			_refresh_world_list()
		"create":
			_name_edit.text = "World %d" % (SaveGame.list_worlds().size() + 1)
			_seed_edit.text = ""
			_name_edit.grab_focus()
			_name_edit.select_all()
		"settings":
			_settings.open()


func _play(world_id: String) -> void:
	SaveGame.current_world_id = world_id
	get_tree().change_scene_to_file(GAME_SCENE)


func _create_world() -> void:
	var world_name := _name_edit.text.strip_edges()
	if world_name == "":
		world_name = "New World"
	_play(SaveGame.create_world(world_name, SaveGame.seed_from_text(_seed_edit.text)))


func _ask_delete(world: Dictionary) -> void:
	_pending_delete = world["id"]
	_confirm.dialog_text = "Delete \"%s\"?\nThis can't be undone." % world["name"]
	_confirm.popup_centered()


func _refresh_world_list() -> void:
	for child in _world_list.get_children():
		child.queue_free()
	var worlds := SaveGame.list_worlds()
	if worlds.is_empty():
		var empty := UI.label("No worlds yet. Create one to start exploring!", 18)
		empty.modulate = UI.SOFT_TEXT_COLOR
		_world_list.add_child(empty)
	for world in worlds:
		var row := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 0)
		info.add_child(UI.label(world["name"], 22))
		var details := UI.label("Seed %d  •  Last played %s" % [world["world_seed"], _pretty_date(world["saved_at"])], 15)
		details.modulate = UI.SOFT_TEXT_COLOR
		info.add_child(details)
		row.add_child(info)
		row.add_child(UI.button("Play", _play.bind(world["id"]), 110))
		row.add_child(UI.button("Delete", _ask_delete.bind(world), 110))
		_world_list.add_child(row)
		_world_list.add_child(HSeparator.new())


## "2026-10-03T14:22:05" -> "2026-10-03 14:22"
static func _pretty_date(text: String) -> String:
	return text.replace("T", " ").left(16) if text != "" else "never"


func _build_background() -> void:
	var env := WorldEnvironment.new()
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = Settings.get_value("graphics", "shadows") > 0
	sun.directional_shadow_max_distance = 250.0
	add_child(sun)
	var day_night = DayNightScript.new()
	day_night.sun = sun
	day_night.world_environment = env
	day_night.time_of_day = 0.31  # Golden morning light.
	day_night.day_length_seconds = 3000.0
	add_child(day_night)

	_world = WorldScript.new()
	_world.world_seed = randi()
	_world.view_radius = Settings.get_value("graphics", "view_distance")
	add_child(_world)
	_focus = _world.find_spawn_point()
	var focus_node := Node3D.new()
	add_child(focus_node)
	focus_node.global_position = _focus
	_world.target = focus_node
	_world.generate_around(_focus, true)

	_camera = Camera3D.new()
	_camera.far = 800.0
	_camera.fov = 60.0
	add_child(_camera)
	_camera.current = true
	_process(0.0)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.theme = UI.make_theme()
	layer.add_child(_ui)

	_title = UI.title("Nelbrenn", 96)
	_title.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_title.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_title.offset_top = 70.0
	_title.add_theme_constant_override("outline_size", 16)
	_ui.add_child(_title)

	# Main page
	var main := _new_page("main")
	_update_button = UI.button("Update available!", func(): OS.shell_open(RELEASES_PAGE))
	_update_button.add_theme_color_override("font_color", UI.HIGHLIGHT_COLOR)
	_update_button.visible = false
	main.add_child(_update_button)
	_continue_button = UI.button("Continue", func(): _play(_continue_button.get_meta("world_id")))
	main.add_child(_continue_button)
	main.add_child(UI.button("Worlds", _show_page.bind("worlds")))
	main.add_child(UI.button("Settings", _show_page.bind("settings")))
	if not OS.has_feature("web"):  # A browser tab can't quit itself.
		main.add_child(UI.button("Quit", _quit))

	var version := UI.label(_version(), 15)
	version.modulate = UI.SOFT_TEXT_COLOR
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -12.0
	version.offset_bottom = -8.0
	_ui.add_child(version)

	# World list
	var worlds := _new_page("worlds")
	worlds.add_child(UI.title("Your Worlds", 34))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	worlds.add_child(scroll)
	_world_list = VBoxContainer.new()
	_world_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_world_list)
	var world_buttons := HBoxContainer.new()
	world_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	world_buttons.add_child(UI.button("Create New World", _show_page.bind("create"), 260))
	world_buttons.add_child(UI.button("Back", _show_page.bind("main"), 160))
	worlds.add_child(world_buttons)

	# Create a world
	var create := _new_page("create")
	create.add_child(UI.title("Create New World", 34))
	create.add_child(UI.label("World name"))
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(480, 44)
	_name_edit.max_length = 40
	_name_edit.text_submitted.connect(func(_text): _create_world())
	create.add_child(_name_edit)
	create.add_child(UI.label("Seed"))
	_seed_edit = LineEdit.new()
	_seed_edit.custom_minimum_size = Vector2(480, 44)
	_seed_edit.placeholder_text = "Leave empty for a random world"
	_seed_edit.text_submitted.connect(func(_text): _create_world())
	create.add_child(_seed_edit)
	var hint := UI.label("The same seed always makes the same world,\nso you can share good ones with friends.", 16)
	hint.modulate = UI.SOFT_TEXT_COLOR
	create.add_child(hint)
	var create_buttons := HBoxContainer.new()
	create_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	create_buttons.add_child(UI.button("Create World", _create_world, 220))
	create_buttons.add_child(UI.button("Back", _show_page.bind("worlds"), 160))
	create.add_child(create_buttons)

	# Settings
	_settings = SettingsMenuScript.new()
	_settings.closed.connect(_show_page.bind("main"))
	_ui.add_child(_settings)
	_pages["settings"] = _settings

	_confirm = ConfirmationDialog.new()
	_confirm.title = "Delete world"
	_confirm.ok_button_text = "Delete"
	_confirm.theme = _ui.theme
	_confirm.confirmed.connect(func():
		SaveGame.delete(_pending_delete)
		_refresh_world_list()
	)
	_ui.add_child(_confirm)


## A full-screen page with a centred panel; returns the panel's column.
func _new_page(page_name: String) -> VBoxContainer:
	var page := Control.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(page)
	_pages[page_name] = page
	var column := UI.centered_panel(page)
	if page_name == "main":
		# Sit a little below the centre, under the big title.
		column.get_parent().get_parent().offset_top = 140.0
	return column


## "build-12" for published builds (set by the GitHub build), "dev" when run from the editor.
static func _version() -> String:
	var version: String = ProjectSettings.get_setting("application/config/version", "")
	return version if version != "" else "dev"


static func _build_number(version: String) -> int:
	return version.trim_prefix("build-").to_int() if version.begins_with("build-") else 0


## Downloaded builds ask GitHub for the newest release and offer it if it's newer.
## (The browser version is always the newest, so it doesn't need to check.)
func _check_for_update() -> void:
	var current := _build_number(_version())
	if current == 0 or OS.has_feature("web"):
		return
	var request := HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(func(result: int, code: int, _headers, body: PackedByteArray) -> void:
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			return
		var data = JSON.parse_string(body.get_string_from_utf8())
		if data is Dictionary:
			var latest := String(data.get("tag_name", ""))
			if _build_number(latest) > current:
				_update_button.text = "Update available (%s) - Download" % latest
				_update_button.visible = true
	)
	request.request(RELEASES_API, ["User-Agent: Nelbrenn"])


func _quit() -> void:
	Settings.save()
	get_tree().quit()
