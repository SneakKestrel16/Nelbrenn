extends Node
## Runs horror mode (only added in horror worlds): spawns and removes the
## monsters (see monster.gd), and handles the atmosphere: a dark vignette,
## a droning hum, distant howls and creaks at night, a heartbeat when
## something is close, a red flash when you're hurt and the Watcher's jump
## scare.

const MonsterScript := preload("res://scripts/monster.gd")
const Sounds := preload("res://scripts/horror_sounds.gd")

const DESPAWN_DISTANCE := 110.0
const GRACE_SECONDS := 45.0  ## No monsters right after starting or waking up.

var world  # world.gd
var player  # player.gd
var vitals  # vitals.gd
var day_night  # day_night.gd
var game  # game.gd, for messages

var _monsters: Array = []
var _rng := RandomNumberGenerator.new()
var _spawn_timer := 3.0
var _grace := GRACE_SECONDS
var _watcher_cooldown := 60.0
var _stinger_timer := 25.0
var _heart_timer := 0.0
var _night_announced := false

var _vignette: TextureRect
var _flash: ColorRect
var _drain: ColorRect
var _scare: Control
var _scare_time := 0.0
var _drone: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _sounds := {}


func _ready() -> void:
	_rng.randomize()
	_build_overlay()
	_sounds = {
		"boom": Sounds.boom(), "screech": Sounds.screech(), "heartbeat": Sounds.heartbeat(),
		"howl": Sounds.howl(), "creak": Sounds.creak(), "whisper": Sounds.whisper(),
	}
	_drone = _player_2d(Sounds.drone(), "Ambience")
	_drone.play()
	_heart = _player_2d(_sounds["heartbeat"], "Effects")
	_sting = _player_2d(null, "Effects")
	vitals.damaged.connect(_on_damaged)
	vitals.fainted.connect(_on_fainted)
	_night_announced = darkness() > 0.5


## 0 in daylight, 1 in the middle of the night.
func darkness() -> float:
	return 1.0 - day_night.get_daylight()


func _process(delta: float) -> void:
	var dark := darkness()
	_vignette.modulate.a = lerpf(0.5, 0.9, dark)
	_drone.volume_db = linear_to_db(lerpf(0.2, 0.8, dark))
	_flash.color.a = move_toward(_flash.color.a, 0.0, delta * 1.2)
	_drain.color.a = move_toward(_drain.color.a, 0.0, delta * 0.8)
	if _scare_time > 0.0:
		_scare_time -= delta
		_scare.modulate.a = clampf(_scare_time / 0.25, 0.0, 1.0)
		_scare.visible = _scare_time > 0.0
		_scare.queue_redraw()

	_grace -= delta
	_watcher_cooldown -= delta
	_announce(dark)
	_monsters = _monsters.filter(func(m): return is_instance_valid(m))
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 2.0
		_manage(dark)
	_heartbeat(delta)
	_stingers(delta, dark)


func _announce(dark: float) -> void:
	if dark > 0.5 and not _night_announced:
		_night_announced = true
		game.show_message("Night is falling... keep your lantern close.")
	elif dark < 0.2 and _night_announced:
		_night_announced = false
		game.show_message("The sun rises. The creatures crawl back into the dark.")


# --- Monsters ----------------------------------------------------------------------

func _manage(dark: float) -> void:
	for m in _monsters:
		if m.leaving:
			continue
		if m.global_position.distance_to(player.global_position) > DESPAWN_DISTANCE:
			m.queue_free()
		elif dark < 0.35 and m.kind != "mimic":
			m.leave()  # Daybreak.
	if _grace > 0.0:
		return
	var counts := {"watcher": 0, "crawler": 0, "shade": 0, "mimic": 0}
	for m in _monsters:
		if is_instance_valid(m) and not m.leaving:
			counts[m.kind] += 1
	if dark > 0.6:
		if counts["watcher"] == 0 and _watcher_cooldown <= 0.0 and _rng.randf() < 0.3:
			_spawn("watcher")
		if counts["crawler"] < 2 and _rng.randf() < 0.25:
			_spawn("crawler")
		if counts["shade"] < (3 if dark > 0.9 else 1) and _rng.randf() < 0.25:
			_spawn("shade")
	if counts["mimic"] < (2 if dark > 0.5 else 1) and _rng.randf() < 0.12:
		_spawn("mimic")


func _spawn(kind: String) -> void:
	var look: Vector3 = player.get_look_direction()
	for attempt in 8:
		var dir: Vector3
		var dist: float
		match kind:
			"watcher":  # Somewhere behind you.
				dir = (-look).rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2))
				dist = _rng.randf_range(40.0, 55.0)
			"mimic":  # Somewhere ahead, where you'll come across it.
				dir = look.rotated(Vector3.UP, _rng.randf_range(-1.2, 1.2))
				dist = _rng.randf_range(25.0, 45.0)
			"shade":
				dir = Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
				dist = _rng.randf_range(30.0, 45.0)
			_:
				dir = Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
				dist = _rng.randf_range(45.0, 65.0)
		var pos: Vector3 = player.global_position + dir * dist
		pos.y = world.get_height(pos.x, pos.z)
		if pos.y < 1.0 or world.near_fire(pos, 4.0):
			continue
		if kind == "watcher" and can_see(pos + Vector3.UP * 2.6):
			continue
		var monster := MonsterScript.new()
		monster.kind = kind
		monster.world = world
		monster.player = player
		monster.vitals = vitals
		monster.director = self
		add_child(monster)
		monster.global_position = pos
		_monsters.append(monster)
		return


