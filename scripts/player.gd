extends CharacterBody3D
## Third-person explorer. WASD to move, Shift to sprint, Space to jump,
## mouse to look around. Keys and mouse settings come from the Settings autoload.
##
## The character is built in code from low-poly parts (body, head, two arms,
## two legs). Each limb hangs from a joint, so it can swing while walking,
## chop, eat and swim.

const LowPoly := preload("res://scripts/low_poly.gd")

const WALK_SPEED := 7.0
const SPRINT_SPEED := 14.0
const SWIM_SPEED := 4.0
const JUMP_VELOCITY := 8.0
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0025
const WATER_LEVEL := 0.0

const SWING_TIME := 0.35  ## One chop / mining swing, in seconds.
const EAT_TIME := 0.5

const SKIN := Color(0.95, 0.78, 0.62)
const HAIR := Color(0.38, 0.24, 0.13)
const DEFAULT_TUNIC := Color(0.75, 0.25, 0.20)
const DEFAULT_TROUSERS := Color(0.25, 0.32, 0.55)
const DEFAULT_SHOES := Color(0.30, 0.20, 0.12)
const HAT := Color(0.30, 0.55, 0.30)

## Turned off while a menu (like the inventory) is open.
var controls_enabled := true
## Percent bonuses from worn equipment.
var speed_bonus := 0.0
var jump_bonus := 0.0

var _camera_yaw: Node3D
var _camera_pitch: Node3D
var _camera: Camera3D

var _material: StandardMaterial3D
var _model: Node3D  ## Turns to face where you walk.
var _body: Node3D   ## Bobs up and down while walking.
var _torso: MeshInstance3D
var _head: MeshInstance3D
var _arm_l: MeshInstance3D  ## Limbs hang from their joint (shoulder / hip).
var _arm_r: MeshInstance3D
var _leg_l: MeshInstance3D
var _leg_r: MeshInstance3D
var _held: Node3D  ## The item in the right hand.
var _held_id := ""
var _held_light: OmniLight3D  ## Set while holding a lantern.

var _noise := 0.0   ## How far away the last loud thing you did could be heard (m).
var _shake := 0.0

var _walk_phase := 0.0
var _walk_amount := 0.0
var _swing_left := 0.0
var _eat_left := 0.0
var _swimming := false


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	_build_model()
	set_look({})

	_camera_yaw = Node3D.new()
	_camera_yaw.position.y = 1.6
	add_child(_camera_yaw)
	_camera_yaw.top_level = true

	_camera_pitch = Node3D.new()
	_camera_pitch.rotation.x = -0.35
	_camera_yaw.add_child(_camera_pitch)

	var arm := SpringArm3D.new()
	arm.spring_length = 6.0
	arm.margin = 0.3
	arm.add_excluded_object(get_rid())
	_camera_pitch.add_child(arm)

	_camera = Camera3D.new()
	_camera.far = 600.0
	_camera.fov = 70.0
	arm.add_child(_camera)
	_camera.current = true

	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sensitivity: float = MOUSE_SENSITIVITY * Settings.get_value("controls", "mouse_sensitivity")
		var invert := -1.0 if Settings.get_value("controls", "invert_y") else 1.0
		_camera_yaw.rotation.y -= event.relative.x * sensitivity
		_camera_pitch.rotation.x = clampf(_camera_pitch.rotation.x - event.relative.y * sensitivity * invert, -1.3, 0.6)


func _physics_process(delta: float) -> void:
	var swimming := global_position.y + 1.0 < WATER_LEVEL
	_swimming = swimming

	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (_camera_yaw.global_basis * Vector3(input.x, 0, input.y))
	direction.y = 0
	direction = direction.normalized()

	var speed := WALK_SPEED
	if swimming:
		speed = SWIM_SPEED
	elif controls_enabled and Input.is_action_pressed("sprint"):
		speed = SPRINT_SPEED
	speed *= 1.0 + speed_bonus / 100.0

	if swimming:
		# Float gently back up to the surface.
		velocity.y = move_toward(velocity.y, 2.5, 12.0 * delta)
	elif not is_on_floor():
		velocity.y -= GRAVITY * delta

	if controls_enabled and Input.is_action_just_pressed("jump") and (is_on_floor() or swimming):
		velocity.y = JUMP_VELOCITY * sqrt(1.0 + jump_bonus / 100.0)  # sqrt so jump height grows by jump_bonus %

	var accel := 12.0 if is_on_floor() or swimming else 3.0
	velocity.x = move_toward(velocity.x, direction.x * speed, speed * accel * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, speed * accel * delta)

	move_and_slide()

	if direction.length() > 0.1:
		var target_yaw := atan2(-direction.x, -direction.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_yaw, 10.0 * delta)

	_camera_yaw.global_position = global_position + Vector3(0, 1.6, 0)

	# Safety net if the player ever falls out of the world.
	if global_position.y < -100.0:
		var world = get_parent().get_node_or_null("World")
		if world:
			global_position = world.find_spawn_point()
			velocity = Vector3.ZERO


