extends Node3D
## Endless low-poly world. Terrain is generated in square chunks around the
## player from noise, so the same seed always gives the same world.

const LowPoly := preload("res://scripts/low_poly.gd")

const CHUNK_SIZE := 48.0          ## Width of one chunk in metres.
const CHUNK_RES := 16             ## Quads per chunk side (3 m per quad).
const VIEW_RADIUS := 5            ## Chunks kept loaded in each direction.
const CHUNKS_PER_FRAME := 2       ## Build budget, keeps the frame rate smooth.
const WATER_LEVEL := 0.0

const COLOR_SAND := Color(0.86, 0.79, 0.55)
const COLOR_GRASS := Color(0.42, 0.68, 0.30)
const COLOR_GRASS_DARK := Color(0.30, 0.55, 0.24)
const COLOR_ROCK := Color(0.50, 0.47, 0.44)
const COLOR_SNOW := Color(0.95, 0.96, 0.98)
const COLOR_SEABED := Color(0.55, 0.52, 0.40)

var world_seed: int = 1337
var target: Node3D

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _forest := FastNoiseLite.new()

var _chunks := {}                 ## Vector2i -> Node3D
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(1 << 30, 1 << 30)

var _terrain_material: StandardMaterial3D
var _water: MeshInstance3D
var _prop_meshes := {}            ## name -> ArrayMesh


func _ready() -> void:
	_continent.seed = world_seed
	_continent.frequency = 0.0015
	_continent.fractal_octaves = 3

	_hills.seed = world_seed + 1
	_hills.frequency = 0.008
	_hills.fractal_octaves = 4

	_mountains.seed = world_seed + 2
	_mountains.frequency = 0.004
	_mountains.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_mountains.fractal_octaves = 4

	_forest.seed = world_seed + 3
	_forest.frequency = 0.01

	_terrain_material = LowPoly.make_material()
	_build_prop_meshes()
	_build_water()


func _process(_delta: float) -> void:
	if target == null:
		return
	_water.global_position = Vector3(target.global_position.x, WATER_LEVEL, target.global_position.z)
	generate_around(target.global_position, false)

	for i in CHUNKS_PER_FRAME:
		if _queue.is_empty():
			break
		_build_chunk(_queue.pop_front())


## Terrain height in metres at a world position.
func get_height(x: float, z: float) -> float:
	var c := _continent.get_noise_2d(x, z)
	var base := c * 30.0 + 4.0
	var hills := _hills.get_noise_2d(x, z) * 6.0
	var ridge := (_mountains.get_noise_2d(x, z) + 1.0) * 0.5
	var mountains := pow(ridge, 3.0) * 90.0 * smoothstep(0.05, 0.5, c)
	return base + hills + mountains


## Queues chunks near `pos` and unloads far ones. With `immediate`, the
## chunks right around `pos` are built now so the player has ground to stand on.
func generate_around(pos: Vector3, immediate: bool) -> void:
	var center := _chunk_coord(pos)
	if center == _last_center and not immediate:
		return
	_last_center = center

	for coord in _chunks.keys():
		if _chunk_distance(coord, center) > VIEW_RADIUS + 1:
			_chunks[coord].queue_free()
			_chunks.erase(coord)

	_queue.clear()
	for x in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
		for z in range(-VIEW_RADIUS, VIEW_RADIUS + 1):
			var coord := center + Vector2i(x, z)
			if not _chunks.has(coord):
				_queue.append(coord)
	_queue.sort_custom(func(a, b): return _chunk_distance(a, center) < _chunk_distance(b, center))

	if immediate:
		while not _queue.is_empty() and _chunk_distance(_queue[0], center) <= 1:
			_build_chunk(_queue.pop_front())


## Searches outward from the origin for a dry, fairly flat place to start.
func find_spawn_point() -> Vector3:
	for ring in range(0, 200):
		var r := ring * 12.0
		var steps := maxi(1, ring * 6)
		for i in steps:
			var a := TAU * i / steps
			var x := cos(a) * r
			var z := sin(a) * r
			var h := get_height(x, z)
			if h > WATER_LEVEL + 3.0 and h < 25.0 and absf(get_height(x + 3.0, z) - h) < 1.5:
				return Vector3(x, h + 2.0, z)
	return Vector3(0, get_height(0, 0) + 2.0, 0)


func _chunk_coord(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CHUNK_SIZE), floori(pos.z / CHUNK_SIZE))


func _chunk_distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func _build_chunk(coord: Vector2i) -> void:
	if _chunks.has(coord):
		return
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	chunk.position = Vector3(coord.x * CHUNK_SIZE, 0, coord.y * CHUNK_SIZE)
	add_child(chunk)
	_chunks[coord] = chunk

	var body := StaticBody3D.new()
	chunk.add_child(body)
	_build_terrain(chunk, body)
	_build_props(chunk, body, coord)


func _build_terrain(chunk: Node3D, body: StaticBody3D) -> void:
	var step := CHUNK_SIZE / CHUNK_RES
	var heights := PackedFloat32Array()
	heights.resize((CHUNK_RES + 1) * (CHUNK_RES + 1))
	for z in CHUNK_RES + 1:
		for x in CHUNK_RES + 1:
			heights[z * (CHUNK_RES + 1) + x] = get_height(chunk.position.x + x * step, chunk.position.z + z * step)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := PackedVector3Array()

	for z in CHUNK_RES:
		for x in CHUNK_RES:
			var p00 := Vector3(x * step, heights[z * (CHUNK_RES + 1) + x], z * step)
			var p10 := Vector3((x + 1) * step, heights[z * (CHUNK_RES + 1) + x + 1], z * step)
			var p01 := Vector3(x * step, heights[(z + 1) * (CHUNK_RES + 1) + x], (z + 1) * step)
			var p11 := Vector3((x + 1) * step, heights[(z + 1) * (CHUNK_RES + 1) + x + 1], (z + 1) * step)
			# Alternate the diagonal so the low-poly facets don't all line up.
			if (x + z) % 2 == 0:
				_add_terrain_tri(st, faces, p00, p10, p11, chunk.position)
				_add_terrain_tri(st, faces, p00, p11, p01, chunk.position)
			else:
				_add_terrain_tri(st, faces, p00, p10, p01, chunk.position)
				_add_terrain_tri(st, faces, p10, p11, p01, chunk.position)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _terrain_material
	chunk.add_child(mesh_instance)

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)