## Is the player looking at `point`? It has to be roughly in the direction
## the camera faces *from the player* (so something creeping up behind your
## character still counts as unseen, even though it's on screen), on screen,
## and not hidden behind the ground or a tree.
func can_see(point: Vector3) -> bool:
	var camera: Camera3D = player.get_camera()
	if camera.is_position_behind(point):
		return false
	var to_point: Vector3 = point - player.global_position
	to_point.y = 0.0
	if to_point.length() > 0.5 and to_point.normalized().dot(player.get_look_direction()) < 0.55:
		return false
	var screen := camera.unproject_position(point)
	if not camera.get_viewport().get_visible_rect().grow(-20.0).has_point(screen):
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, point)
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## The Watcher went away: after an attack it stays away longer.
func watcher_gone(attacked: bool) -> void:
	_watcher_cooldown = _rng.randf_range(80.0, 120.0) if attacked else _rng.randf_range(40.0, 70.0)


func on_attack(monster) -> void:
	if monster.kind == "watcher":
		_scare_time = 0.7
		_scare.visible = true
		play_sting("screech")
		player.shake(1.2)
	else:
		player.shake(0.5)


## A Shade is draining you: the screen darkens.
func drain(delta: float) -> void:
	_drain.color.a = minf(_drain.color.a + delta * 1.5, 0.6)


func play_sting(sound: String) -> void:
	_sting.stream = _sounds[sound]
	_sting.play()


func _on_damaged(amount: float) -> void:
	_flash.color.a = minf(_flash.color.a + amount * 0.015, 0.55)


func _on_fainted() -> void:
	for m in _monsters:
		if is_instance_valid(m):
			m.queue_free()
	_monsters.clear()
	_grace = GRACE_SECONDS
	_flash.color.a = 0.0
	_drain.color.a = 0.0


# --- Sound ------------------------------------------------------------------------

## A heartbeat that speeds up the closer the nearest monster is.
func _heartbeat(delta: float) -> void:
	var nearest := INF
	for m in _monsters:
		if is_instance_valid(m) and m.threatening:
			nearest = minf(nearest, m.global_position.distance_to(player.global_position))
	_heart_timer -= delta
	if nearest < 20.0 and _heart_timer <= 0.0:
		_heart_timer = lerpf(0.4, 1.3, nearest / 20.0)
		_heart.volume_db = lerpf(0.0, -12.0, nearest / 20.0)
		_heart.play()


## Now and then at night: a howl, creak or whisper from somewhere out there.
func _stingers(delta: float, dark: float) -> void:
	_stinger_timer -= delta
	if _stinger_timer > 0.0:
		return
	_stinger_timer = _rng.randf_range(18.0, 45.0)
	if dark < 0.5:
		return
	var sound := AudioStreamPlayer3D.new()
	sound.stream = _sounds[["howl", "creak", "whisper", "howl"][_rng.randi() % 4]]
	sound.bus = "Ambience"
	sound.unit_size = 25.0
	sound.max_distance = 120.0
	add_child(sound)
	var dir := Vector3.FORWARD.rotated(Vector3.UP, _rng.randf() * TAU)
	sound.global_position = player.global_position + dir * _rng.randf_range(25.0, 40.0)
	sound.finished.connect(sound.queue_free)
	sound.play()
	if sound.stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		get_tree().create_timer(3.0).timeout.connect(sound.queue_free)


func _player_2d(stream: AudioStream, bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	add_child(p)
	return p


# --- Screen effects ------------------------------------------------------------------

func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 2  # Under the HUD and menus.
	add_child(layer)

	# Dark edges around the screen.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0, 0, 0, 0))
	gradient.set_color(1, Color(0, 0, 0, 1))
	gradient.add_point(0.45, Color(0, 0, 0, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.05, 0.5)
	_vignette = TextureRect.new()
	_vignette.texture = texture
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_vignette)

	_drain = _full_rect(layer, Color(0.05, 0.0, 0.08, 0.0))
	_flash = _full_rect(layer, Color(0.6, 0.0, 0.0, 0.0))

	# The Watcher's face, filling the screen for a moment.
	_scare = Control.new()
	_scare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scare.visible = false
	_scare.draw.connect(_draw_scare)
	layer.add_child(_scare)


func _full_rect(layer: CanvasLayer, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	return rect


func _draw_scare() -> void:
	var size := _scare.size
	var c := size * 0.5 + Vector2(randf_range(-8, 8), randf_range(-8, 8))  # Shudders.
	var h := size.y * 0.95
	_scare.draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.85))
	var face := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		face.append(c + Vector2(cos(a) * h * 0.32, sin(a) * h * 0.5))
	_scare.draw_colored_polygon(face, Color(0.78, 0.76, 0.72))
	for side in [-1.0, 1.0]:
		var eye := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			eye.append(c + Vector2(side * h * 0.11, -h * 0.1) + Vector2(cos(a) * h * 0.055, sin(a) * h * 0.09))
		_scare.draw_colored_polygon(eye, Color.BLACK)
	var mouth := PackedVector2Array()
	for i in 12:
		var a := TAU * i / 12.0
		mouth.append(c + Vector2(0, h * 0.2) + Vector2(cos(a) * h * 0.06, sin(a) * h * 0.14))
	_scare.draw_colored_polygon(mouth, Color.BLACK)