func _process(delta: float) -> void:
	_animate(delta)
	_noise = maxf(_noise - 25.0 * delta, 0.0)
	if _held_light:
		var t := Time.get_ticks_msec() * 0.001
		_held_light.light_energy = 2.2 + sin(t * 9.0) * 0.12 + sin(t * 23.0) * 0.08
	# Camera shake (when something hits you).
	_shake = maxf(_shake - delta * 2.5, 0.0)
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.25
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.25


## How far away monsters can hear you right now, in metres: sprinting is
## loud, walking is quiet, standing still is silent, chopping and mining
## carry a long way.
func get_noise() -> float:
	var speed := Vector2(velocity.x, velocity.z).length()
	var moving := 0.0
	if speed > WALK_SPEED * 1.2:
		moving = 45.0
	elif speed > 1.0:
		moving = 14.0
	return maxf(moving, _noise)


func make_noise(radius: float) -> void:
	_noise = maxf(_noise, radius)


## True while holding a lit lantern.
func has_light() -> bool:
	return _held_light != null


func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func set_fov(degrees: float) -> void:
	_camera.fov = degrees


func get_camera() -> Camera3D:
	return _camera


## Flat direction the camera looks in.
func get_look_direction() -> Vector3:
	return -_camera_yaw.global_basis.z


## Turns to face `pos` and swings the right arm (chopping / mining).
func swing_at(pos: Vector3) -> void:
	var to := pos - global_position
	if to.length() > 0.01:
		_model.rotation.y = atan2(-to.x, -to.z)
	_swing_left = SWING_TIME
	make_noise(35.0)


## Raises the held food to the mouth.
func eat_animation() -> void:
	_eat_left = EAT_TIME


# --- Animation ---------------------------------------------------------------

## Poses the limbs every frame: walking and running swing the arms and legs,
## jumping tucks the legs, swimming paddles, and chopping / eating move the
## right arm.
func _animate(delta: float) -> void:
	var ground_speed := Vector2(velocity.x, velocity.z).length()
	_walk_amount = move_toward(_walk_amount, clampf(ground_speed / WALK_SPEED, 0.0, 1.5), delta * 5.0)
	_walk_phase += delta * ground_speed * 1.5
	var stride := sin(_walk_phase) * 0.75 * minf(_walk_amount, 1.25)

	var leg_l := stride
	var leg_r := -stride
	var arm_l := -stride * 0.8
	var arm_r := stride * 0.8
	var arm_out := 0.1  # Arms held slightly away from the body.
	var bob := absf(sin(_walk_phase)) * 0.07 * minf(_walk_amount, 1.0)
	var t := Time.get_ticks_msec() * 0.001

	if _swimming:
		var paddle := sin(t * 5.0)
		arm_l = 1.4 + paddle * 0.9
		arm_r = 1.4 - paddle * 0.9
		arm_out = 0.5
		leg_l = 0.3 + sin(t * 8.0) * 0.4
		leg_r = 0.3 - sin(t * 8.0) * 0.4
		bob = 0.0
	elif not is_on_floor():
		leg_l = 0.7
		leg_r = -0.25
		arm_l = 0.4
		arm_r = 0.4
		arm_out = 0.55
		bob = 0.0
	elif _walk_amount < 0.05:
		# Standing still: breathe gently.
		arm_l = sin(t * 1.6) * 0.03
		arm_r = -arm_l

	var lean := 0.0
	if _swing_left > 0.0:
		_swing_left -= delta
		var p := 1.0 - maxf(_swing_left, 0.0) / SWING_TIME
		# Lift the arm over the shoulder, then bring it down hard.
		arm_r = lerpf(0.3, 2.7, ease(p / 0.4, 0.5)) if p < 0.4 else lerpf(2.7, 0.5, ease((p - 0.4) / 0.6, 0.4))
		lean = -sin(p * PI) * 0.12
	elif _eat_left > 0.0:
		_eat_left -= delta
		var p := 1.0 - maxf(_eat_left, 0.0) / EAT_TIME
		arm_r = sin(p * PI) * 2.1

	var k := 1.0 - exp(-18.0 * delta)
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, leg_l, k)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, leg_r, k)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, arm_l, k)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -arm_out, k)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, arm_out if _eat_left <= 0.0 else -0.45, k)
	_arm_r.rotation.x = arm_r if _swing_left > 0.0 or _eat_left > 0.0 else lerpf(_arm_r.rotation.x, arm_r, k)
	_body.position.y = bob
	_body.rotation.x = lean


