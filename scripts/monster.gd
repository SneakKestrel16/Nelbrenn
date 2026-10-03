extends Node3D
## One monster in a horror world. Spawned and removed by horror.gd.
## `kind` picks how it looks and behaves:
##
##   "watcher"  Tall, pale and thin. Only moves while you're NOT looking at
##              it, and slips around behind you. If it reaches you: a jump
##              scare and heavy damage. Keep it in view long enough and it
##              gives up and vanishes. One at a time, at night.
##   "crawler"  Fast, blind, many-legged. Hunts by sound: sprinting,
##              chopping and mining can be heard from far away, walking only
##              close by, standing still not at all. Can't swim.
##   "shade"    A floating shadow that drains your health while it's close.
##              Backs away from a held lantern.
##   "mimic"    Looks exactly like a berry bush (but has no "Pick" prompt).
##              Walk up to it and it jumps up on legs and chases you for a
##              while, then hides again. Day or night.
##
## No monster will go near a campfire.

const LowPoly := preload("res://scripts/low_poly.gd")
const Sounds := preload("res://scripts/horror_sounds.gd")

const INFO := {
	"watcher": {"name": "the Watcher", "damage": 35.0},
	"crawler": {"name": "a Crawler", "damage": 12.0},
	"shade": {"name": "a Shade", "damage": 6.0},  # Per second while close.
	"mimic": {"name": "a Mimic", "damage": 18.0},
}
const WATER_LEVEL := 0.0

var kind := "crawler"
var world  # world.gd
var player  # player.gd
var vitals  # vitals.gd
var director  # horror.gd

## True once it has started to go away (sinking into the ground / fading).
var leaving := false
## Is it currently a danger? (A hidden Mimic isn't, yet.)
var threatening := true

var _state := ""
var _target := Vector3.ZERO
var _timer := 0.0
var _attack_cooldown := 0.0
var _seen_time := 0.0
var _unseen_time := 0.0
var _spotted := false
var _phase := 0.0
var _hover := 0.0  ## Height above the ground.
var _rng := RandomNumberGenerator.new()
var _sound: AudioStreamPlayer3D
var _material: StandardMaterial3D
var _body: Node3D
var _legs: Array[Node3D] = []
var _extra: Node3D  ## Shade eyes / Mimic mouth.


func _ready() -> void:
	_rng.randomize()
	_material = LowPoly.make_material()
	_body = Node3D.new()
	add_child(_body)
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = "Effects"
	_sound.unit_size = 6.0
	_sound.max_distance = 60.0
	add_child(_sound)
	match kind:
		"watcher":
			_build_watcher()
			_sound.stream = Sounds.whisper()
			_sound.volume_db = -14.0
			_sound.play()
		"crawler":
			_build_crawler()
			_sound.stream = Sounds.skitter()
			_state = "wander"
		"shade":
			_build_shade()
			_hover = 0.6
			_sound.stream = Sounds.hum()
			_sound.volume_db = -4.0
			_sound.play()
		"mimic":
			_build_mimic()
			_state = "hidden"
			threatening = false
	global_position.y = _ground(global_position) + _hover


func _process(delta: float) -> void:
	if leaving or player == null:
		return
	_attack_cooldown -= delta
	_phase += delta
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	match kind:
		"watcher":
			_watcher(delta, dist)
		"crawler":
			_crawler(delta, dist)
		"shade":
			_shade(delta, dist, to_player)
		"mimic":
			_mimic(delta, dist)


## Sinks into the ground (or fades away) and disappears.
func leave() -> void:
	if leaving:
		return
	leaving = true
	threatening = false
	_sound.stop()
	var tween := create_tween()
	if kind == "shade":
		tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 1.2)
	else:
		tween.tween_property(self, "position:y", position.y - 3.5, 1.5).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)


# --- Behaviour ------------------------------------------------------------------

func _watcher(delta: float, dist: float) -> void:
	_face(player.global_position, 1.0)  # It always stares at you.
	var seen: bool = director.can_see(global_position + Vector3.UP * 2.6)
	if seen:
		_seen_time += delta
		_sound.volume_db = move_toward(_sound.volume_db, 2.0, delta * 20.0)
		if not _spotted:
			_spotted = true
			director.play_sting("boom")
		if _seen_time > 5.0:
			director.watcher_gone(false)
			leave()
		return
	_sound.volume_db = move_toward(_sound.volume_db, -14.0, delta * 10.0)
	_unseen_time += delta
	if dist > 22.0 and _unseen_time > 5.0:
		_creep_behind()
	else:
		_move_toward(player.global_position, 4.2, delta)
	if dist < 1.8:
		_attack(INFO[kind]["damage"])
		director.watcher_gone(true)
		leave()