func _add_terrain_tri(st: SurfaceTool, faces: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, origin: Vector3) -> void:
	var normal := LowPoly.face_normal(a, b, c)
	if normal.y < 0.0:
		var t := b
		b = c
		c = t
		normal = -normal

	var mid := (a + b + c) / 3.0
	var color := _terrain_color(mid.y, normal.y, origin.x + mid.x, origin.z + mid.z)
	st.set_color(color)
	st.set_normal(normal)
	for p in [a, b, c]:
		st.add_vertex(p)
		faces.append(p)


func _terrain_color(h: float, up: float, wx: float, wz: float) -> Color:
	if h < WATER_LEVEL - 0.5:
		return COLOR_SEABED
	if h < WATER_LEVEL + 1.8:
		return COLOR_SAND
	if h > 58.0 and up > 0.6:
		return COLOR_SNOW
	if up < 0.72 or h > 42.0:
		return COLOR_ROCK
	var t := clampf(_forest.get_noise_2d(wx * 3.0, wz * 3.0) * 0.5 + 0.5, 0.0, 1.0)
	return COLOR_GRASS.lerp(COLOR_GRASS_DARK, t)


func _build_props(chunk: Node3D, body: StaticBody3D, coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coord.x, coord.y, world_seed))

	var transforms := {"pine": [], "oak": [], "rock": []}
	for i in 40:
		var lx := rng.randf() * CHUNK_SIZE
		var lz := rng.randf() * CHUNK_SIZE
		var wx := chunk.position.x + lx
		var wz := chunk.position.z + lz
		var h := get_height(wx, wz)
		var slope := absf(get_height(wx + 1.0, wz) - h) + absf(get_height(wx, wz + 1.0) - h)
		var roll := rng.randf()
		var basis := Basis(Vector3.UP, rng.randf() * TAU)

		if h > WATER_LEVEL + 2.0 and h < 38.0 and slope < 0.9:
			var forest := _forest.get_noise_2d(wx, wz)
			if roll < 0.15 + forest * 0.6:
				var kind := "pine" if h > 16.0 or forest > 0.3 else "oak"
				var s := rng.randf_range(0.8, 1.4)
				transforms[kind].append(Transform3D(basis.scaled(Vector3.ONE * s), Vector3(lx, h - 0.2, lz)))
				_add_trunk_collider(body, Vector3(lx, h, lz), s)
				continue
		if h > WATER_LEVEL - 1.0 and roll > 0.93:
			var s := rng.randf_range(0.5, 2.0)
			transforms["rock"].append(Transform3D(basis.scaled(Vector3(s, s * 0.7, s)), Vector3(lx, h - 0.2, lz)))

	for kind in transforms:
		var list: Array = transforms[kind]
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _prop_meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, list[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _terrain_material
		chunk.add_child(mmi)


func _add_trunk_collider(body: StaticBody3D, pos: Vector3, s: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = 0.35 * s
	shape.height = 4.0 * s
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos + Vector3(0, shape.height * 0.5, 0)
	body.add_child(collision)


func _build_prop_meshes() -> void:
	var bark := Color(0.40, 0.27, 0.17)

	var pine := SurfaceTool.new()
	pine.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(pine, 0.25, 0.35, 2.0, 6, Vector3(0, 1.0, 0), bark)
	LowPoly.add_cylinder(pine, 0.0, 2.0, 3.0, 7, Vector3(0, 3.2, 0), Color(0.18, 0.42, 0.25))
	LowPoly.add_cylinder(pine, 0.0, 1.5, 2.6, 7, Vector3(0, 4.8, 0), Color(0.20, 0.46, 0.27))
	LowPoly.add_cylinder(pine, 0.0, 1.0, 2.0, 7, Vector3(0, 6.2, 0), Color(0.22, 0.50, 0.29))
	_prop_meshes["pine"] = pine.commit()

	var oak := SurfaceTool.new()
	oak.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(oak, 0.3, 0.4, 2.8, 6, Vector3(0, 1.4, 0), bark)
	LowPoly.add_blob(oak, 2.2, Vector3(0, 4.2, 0), Color(0.36, 0.62, 0.24), 11)
	LowPoly.add_blob(oak, 1.5, Vector3(1.0, 3.6, 0.6), Color(0.32, 0.58, 0.22), 12)
	_prop_meshes["oak"] = oak.commit()

	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(rock, 1.0, Vector3(0, 0.3, 0), Color(0.55, 0.53, 0.50), 21)
	_prop_meshes["rock"] = rock.commit()


func _build_water() -> void:
	var plane := PlaneMesh.new()
	var size := CHUNK_SIZE * (VIEW_RADIUS * 2 + 3)
	plane.size = Vector2(size, size)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.50, 0.75, 0.75)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.1
	mat.roughness = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	_water = MeshInstance3D.new()
	_water.name = "Water"
	_water.mesh = plane
	_water.material_override = mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
