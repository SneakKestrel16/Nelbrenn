extends RefCounted
## Reads and writes the save file. On Windows it lives at
## %APPDATA%\Godot\app_userdata\Nelbrenn\savegame.json

const SAVE_PATH := "user://savegame.json"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Returns the saved data, or an empty Dictionary if there is no usable save.
static func read() -> Dictionary:
	if not exists():
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_warning("Could not open save file: %s" % error_string(FileAccess.get_open_error()))
		return {}
	var data = JSON.parse_string(file.get_as_text())
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		push_warning("Save file is unreadable or from another version, starting fresh.")
		return {}
	return data


static func write(data: Dictionary) -> bool:
	data["version"] = VERSION
	# Write to a temporary file first so a crash mid-save can't corrupt the old save.
	var tmp_path := SAVE_PATH + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write save file: %s" % error_string(FileAccess.get_open_error()))
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(tmp_path, SAVE_PATH) == OK


static func delete() -> void:
	if exists():
		DirAccess.remove_absolute(SAVE_PATH)