## Reappears somewhere behind the player, out of sight.
func _creep_behind() -> void:
	_unseen_time = 0.0
	var back: Vector3 = -player.get_look_direction()
	for attempt in 6:
		var dir := back.rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9))
		var pos: Vector3 = player.global_position + dir * _rng.randf_range(12.0, 17.0)
		pos.y = _ground(pos)
		if pos.y > WATER_LEVEL + 0.3 and not world.near_fire(pos, 2.0) and not director.can_see(pos + Vector3.UP * 2.6):
			global_position = pos
			return


func _crawler(delta: float, dist: float) -> void:
	var noise: float = player.get_noise()
	if dist < noise and not world.near_fire(player.global_position):
		_target = player.global_position
		_state = "hunt"
	var moved := false
	if _state == "hunt":
		moved = _move_toward(_target, 9.5, delta)
		var to_target := _target - global_position
		to_target.y = 0.0
		if to_target.length() < 1.5 or not moved:
			_state = "wander"
			_timer = 0.0
	else:
		_timer -= delta
		if _timer <= 0.0:
			_timer = _rng.randf_range(2.5, 6.0)
			_target = global_position + Vector3(_rng.randf_range(-12.0, 12.0), 0, _rng.randf_range(-12.0, 12.0))
		moved = _move_toward(_target, 2.2, delta)
	if dist < 1.8:
		_attack(INFO[kind]["damage"])
	# Legs scurry; the skitter gets faster when it's hunting.
	var speed := 9.5 if _state == "hunt" else 2.2
	for i in _legs.size():
		_legs[i].rotation.y = sin(_phase * speed * 2.2 + i * 2.1) * 0.45 if moved else 0.0
	if moved and not _sound.playing:
		_sound.play()
	elif not moved and _sound.playing:
		_sound.stop()
	_sound.pitch_scale = 1.3 if _state == "hunt" else 0.8


func _shade(delta: float, dist: float, to_player: Vector3) -> void:
	_hover = 0.6 + sin(_phase * 1.5) * 0.2
	_face(player.global_position, 3.0 * delta)
	var afraid: bool = (player.has_light() and dist < 14.0) or world.near_fire(global_position, 3.0)
	if afraid:
		var away := global_position - to_player.normalized() * 3.0
		_move_toward(away, 4.5, delta, false)
		_extra.visible = fmod(_phase, 0.3) < 0.15  # Eyes flicker when it flinches.
	else:
		_extra.visible = true
		if dist > 1.5:
			_move_toward(player.global_position, 2.6, delta, false)
		if dist < 3.2:
			vitals.hurt(INFO[kind]["damage"] * delta, INFO[kind]["name"])
			director.drain(delta)
	global_position.y = _ground(global_position) + _hover


func _mimic(delta: float, dist: float) -> void:
	if _state == "hidden":
		if dist < 4.5 and not world.near_fire(global_position):
			_state = "chase"
			threatening = true
			_timer = 10.0
			_sound.stream = Sounds.roar()
			_sound.volume_db = 4.0
			_sound.play()
			player.shake(0.6)
			_show_mimic(true)
		return
	_timer -= delta
	_face(player.global_position, 8.0 * delta)
	if _move_toward(player.global_position, 8.0, delta):
		for i in _legs.size():
			_legs[i].rotation.x = sin(_phase * 16.0 + i * PI * 0.5) * 0.5
	if dist < 1.9:
		_attack(INFO[kind]["damage"])
	if _timer <= 0.0 or dist > 35.0:
		_state = "hidden"
		threatening = false
		_show_mimic(false)


func _show_mimic(revealed: bool) -> void:
	var tween := create_tween().set_parallel()
	tween.tween_property(_body, "position:y", 0.85 if revealed else 0.0, 0.3)
	tween.tween_property(_extra, "scale", Vector3.ONE if revealed else Vector3.ONE * 0.01, 0.3)
	for leg in _legs:
		tween.tween_property(leg, "scale", Vector3.ONE if revealed else Vector3(1, 0.01, 1), 0.3)


func _attack(damage: float) -> void:
	if _attack_cooldown > 0.0:
		return
	_attack_cooldown = 1.2
	vitals.hurt(damage, INFO[kind]["name"])
	director.on_attack(self)


# --- Movement ---------------------------------------------------------------------

func _ground(pos: Vector3) -> float:
	return world.get_height(pos.x, pos.z)