# --- Building the character ---------------------------------------------------

func _build_model() -> void:
	_material = LowPoly.make_material()
	_model = Node3D.new()
	add_child(_model)
	_body = Node3D.new()
	_model.add_child(_body)
	# The model faces -Z, so the character's right is +X.
	_torso = _part(_body, Vector3.ZERO)
	_head = _part(_body, Vector3(0, 1.47, 0))
	_arm_l = _part(_body, Vector3(-0.33, 1.38, 0))
	_arm_r = _part(_body, Vector3(0.33, 1.38, 0))
	_leg_l = _part(_body, Vector3(-0.12, 0.84, 0))
	_leg_r = _part(_body, Vector3(0.12, 0.84, 0))
	_held = Node3D.new()
	_held.position = Vector3(0, -0.62, -0.02)  # In the right hand...
	_held.rotation.x = -1.0                      # ...with the handle pointing forward and up.
	_arm_r.add_child(_held)


func _part(parent: Node3D, joint: Vector3) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.material_override = _material
	part.position = joint
	parent.add_child(part)
	return part


## Builds a mesh with `build(st)`.
static func _mesh(build: Callable) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	build.call(st)
	return st.commit()


## Rebuilds the character, coloured by worn equipment.
## colors maps an equipment slot ("head", "chest", ...) to the worn item's colour.
func set_look(colors: Dictionary) -> void:
	var tunic: Color = colors.get("chest", DEFAULT_TUNIC)
	var trousers: Color = colors.get("legs", DEFAULT_TROUSERS)
	var shoes: Color = colors.get("feet", DEFAULT_SHOES)
	var hands: Color = colors.get("hands", SKIN)

	var build_torso := func(st: SurfaceTool) -> void:
		LowPoly.add_cylinder(st, 0.21, 0.2, 0.16, 8, Vector3(0, 0.86, 0), trousers, 0.05)          # hips
		LowPoly.add_cylinder(st, 0.27, 0.22, 0.56, 8, Vector3(0, 1.17, 0), tunic, 0.05)            # tunic
		LowPoly.add_cylinder(st, 0.245, 0.235, 0.07, 8, Vector3(0, 0.93, 0), tunic.darkened(0.45))  # belt
		LowPoly.add_box(st, Vector3(0.08, 0.07, 0.03), Vector3(0, 0.93, -0.245), Color(0.85, 0.72, 0.35))  # buckle
		for side in [-1.0, 1.0]:
			LowPoly.add_blob(st, 0.12, Vector3(side * 0.29, 1.37, 0), tunic, 3, 0.05, 0.85)       # shoulders
		LowPoly.add_cylinder(st, 0.075, 0.085, 0.12, 6, Vector3(0, 1.47, 0), SKIN)                # neck
		if colors.has("neck"):
			LowPoly.add_blob(st, 0.065, Vector3(0, 1.3, -0.27), colors["neck"], 4, 0.1)           # amulet
			LowPoly.add_limb(st, Vector3(-0.1, 1.44, -0.16), Vector3(0, 1.33, -0.265), 0.012, 0.012, 3, Color(0.3, 0.25, 0.2))
			LowPoly.add_limb(st, Vector3(0.1, 1.44, -0.16), Vector3(0, 1.33, -0.265), 0.012, 0.012, 3, Color(0.3, 0.25, 0.2))
	_torso.mesh = _mesh(build_torso)

	var build_head := func(st: SurfaceTool) -> void:
		LowPoly.add_blob(st, 0.21, Vector3(0, 0.2, 0), SKIN, 5, 0.03, 1.05, 1)
		for side in [-1.0, 1.0]:
			LowPoly.add_box(st, Vector3(0.045, 0.06, 0.03), Vector3(side * 0.075, 0.23, -0.19), Color(0.12, 0.09, 0.07))  # eyes
			LowPoly.add_box(st, Vector3(0.07, 0.02, 0.03), Vector3(side * 0.075, 0.285, -0.185), HAIR)                    # brows
			LowPoly.add_blob(st, 0.045, Vector3(side * 0.205, 0.19, 0.0), SKIN.darkened(0.05), 6)                          # ears
		LowPoly.add_limb(st, Vector3(0, 0.22, -0.19), Vector3(0, 0.15, -0.25), 0.03, 0.035, 4, SKIN.darkened(0.08))          # nose
		LowPoly.add_box(st, Vector3(0.07, 0.015, 0.02), Vector3(0, 0.1, -0.195), Color(0.55, 0.3, 0.25))                     # mouth
		if colors.has("head"):  # helmet
			LowPoly.add_blob(st, 0.245, Vector3(0, 0.25, 0.01), colors["head"], 8, 0.06, 0.8, 1)
			LowPoly.add_cylinder(st, 0.25, 0.26, 0.05, 10, Vector3(0, 0.2, 0.01), colors["head"].darkened(0.25))
		else:  # hair and the usual pointy hat
			LowPoly.add_blob(st, 0.205, Vector3(0, 0.26, 0.05), HAIR, 9, 0.06, 0.9)
			LowPoly.add_blob(st, 0.18, Vector3(0, 0.15, 0.07), HAIR, 12, 0.06, 1.0)  # back of the head
			LowPoly.add_cylinder(st, 0.35, 0.35, 0.035, 12, Vector3(0, 0.36, 0.01), HAT.darkened(0.1), 0.05)  # brim
			LowPoly.add_cylinder(st, 0.2, 0.21, 0.07, 10, Vector3(0, 0.41, 0.01), HAT.darkened(0.4))         # band
			LowPoly.add_limb(st, Vector3(0, 0.38, 0.01), Vector3(0, 0.62, 0.04), 0.2, 0.12, 8, HAT, 0.05)
			LowPoly.add_limb(st, Vector3(0, 0.62, 0.04), Vector3(0.0, 0.84, 0.14), 0.12, 0.0, 8, HAT, 0.05)  # floppy tip
	_head.mesh = _mesh(build_head)

	var build_arm := func(st: SurfaceTool) -> void:
		LowPoly.add_limb(st, Vector3(0, 0.02, 0), Vector3(0, -0.3, 0), 0.085, 0.075, 6, tunic, 0.05)   # sleeve
		LowPoly.add_limb(st, Vector3(0, -0.3, 0), Vector3(0, -0.53, 0), 0.068, 0.06, 6, SKIN, 0.03)    # forearm
		LowPoly.add_cylinder(st, 0.08, 0.075, 0.05, 6, Vector3(0, -0.29, 0), tunic.darkened(0.2))      # cuff
		LowPoly.add_blob(st, 0.075, Vector3(0, -0.6, -0.01), hands, 10, 0.04)                          # hand
	_arm_l.mesh = _mesh(build_arm)
	_arm_r.mesh = _arm_l.mesh

	var build_leg := func(st: SurfaceTool) -> void:
		LowPoly.add_limb(st, Vector3(0, 0.03, 0), Vector3(0, -0.66, 0), 0.11, 0.085, 6, trousers, 0.05)
		LowPoly.add_box(st, Vector3(0.17, 0.14, 0.28), Vector3(0, -0.76, -0.04), shoes)                  # boot
		LowPoly.add_cylinder(st, 0.1, 0.095, 0.1, 6, Vector3(0, -0.66, 0), shoes.darkened(0.1))          # boot top
	_leg_l.mesh = _mesh(build_leg)
	_leg_r.mesh = _leg_l.mesh


