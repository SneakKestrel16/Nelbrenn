extends CharacterBody3D
## Third-person explorer. WASD to move, Shift to sprint, Space to jump,
## mouse to look around. Keys and mouse settings come from the Settings autoload.

const LowPoly := preload("res://scripts/low_poly.gd")

const WALK_SPEED := 7.0
const SPRINT_SPEED := 14.0
const SWIM_SPEED := 4.0
const JUMP_VELOCITY := 8.0
const GRAVITY := 22.0
const MOUSE_SENSITIVITY := 0.0025
const WATER_LEVEL := 0.0

## Turned off while a menu (like the inventory) is open.
var controls_enabled := true
## Percent bonuses from worn equipment.
var speed_bonus := 0.0
var jump_bonus := 0.0

var _camera_yaw: Node3D
var _camera_pitch: Node3D
var _camera: Camera3D
var _model: Node3D


func _ready() -> void:
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	var collision := CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.9
	add_child(collision)

	_model = MeshInstance3D.new()
	_model.material_override = LowPoly.make_material()
	set_look({})
	add_child(_model)

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


func set_fov(degrees: float) -> void:
	_camera.fov = degrees


func get_camera() -> Camera3D:
	return _camera


## Flat direction the camera looks in.
func get_look_direction() -> Vector3:
	return -_camera_yaw.global_basis.z


## Turns to face `pos` and leans in for a quick chop / swing.
func swing_at(pos: Vector3) -> void:
	var to := pos - global_position
	if to.length() > 0.01:
		_model.rotation.y = atan2(-to.x, -to.z)
	var tween := create_tween()
	tween.tween_property(_model, "rotation:x", -0.35, 0.08)
	tween.tween_property(_model, "rotation:x", 0.0, 0.18)


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


## Rebuilds the character, coloured by worn equipment.
## colors maps an equipment slot ("head", "chest", ...) to the worn item's colour.
func set_look(colors: Dictionary) -> void:
	var skin := Color(0.95, 0.78, 0.62)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(st, 0.3, 0.4, 0.9, 6, Vector3(0, 0.55, 0), colors.get("legs", Color(0.25, 0.32, 0.55)))   # legs
	LowPoly.add_cylinder(st, 0.35, 0.42, 0.7, 6, Vector3(0, 1.2, 0), colors.get("chest", Color(0.75, 0.25, 0.20))) # tunic
	LowPoly.add_blob(st, 0.28, Vector3(0, 1.8, 0), skin, 5)                                                        # head
	LowPoly.add_cylinder(st, 0.08, 0.08, 0.25, 4, Vector3(0, 1.78, -0.3), skin)                                    # nose, shows facing
	if colors.has("head"):  # helmet
		LowPoly.add_cylinder(st, 0.2, 0.34, 0.3, 6, Vector3(0, 2.02, 0), colors["head"])
	else:  # the usual pointy hat
		LowPoly.add_cylinder(st, 0.0, 0.32, 0.45, 6, Vector3(0, 2.15, 0), Color(0.30, 0.55, 0.30))
	if colors.has("feet"):  # boots
		LowPoly.add_cylinder(st, 0.42, 0.44, 0.3, 6, Vector3(0, 0.2, 0), colors["feet"])
	if colors.has("neck"):  # amulet on the chest
		LowPoly.add_blob(st, 0.09, Vector3(0, 1.38, -0.4), colors["neck"], 3)
	_model.mesh = st.commit()