## Walks towards `point` (flat), staying out of campfire light and, with
## `avoid_water`, out of the water. Returns false if it couldn't move.
func _move_toward(point: Vector3, speed: float, delta: float, avoid_water := true) -> bool:
	var dir := point - global_position
	dir.y = 0.0
	if dir.length() < 0.05:
		return false
	var step := minf(speed * delta, dir.length())
	dir = dir.normalized()
	var next := global_position + dir * step
	var ground := _ground(next)
	if avoid_water and ground < WATER_LEVEL + 0.2:
		return false
	if world.near_fire(next) and not world.near_fire(global_position):
		return false
	next.y = ground + _hover
	global_position = next
	if kind != "watcher":
		_face(global_position + dir, 10.0 * delta)
	return true


## Turns to face `point`; `weight` 1 turns instantly.
func _face(point: Vector3, weight: float) -> void:
	var dir := point - global_position
	if Vector2(dir.x, dir.z).length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), clampf(weight, 0.0, 1.0))


# --- Models (all face -Z) -----------------------------------------------------------

func _mesh_part(parent: Node3D, build: Callable, material: Material = null) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	build.call(st)
	var part := MeshInstance3D.new()
	part.mesh = st.commit()
	part.material_override = material if material else _material
	parent.add_child(part)
	return part


func _glow_material(color: Color) -> StandardMaterial3D:
	var mat := LowPoly.make_material()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


func _build_watcher() -> void:
	var pale := Color(0.80, 0.78, 0.74)
	var black := Color(0.02, 0.015, 0.015)
	_material.emission_enabled = true  # Faintly visible even in the dark.
	_material.emission = Color(0.07, 0.07, 0.07)
	var build := func(st: SurfaceTool) -> void:
		for side in [-1.0, 1.0]:
			LowPoly.add_limb(st, Vector3(side * 0.12, -0.05, 0), Vector3(side * 0.1, 1.38, 0), 0.06, 0.08, 5, pale, 0.06)
			LowPoly.add_limb(st, Vector3(side * 0.25, 2.28, -0.06), Vector3(side * 0.34, 1.55, -0.05), 0.05, 0.045, 5, pale, 0.06)
			LowPoly.add_limb(st, Vector3(side * 0.34, 1.55, -0.05), Vector3(side * 0.37, 0.78, -0.13), 0.045, 0.035, 5, pale, 0.06)
			for finger in 3:
				var spread := (finger - 1) * 0.045
				LowPoly.add_limb(st, Vector3(side * 0.37, 0.78, -0.13), Vector3(side * (0.39 + spread), 0.42, -0.16 + spread), 0.016, 0.004, 3, pale.darkened(0.15))
		LowPoly.add_blob(st, 0.17, Vector3(0, 1.42, 0), pale, 40, 0.06)
		LowPoly.add_limb(st, Vector3(0, 1.4, 0), Vector3(0, 2.35, -0.08), 0.15, 0.2, 6, pale, 0.08)
		LowPoly.add_limb(st, Vector3(0, 2.33, -0.08), Vector3(0, 2.56, -0.17), 0.06, 0.055, 5, pale)
		LowPoly.add_blob(st, 0.17, Vector3(0, 2.73, -0.2), pale, 41, 0.05, 1.35, 1)
		for side in [-1.0, 1.0]:
			LowPoly.add_box(st, Vector3(0.06, 0.1, 0.03), Vector3(side * 0.06, 2.77, -0.355), black)  # hollow eyes
		LowPoly.add_box(st, Vector3(0.07, 0.15, 0.03), Vector3(0, 2.57, -0.34), black)                 # gaping mouth
	_mesh_part(_body, build)


func _build_crawler() -> void:
	var skin := Color(0.70, 0.66, 0.58)
	var mouth := Color(0.45, 0.06, 0.06)
	var build := func(st: SurfaceTool) -> void:
		LowPoly.add_blob(st, 0.4, Vector3(0, 0.5, 0), skin, 50, 0.08, 0.6, 1)
		LowPoly.add_blob(st, 0.5, Vector3(0, 0.55, 0.6), skin.darkened(0.1), 51, 0.08, 0.7, 1)
		LowPoly.add_blob(st, 0.24, Vector3(0, 0.45, -0.45), skin.lightened(0.05), 52, 0.06, 0.8)
		for side in [-1.0, 1.0]:  # Mandibles; no eyes at all.
			LowPoly.add_limb(st, Vector3(side * 0.09, 0.38, -0.6), Vector3(side * 0.04, 0.3, -0.84), 0.045, 0.0, 4, mouth)
		for i in 4:  # Spines along the back.
			LowPoly.add_limb(st, Vector3(0, 0.75, 0.25 + i * 0.2), Vector3(0, 1.0 - i * 0.04, 0.35 + i * 0.22), 0.05, 0.0, 4, skin.darkened(0.3))
	_mesh_part(_body, build)
	for z in [-0.25, 0.05, 0.35]:
		for side in [-1.0, 1.0]:
			var pivot := Node3D.new()
			pivot.position = Vector3(side * 0.3, 0.5, z)
			_body.add_child(pivot)
			var leg := func(st: SurfaceTool) -> void:
				LowPoly.add_limb(st, Vector3.ZERO, Vector3(side * 0.55, 0.38, 0), 0.05, 0.04, 4, skin, 0.08)
				LowPoly.add_limb(st, Vector3(side * 0.55, 0.38, 0), Vector3(side * 0.95, -0.5, 0), 0.04, 0.012, 4, skin.darkened(0.25), 0.08)
			_mesh_part(pivot, leg)
			_legs.append(pivot)