# --- The held item -------------------------------------------------------------

## Shows item `id` (from items.gd) in the player's hand, or nothing for "".
func set_held(id: String, info: Dictionary) -> void:
	if id == _held_id:
		return
	_held_id = id
	for child in _held.get_children():
		child.queue_free()
	_held_light = null
	if id == "":
		return
	if info.get("light", false):
		_hold_lantern(info)
		return
	var color: Color = info.get("color", Color.WHITE)
	var wood := Color(0.50, 0.34, 0.20)
	var item := MeshInstance3D.new()
	item.material_override = _material
	var build_axe := func(st: SurfaceTool) -> void:
		LowPoly.add_limb(st, Vector3(0, -0.15, 0), Vector3(0, 0.62, 0), 0.035, 0.03, 5, wood, 0.06)
		# Blade: a wedge sticking out forward near the top, wide at the edge.
		LowPoly.add_limb(st, Vector3(0, 0.5, -0.02), Vector3(0, 0.5, -0.3), 0.07, 0.15, 4, color, 0.1)
	var build_pickaxe := func(st: SurfaceTool) -> void:
		LowPoly.add_limb(st, Vector3(0, -0.15, 0), Vector3(0, 0.62, 0), 0.035, 0.03, 5, wood, 0.06)
		# Head: a curved spike to the front and a shorter one to the back.
		LowPoly.add_limb(st, Vector3(0, 0.6, 0), Vector3(0, 0.56, -0.22), 0.06, 0.045, 5, color, 0.1)
		LowPoly.add_limb(st, Vector3(0, 0.56, -0.22), Vector3(0, 0.45, -0.36), 0.045, 0.0, 5, color, 0.1)
		LowPoly.add_limb(st, Vector3(0, 0.6, 0), Vector3(0, 0.55, 0.22), 0.06, 0.0, 5, color, 0.1)
	match info.get("tool", ""):
		"axe":
			item.mesh = _mesh(build_axe)
		"pickaxe":
			item.mesh = _mesh(build_pickaxe)
		_:
			if info.has("place"):  # A bench is a bit big for one hand; show a small block of it.
				item.mesh = _mesh(func(st: SurfaceTool) -> void: LowPoly.add_box(st, Vector3(0.3, 0.12, 0.2), Vector3(0, 0.08, 0), color))
			else:
				item.mesh = _mesh(func(st: SurfaceTool) -> void: LowPoly.add_blob(st, 0.11, Vector3(0, 0.08, 0), color, 7, 0.08))
	_held.add_child(item)


