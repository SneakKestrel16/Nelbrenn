extends CanvasLayer
## The pause menu. Esc opens and closes it; the game stops while it's open.

const UI := preload("res://scripts/ui.gd")
const SettingsMenuScript := preload("res://scripts/settings_menu.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var game  # game.gd

var _root: Control
var _main_page: Control
var _settings: Control
var _world_label: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS  # Keeps working while the game is paused.

	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = UI.make_theme()
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	_main_page = Control.new()
	_main_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_main_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_main_page)
	var column := UI.centered_panel(_main_page)
	column.add_child(UI.title("Paused"))
	_world_label = UI.label("", 17)
	_world_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_label.modulate = UI.SOFT_TEXT_COLOR
	column.add_child(_world_label)
	column.add_child(UI.button("Resume", close))
	column.add_child(UI.button("Settings", _open_settings))
	column.add_child(UI.button("Save Game", func(): game.save_game(true)))
	column.add_child(UI.button("Save & Quit to Main Menu", _quit_to_menu))
	column.add_child(UI.button("Save & Quit to Desktop", _quit_to_desktop))

	_settings = SettingsMenuScript.new()
	_settings.visible = false
	_settings.closed.connect(func(): _main_page.visible = true)
	_root.add_child(_settings)

	visible = false


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_main_page.visible = true
	_settings.visible = false
	_world_label.text = "%s  •  Seed %d" % [game.world_name, game.world_seed]
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if visible:
			close()
		else:
			open()


func _open_settings() -> void:
	_main_page.visible = false
	_settings.open()


func _quit_to_menu() -> void:
	game.save_game(false)
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _quit_to_desktop() -> void:
	game.save_game(false)
	Settings.save()
	get_tree().quit()