func _build_shade() -> void:
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1, 1, 1, 0.85)
	var black := Color(0.03, 0.03, 0.04)
	var build := func(st: SurfaceTool) -> void:
		LowPoly.add_cylinder(st, 0.18, 0.6, 1.7, 8, Vector3(0, 0.85, 0), black, 0.3)
		LowPoly.add_blob(st, 0.3, Vector3(0, 1.8, 0.02), black, 60, 0.3, 1.1)
		for i in 7:  # Ragged hem.
			var a := TAU * i / 7.0
			var out := Vector3(cos(a), 0, sin(a))
			LowPoly.add_limb(st, out * 0.5 + Vector3(0, 0.15, 0), out * 0.58 + Vector3(0, -0.4 - (i % 3) * 0.1, 0), 0.13, 0.0, 4, black, 0.3)
	_mesh_part(_body, build)
	_extra = Node3D.new()
	_body.add_child(_extra)
	var eyes := func(st: SurfaceTool) -> void:
		for side in [-1.0, 1.0]:
			LowPoly.add_blob(st, 0.04, Vector3(side * 0.09, 1.83, -0.25), Color(1.0, 0.9, 0.6), 61)
	_mesh_part(_extra, eyes, _glow_material(Color(1.0, 1.0, 1.0)))


func _build_mimic() -> void:
	var bush := MeshInstance3D.new()  # The very same mesh as the real berry bushes.
	bush.mesh = world.get_prop_mesh("berry_bush")
	bush.material_override = _material
	_body.add_child(bush)
	_extra = Node3D.new()
	_extra.scale = Vector3.ONE * 0.01
	_body.add_child(_extra)
	var teeth := Color(0.95, 0.92, 0.85)
	var mouth := func(st: SurfaceTool) -> void:
		LowPoly.add_box(st, Vector3(0.75, 0.4, 0.12), Vector3(0, 0.45, -0.66), Color(0.35, 0.02, 0.04))
		for i in 7:
			var x := -0.3 + i * 0.1
			LowPoly.add_limb(st, Vector3(x, 0.66, -0.72), Vector3(x, 0.5, -0.74), 0.035, 0.0, 4, teeth)
			LowPoly.add_limb(st, Vector3(x + 0.05, 0.24, -0.72), Vector3(x + 0.05, 0.4, -0.74), 0.035, 0.0, 4, teeth)
	_mesh_part(_extra, mouth)
	var eyes := func(st: SurfaceTool) -> void:
		for p in [Vector3(-0.22, 0.85, -0.62), Vector3(0.22, 0.85, -0.62), Vector3(0.0, 0.98, -0.55)]:
			LowPoly.add_blob(st, 0.06, p, Color(1.0, 0.85, 0.2), 62)
	_mesh_part(_extra, eyes, _glow_material(Color.WHITE))
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		var pivot := Node3D.new()
		pivot.position = Vector3(corner.x * 0.35, 0.3, corner.z * 0.3)
		pivot.scale = Vector3(1, 0.01, 1)
		_body.add_child(pivot)
		var leg := func(st: SurfaceTool) -> void:
			LowPoly.add_limb(st, Vector3.ZERO, Vector3(corner.x * 0.25, -0.5, corner.z * 0.2), 0.08, 0.06, 5, Color(0.25, 0.2, 0.12), 0.1)
			LowPoly.add_limb(st, Vector3(corner.x * 0.25, -0.5, corner.z * 0.2), Vector3(corner.x * 0.2, -1.1, corner.z * 0.25), 0.06, 0.03, 5, Color(0.2, 0.16, 0.1), 0.1)
		_mesh_part(pivot, leg)
		_legs.append(pivot)