## A lantern hanging from the hand, with a warm flickering light.
func _hold_lantern(info: Dictionary) -> void:
	var lantern := Node3D.new()
	lantern.rotation.x = 1.0  # Undo the hand's tilt so it hangs straight down.
	_held.add_child(lantern)
	var frame := Color(0.25, 0.23, 0.21)
	var build := func(st: SurfaceTool) -> void:
		LowPoly.add_limb(st, Vector3(0, 0.0, 0), Vector3(0, -0.12, 0), 0.012, 0.012, 3, frame)       # handle
		LowPoly.add_cylinder(st, 0.08, 0.1, 0.05, 6, Vector3(0, -0.14, 0), frame)                  # top
		LowPoly.add_cylinder(st, 0.1, 0.1, 0.04, 6, Vector3(0, -0.38, 0), frame)                   # base
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			LowPoly.add_limb(st, Vector3(cos(a) * 0.085, -0.16, sin(a) * 0.085), Vector3(cos(a) * 0.085, -0.36, sin(a) * 0.085), 0.012, 0.012, 3, frame)
	var body := MeshInstance3D.new()
	body.mesh = _mesh(build)
	body.material_override = _material
	lantern.add_child(body)
	var glow_material := LowPoly.make_material()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var glow := MeshInstance3D.new()
	glow.mesh = _mesh(func(st: SurfaceTool) -> void: LowPoly.add_cylinder(st, 0.07, 0.07, 0.19, 6, Vector3(0, -0.26, 0), info["color"].lightened(0.3)))
	glow.material_override = glow_material
	glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lantern.add_child(glow)
	_held_light = OmniLight3D.new()
	_held_light.light_color = Color(1.0, 0.75, 0.45)
	_held_light.omni_range = 18.0
	_held_light.omni_attenuation = 1.1
	# No shadows: right next to the body they'd throw huge streaks across the ground.
	_held_light.shadow_enabled = false
	_held_light.position.y = -0.26
	lantern.add_child(_held_light)


func get_save_data() -> Dictionary:
	return {
		"position": [global_position.x, global_position.y, global_position.z],
		"facing": _model.rotation.y,
		"camera_yaw": _camera_yaw.rotation.y,
		"camera_pitch": _camera_pitch.rotation.x,
	}


func apply_save_data(data: Dictionary) -> void:
	var p: Array = data.get("position", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
	_model.rotation.y = data.get("facing", 0.0)
	_camera_yaw.rotation.y = data.get("camera_yaw", 0.0)
	_camera_pitch.rotation.x = data.get("camera_pitch", -0.35)
	_camera_yaw.global_position = global_position + Vector3(0, 1.6, 0)
	velocity = Vector3.ZERO
