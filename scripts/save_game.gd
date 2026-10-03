extends RefCounted
## Reads and writes saved worlds. Every world has its own file in
## %APPDATA%\Godot\app_userdata\Nelbrenn\worlds\

const WORLDS_DIR := "user://worlds/"
## The single save file used before there were multiple worlds.
const OLD_SAVE_PATH := "user://savegame.json"
const VERSION := 1

## The world being played. The main menu sets this before starting the game.
static var current_world_id := ""


## All saved worlds, most recently played first. Each is
## {"id", "name", "world_seed", "saved_at"}.
static func list_worlds() -> Array[Dictionary]:
	_migrate_old_save()
	var worlds: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(WORLDS_DIR):
		if not file_name.ends_with(".json"):
			continue
		var id := file_name.get_basename()
		var data := read(id)
		if data.is_empty():
			continue
		worlds.append({
			"id": id,
			"name": String(data.get("name", id)),
			"world_seed": int(data.get("world_seed", 0)),
			"saved_at": String(data.get("saved_at", "")),
		})
	worlds.sort_custom(func(a, b): return a["saved_at"] > b["saved_at"])
	return worlds


## Makes a new, empty world file and returns its id.
static func create_world(world_name: String, world_seed: int) -> String:
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	var base := _file_safe(world_name)
	var id := base
	var n := 2
	while FileAccess.file_exists(_path(id)):
		id = "%s_%d" % [base, n]
		n += 1
	var now := Time.get_datetime_string_from_system()
	write(id, {"name": world_name, "world_seed": world_seed, "created_at": now, "saved_at": now})
	return id


static func exists(id: String) -> bool:
	return id != "" and FileAccess.file_exists(_path(id))


## Returns the world's saved data, or an empty Dictionary if it can't be read.
static func read(id: String) -> Dictionary:
	if not exists(id):
		return {}
	var file := FileAccess.open(_path(id), FileAccess.READ)
	if file == null:
		push_warning("Could not open save file: %s" % error_string(FileAccess.get_open_error()))
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		push_warning("Save file %s is unreadable or from another version." % id)
		return {}
	return data


static func write(id: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(WORLDS_DIR)
	data["version"] = VERSION
	# Write to a temporary file first so a crash mid-save can't corrupt the old save.
	var tmp_path := _path(id) + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp_path, _path(id)) == OK


static func delete(id: String) -> void:
	if exists(id):
		DirAccess.remove_absolute(_path(id))


## Turns typed text into a world seed: empty = random, a number = that number,
## any other text = a seed made from the text (the same text always gives the same world).
static func seed_from_text(text: String) -> int:
	text = text.strip_edges()
	if text == "":
		return randi_range(1, 999_999_999)
	if text.is_valid_int():
		return text.to_int()
	return text.hash()


static func _path(id: String) -> String:
	return WORLDS_DIR + id + ".json"


## Lowercase letters, digits and underscores only, for the file name.
static func _file_safe(text: String) -> String:
	var out := ""
	for ch in text.to_lower():
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	out = out.strip_edges().replace("__", "_").trim_prefix("_").trim_suffix("_")
	return out.left(40) if out != "" else "world"


## Moves a save from before multiple worlds existed into the worlds folder.
static func _migrate_old_save() -> void:
	if not FileAccess.file_exists(OLD_SAVE_PATH):
		return
	var file := FileAccess.open(OLD_SAVE_PATH, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text()) if file else null
	file = null
	if data is Dictionary:
		var id := create_world("My First World", int(data.get("world_seed", 1337)))
		data.merge(read(id))  # adds name and dates, keeps everything else
		data["saved_at"] = String(data.get("saved_at", Time.get_datetime_string_from_system()))
		write(id, data)
	DirAccess.remove_absolute(OLD_SAVE_PATH)
