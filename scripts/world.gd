extends Node3D
## Endless low-poly world. Terrain is generated in square chunks around the
## player from noise, so the same seed always gives the same world.

const LowPoly := preload("res://scripts/low_poly.gd")
const Harvestables := preload("res://scripts/harvestables.gd")

const CHUNK_SIZE := 48.0          ## Width of one chunk in metres.
const CHUNK_RES := 24             ## Quads per chunk side (2 m per quad).
const MAX_VIEW_RADIUS := 8        ## Largest view distance the settings allow.
const CHUNKS_PER_FRAME := 1       ## Build budget, keeps the frame rate smooth.
const WATER_LEVEL := 0.0
const LOD_DISTANCE := 110.0       ## Beyond this (from a chunk's centre), trees and rocks use simpler models.
const PROPS_CENTER := Vector3(CHUNK_SIZE * 0.5, 0, CHUNK_SIZE * 0.5)
const FIRE_RADIUS := 10.0         ## Monsters keep this far from a campfire.

const COLOR_SAND := Color(0.86, 0.79, 0.55)
const COLOR_WET_SAND := Color(0.72, 0.65, 0.45)
const COLOR_GRASS := Color(0.42, 0.66, 0.29)
const COLOR_GRASS_DRY := Color(0.58, 0.66, 0.33)
const COLOR_GRASS_DARK := Color(0.27, 0.48, 0.22)  ## Forest floor.
const COLOR_DIRT := Color(0.47, 0.39, 0.27)
const COLOR_ROCK := Color(0.52, 0.49, 0.46)
const COLOR_ROCK_DARK := Color(0.40, 0.38, 0.36)
const COLOR_SNOW := Color(0.95, 0.96, 0.98)
const COLOR_SEABED := Color(0.55, 0.52, 0.40)

var world_seed: int = 1337
var target: Node3D
## Chunks kept loaded in each direction (the view distance setting).
var view_radius := 5:
	set(value):
		view_radius = value
		_last_center = Vector2i(1 << 30, 1 << 30)  # Re-check which chunks to load.

var _continent := FastNoiseLite.new()
var _hills := FastNoiseLite.new()
var _mountains := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _warp := FastNoiseLite.new()     ## Bends the other noises so shapes look less blobby.
var _detail := FastNoiseLite.new()   ## Small bumps and colour speckle.
var _patches := FastNoiseLite.new()  ## Large soft patches of drier or greener ground.
var _ore := FastNoiseLite.new()      ## Where ore deposits cluster together.

var _chunks := {}                 ## Vector2i -> Node3D
var _queue: Array[Vector2i] = []
var _last_center := Vector2i(1 << 30, 1 << 30)

var _terrain_material: StandardMaterial3D  ## Trees and rocks.
var _ground_material: StandardMaterial3D
var _water: MeshInstance3D
var _prop_meshes := {}            ## name -> ArrayMesh
var _chip_mesh: BoxMesh
var _flame_mesh: ArrayMesh
var _flame_material: StandardMaterial3D

var _resources := {}              ## Vector2i -> Array of harvestable nodes in that chunk
var _resource_by_id := {}         ## node id -> node, for loaded chunks
var _harvested := {}              ## node id -> unix time it grows back (saved)
var _structures: Array = []       ## Things the player built: {"kind", "pos", "yaw", "node"} (saved)
var _regrow_timer := 0.0


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

	_warp.seed = world_seed + 4
	_warp.frequency = 0.004
	_warp.fractal_octaves = 2

	_detail.seed = world_seed + 5
	_detail.frequency = 0.08
	_detail.fractal_octaves = 2

	_patches.seed = world_seed + 6
	_patches.frequency = 0.012
	_patches.fractal_octaves = 2

	_ore.seed = world_seed + 7
	_ore.frequency = 0.02

	_terrain_material = LowPoly.make_material()
	_ground_material = _make_ground_material()
	_chip_mesh = BoxMesh.new()
	_chip_mesh.size = Vector3.ONE * 0.14
	_build_prop_meshes()
	_build_water()


func _process(delta: float) -> void:
	_flicker()
	_regrow_timer -= delta
	if _regrow_timer <= 0.0:
		_regrow_timer = 2.0
		_regrow()
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
	# Sample the big shapes at a slightly bent position, which gives winding
	# coastlines and valleys instead of round blobs.
	var wx := x + _warp.get_noise_2d(x, z) * 30.0
	var wz := z + _warp.get_noise_2d(x + 5200.0, z - 1300.0) * 30.0
	var c := _continent.get_noise_2d(wx, wz)
	var base := c * 30.0 + 4.0
	# Hills roll more gently on low ground and near the coast.
	var hills := _hills.get_noise_2d(wx, wz) * lerpf(3.0, 7.0, smoothstep(-0.1, 0.4, c))
	var ridge := (_mountains.get_noise_2d(wx, wz) + 1.0) * 0.5
	var mountains := pow(ridge, 3.0) * 90.0 * smoothstep(0.05, 0.5, c)
	var h := base + hills + mountains
	# Flatten the land just around sea level into gentle beaches and shallows.
	h *= lerpf(0.55, 1.0, smoothstep(0.0, 5.0, absf(h)))
	return h + _detail.get_noise_2d(x, z) * 0.4


## Queues chunks near `pos` and unloads far ones. With `immediate`, the
## chunks right around `pos` are built now so the player has ground to stand on.
func generate_around(pos: Vector3, immediate: bool) -> void:
	var center := _chunk_coord(pos)
	if center == _last_center and not immediate:
		return
	_last_center = center

	for coord in _chunks.keys():
		if _chunk_distance(coord, center) > view_radius + 1:
			_chunks[coord].queue_free()
			_chunks.erase(coord)
			for node in _resources.get(coord, []):
				_resource_by_id.erase(node["id"])
			_resources.erase(coord)

	_queue.clear()
	for x in range(-view_radius, view_radius + 1):
		for z in range(-view_radius, view_radius + 1):
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
	var n := CHUNK_RES + 1
	# Heights with one extra sample on every side, so the smooth normals at a
	# chunk's edge match its neighbour's and there are no visible seams.
	var b := n + 2
	var heights := PackedFloat32Array()
	heights.resize(b * b)
	for z in b:
		for x in b:
			heights[z * b + x] = get_height(chunk.position.x + (x - 1) * step, chunk.position.z + (z - 1) * step)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	vertices.resize(n * n)
	normals.resize(n * n)
	colors.resize(n * n)
	for z in n:
		for x in n:
			var i := (z + 1) * b + (x + 1)
			var h := heights[i]
			var normal := Vector3(heights[i - 1] - heights[i + 1], 2.0 * step, heights[i - b] - heights[i + b]).normalized()
			var k := z * n + x
			vertices[k] = Vector3(x * step, h, z * step)
			normals[k] = normal
			colors[k] = _terrain_color(h, normal.y, chunk.position.x + x * step, chunk.position.z + z * step)

	var indices := PackedInt32Array()
	for z in CHUNK_RES:
		for x in CHUNK_RES:
			var i00 := z * n + x
			var i10 := i00 + 1
			var i01 := i00 + n
			var i11 := i01 + 1
			# Split each square along the diagonal that best follows the ground.
			if absf(vertices[i00].y - vertices[i11].y) < absf(vertices[i10].y - vertices[i01].y):
				indices.append_array(PackedInt32Array([i00, i10, i11, i00, i11, i01]))
			else:
				indices.append_array(PackedInt32Array([i00, i10, i01, i10, i11, i01]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.material_override = _ground_material
	chunk.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)


## Ground colour at one point, blending smoothly between sand, grass, forest
## floor, dirt, rock and snow depending on height and steepness (`up` is 1 on
## flat ground and smaller on slopes).
func _terrain_color(h: float, up: float, wx: float, wz: float) -> Color:
	var patch := _patches.get_noise_2d(wx, wz)
	var speck := _detail.get_noise_2d(wx * 4.0, wz * 4.0)
	var forest := _forest.get_noise_2d(wx, wz)  # Same noise that places the trees.

	var color := COLOR_GRASS.lerp(COLOR_GRASS_DRY, smoothstep(0.05, 0.6, patch) * 0.8)
	color = color.lerp(COLOR_GRASS_DRY, smoothstep(22.0, 38.0, h) * 0.6)    # Drier higher up.
	color = color.lerp(COLOR_GRASS_DARK, smoothstep(-0.05, 0.4, forest))   # Darker under trees.
	color = color.lerp(COLOR_DIRT, (1.0 - smoothstep(0.78, 0.9, up)) * 0.7)  # Bare earth on slopes.

	var sand := 1.0 - smoothstep(1.2, 2.6, h + speck * 0.5)
	color = color.lerp(COLOR_SAND.lerp(COLOR_WET_SAND, 1.0 - smoothstep(0.0, 0.8, h)), sand)

	var rock := maxf(1.0 - smoothstep(0.66, 0.8, up), smoothstep(38.0, 48.0, h + patch * 6.0))
	color = color.lerp(COLOR_ROCK.lerp(COLOR_ROCK_DARK, speck * 0.5 + 0.5), rock)

	var snow := smoothstep(54.0, 60.0, h + patch * 6.0) * smoothstep(0.5, 0.65, up)
	color = color.lerp(COLOR_SNOW, snow)

	color = color.lerp(COLOR_SEABED, 1.0 - smoothstep(-2.0, -0.3, h))
	return color * (1.0 + speck * 0.05)


## Vertex-coloured ground with a faint speckled texture on top, so large
## flat areas don't look like plastic.
func _make_ground_material() -> StandardMaterial3D:
	var mat := LowPoly.make_material()
	var noise := FastNoiseLite.new()
	noise.seed = world_seed
	noise.frequency = 0.03
	noise.fractal_octaves = 3
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.84, 0.84, 0.84))
	gradient.set_color(1, Color(1.0, 1.0, 1.0))
	var texture := NoiseTexture2D.new()
	texture.width = 256
	texture.height = 256
	texture.seamless = true
	texture.noise = noise
	texture.color_ramp = gradient
	mat.detail_enabled = true
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	mat.detail_albedo = texture
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true  # Lines up across chunks.
	mat.uv1_scale = Vector3.ONE * 0.08
	return mat

## Trees, rocks, ore deposits and berry bushes. Each one is a harvestable
## "node" (see harvestables.gd); they're drawn with one MultiMesh per kind.
func _build_props(chunk: Node3D, body: StaticBody3D, coord: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coord.x, coord.y, world_seed))

	var nodes: Array = []
	for i in 40:
		var lx := rng.randf() * CHUNK_SIZE
		var lz := rng.randf() * CHUNK_SIZE
		var wx := chunk.position.x + lx
		var wz := chunk.position.z + lz
		var h := get_height(wx, wz)
		var slope := absf(get_height(wx + 1.0, wz) - h) + absf(get_height(wx, wz + 1.0) - h)
		var roll := rng.randf()
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var id := "%d_%d_%d" % [coord.x, coord.y, i]

		if h > WATER_LEVEL + 2.0 and h < 38.0 and slope < 0.9:
			var forest := _forest.get_noise_2d(wx, wz)
			if roll < 0.15 + forest * 0.6:
				var kind := "pine" if h > 16.0 or forest > 0.3 else "oak"
				var s := rng.randf_range(0.8, 1.4)
				var node := _make_node(id, kind, chunk, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(lx, h - 0.2, lz)), 0.35 * s)
				node["collider"] = _add_trunk_collider(body, Vector3(lx, h, lz), s)
				node["tree"] = true
				nodes.append(node)
				continue
		if h > WATER_LEVEL - 1.0 and roll > 0.93:
			var s := rng.randf_range(0.5, 2.0)
			nodes.append(_make_node(id, "rock", chunk, Transform3D(basis.scaled(Vector3(s, s * 0.7, s)), Vector3(lx, h - 0.2, lz)), s))

	_add_ores_and_bushes(chunk, coord, nodes)

	var by_kind := {}
	for node in nodes:
		if not by_kind.has(node["kind"]):
			by_kind[node["kind"]] = []
		by_kind[node["kind"]].append(node)
	for kind in by_kind:
		var list: Array = by_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = _prop_meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			var node: Dictionary = list[i]
			node["mm"] = mm
			node["index"] = i
			mm.set_instance_color(i, _tint(node))
			if _harvested.has(node["id"]):  # Still regrowing since it was harvested.
				node["alive"] = false
				if node["collider"]:
					node["collider"].disabled = true
			_set_instance(node, node["xform"] if node["alive"] else _hidden(node))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _terrain_material
		mmi.position = PROPS_CENTER  # Centred, so the far-away switch happens evenly.
		chunk.add_child(mmi)
		# Far away, swap to a simpler version of the same thing.
		if _prop_meshes.has(kind + "_far"):
			var far: MultiMesh = mm.duplicate()
			far.mesh = _prop_meshes[kind + "_far"]
			for node in list:
				node["mm_far"] = far
			var far_mmi := MultiMeshInstance3D.new()
			far_mmi.multimesh = far
			far_mmi.material_override = _terrain_material
			far_mmi.position = PROPS_CENTER
			far_mmi.visibility_range_begin = LOD_DISTANCE
			mmi.visibility_range_end = LOD_DISTANCE
			chunk.add_child(far_mmi)

	_resources[coord] = nodes
	for node in nodes:
		_resource_by_id[node["id"]] = node


## A slight colour change per tree, rock or bush so no two look quite the
## same: plants shift between yellower and bluer greens, stone gets lighter
## or darker. Always the same for the same thing.
func _tint(node: Dictionary) -> Color:
	var h := absi(hash(node["id"]))
	var a := float(h % 1000) / 1000.0
	var b := float((h >> 10) % 1000) / 1000.0
	match node["kind"]:
		"oak", "pine", "berry_bush":
			return Color(0.86 + 0.14 * a, 0.88 + 0.12 * b, 0.84 + 0.16 * (1.0 - a))
		_:
			var grey := 0.86 + 0.14 * a
			return Color(grey, grey * (0.97 + 0.03 * b), grey * (0.95 + 0.05 * b))


## Ore deposits (more of them up in the hills and mountains, and in clusters)
## and berry bushes. They use their own random numbers so the trees and rocks
## of existing worlds stay exactly where they were.
func _add_ores_and_bushes(chunk: Node3D, coord: Vector2i, nodes: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(coord.x, coord.y, world_seed + 7))
	for i in 12:
		var lx := rng.randf() * CHUNK_SIZE
		var lz := rng.randf() * CHUNK_SIZE
		var roll := rng.randf()
		var pick := rng.randf()
		var s := rng.randf_range(0.8, 1.25)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var h := get_height(chunk.position.x + lx, chunk.position.z + lz)
		if h < WATER_LEVEL + 3.0:
			continue
		var vein := _ore.get_noise_2d(chunk.position.x + lx, chunk.position.z + lz)
		var chance := 0.03 + maxf(vein, 0.0) * 0.35 + smoothstep(15.0, 45.0, h) * 0.12
		if roll > chance:
			continue
		var kind := _pick_ore(h, pick)
		var id := "%d_%d_o%d" % [coord.x, coord.y, i]
		nodes.append(_make_node(id, kind, chunk, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(lx, h - 0.15, lz)), 0.9 * s))

	for i in 6:
		var lx := rng.randf() * CHUNK_SIZE
		var lz := rng.randf() * CHUNK_SIZE
		var roll := rng.randf()
		var s := rng.randf_range(0.8, 1.2)
		var basis := Basis(Vector3.UP, rng.randf() * TAU)
		var wx := chunk.position.x + lx
		var wz := chunk.position.z + lz
		var h := get_height(wx, wz)
		var slope := absf(get_height(wx + 1.0, wz) - h) + absf(get_height(wx, wz + 1.0) - h)
		if h < WATER_LEVEL + 2.0 or h > 30.0 or slope > 0.6:
			continue
		if roll > 0.08 + maxf(_forest.get_noise_2d(wx, wz), 0.0) * 0.3:
			continue
		var id := "%d_%d_b%d" % [coord.x, coord.y, i]
		nodes.append(_make_node(id, "berry_bush", chunk, Transform3D(basis.scaled(Vector3.ONE * s), Vector3(lx, h - 0.1, lz)), 0.8 * s))


## Which ore appears at height `h`: coal and copper everywhere, iron on hills,
## gold and crystals only high in the mountains. `pick` is a random 0..1.
func _pick_ore(h: float, pick: float) -> String:
	var weights := {
		"coal": 5.0,
		"copper": 3.0 if h > 6.0 else 0.0,
		"iron": 2.0 + smoothstep(20.0, 40.0, h) * 3.0 if h > 12.0 else 0.0,
		"gold": 1.2 if h > 28.0 else 0.0,
		"crystal": 1.0 if h > 42.0 else 0.0,
	}
	var total := 0.0
	for kind in weights:
		total += weights[kind]
	pick *= total
	for kind in weights:
		pick -= weights[kind]
		if pick <= 0.0:
			return kind
	return "coal"


func _make_node(id: String, kind: String, chunk: Node3D, xform: Transform3D, radius: float) -> Dictionary:
	return {
		"id": id, "kind": kind, "xform": xform, "radius": radius,
		"pos": chunk.position + xform.origin, "hp": Harvestables.get_info(kind)["hits"],
		"alive": true, "tree": false, "collider": null, "mm": null, "index": 0, "tween": null,
	}


func _add_trunk_collider(body: StaticBody3D, pos: Vector3, s: float) -> CollisionShape3D:
	var shape := CylinderShape3D.new()
	shape.radius = 0.35 * s
	shape.height = 4.0 * s
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = pos + Vector3(0, shape.height * 0.5, 0)
	body.add_child(collision)
	return collision


# --- Harvesting -------------------------------------------------------------

## The harvestable thing the player at `from`, looking along `forward`, can
## reach; prefers close things straight ahead. Returns {} if there's nothing.
func find_resource(from: Vector3, forward: Vector3, reach: float) -> Dictionary:
	var center := _chunk_coord(from)
	var best := {}
	var best_score := INF
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for node in _resources.get(center + Vector2i(dx, dz), []):
				if not node["alive"] or absf(node["pos"].y - from.y) > 3.0:
					continue
				var to: Vector3 = node["pos"] - from
				to.y = 0.0
				var dist: float = to.length() - node["radius"]
				if dist > reach:
					continue
				var facing := forward.dot(to.normalized()) if to.length() > 0.01 else 1.0
				if facing < 0.2 and dist > 0.5:
					continue
				var score := dist - facing * 1.5
				if score < best_score:
					best_score = score
					best = node
	return best


## Hits `node` for `damage` from a player standing at `from`. Returns true if it broke.
func hit_resource(node: Dictionary, from: Vector3, damage := 1) -> bool:
	var info := Harvestables.get_info(node["kind"])
	node["hp"] -= damage
	spawn_chips(node["pos"] + Vector3.UP * (1.2 if node["tree"] else 0.5), info["chips"])
	if node["hp"] > 0:
		_animate(node, "shake", from)
		return false
	node["alive"] = false
	_harvested[node["id"]] = Time.get_unix_time_from_system() + float(info["regrow"])
	if node["collider"]:
		node["collider"].set_deferred("disabled", true)
	_animate(node, "fall" if node["tree"] else "shrink", from)
	return true


## A little burst of chips flying off something you hit.
func spawn_chips(pos: Vector3, color: Color, amount := 8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = 0.8
	p.explosiveness = 1.0
	p.mesh = _chip_mesh
	p.material_override = _terrain_material
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 2.5
	p.initial_velocity_max = 5.0
	p.gravity = Vector3(0, -14.0, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.color = color
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.emitting = true


func get_save_data() -> Dictionary:
	var structures := []
	for s in _structures:
		structures.append({"kind": s["kind"], "pos": [s["pos"].x, s["pos"].y, s["pos"].z], "yaw": s["yaw"]})
	return {"harvested": _harvested.duplicate(), "structures": structures}


func apply_save_data(data: Dictionary) -> void:
	_harvested.clear()
	var saved = data.get("harvested", {})
	if saved is Dictionary:
		for id in saved:
			_harvested[String(id)] = float(saved[id])
	for s in _structures.duplicate():
		remove_structure(s)
	for s in data.get("structures", []):
		if s is Dictionary and _prop_meshes.has(String(s.get("kind", ""))) and s.get("pos", []).size() == 3:
			place_structure(String(s["kind"]), Vector3(s["pos"][0], s["pos"][1], s["pos"][2]), float(s.get("yaw", 0.0)))


# --- Things the player builds (crafting benches) ------------------------------

## Why something can't be built at `pos`, or "" if it can.
func can_place(pos: Vector3) -> String:
	var h := get_height(pos.x, pos.z)
	if h < WATER_LEVEL + 0.3:
		return "You can't build in the water."
	for offset in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9)]:
		if absf(get_height(pos.x + offset.x, pos.z + offset.y) - h) > 0.7:
			return "The ground is too steep here."
	for s in _structures:
		if s["pos"].distance_to(pos) < 2.2:
			return "Too close to something you've built."
	return ""


func place_structure(kind: String, pos: Vector3, yaw: float) -> Dictionary:
	var node := Node3D.new()
	node.name = "Structure"
	add_child(node)
	node.global_position = pos
	node.rotation.y = yaw
	var mesh := MeshInstance3D.new()
	mesh.mesh = _prop_meshes[kind]
	mesh.material_override = _terrain_material
	node.add_child(mesh)
	var s := {"kind": kind, "pos": pos, "yaw": yaw, "node": node, "radius": 0.8}
	if kind == "campfire":
		var flames := MeshInstance3D.new()
		flames.mesh = _flame_mesh
		flames.material_override = _flame_material
		flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flames.position.y = 0.15
		node.add_child(flames)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.6, 0.3)
		light.omni_range = FIRE_RADIUS + 4.0
		light.light_energy = 2.5
		light.shadow_enabled = true
		light.position.y = 1.0
		node.add_child(light)
		s["flames"] = flames
		s["light"] = light
		s["radius"] = 0.6
	else:
		var body := StaticBody3D.new()
		node.add_child(body)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.6, 1.0, 0.9)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position.y = 0.5
		body.add_child(collision)
	_structures.append(s)
	return s


## One of the shared prop meshes ("berry_bush", "rock", ...), e.g. for disguises.
func get_prop_mesh(kind: String) -> Mesh:
	return _prop_meshes.get(kind)


## True if `pos` is within the light of a campfire (monsters won't go there).
func near_fire(pos: Vector3, extra := 0.0) -> bool:
	for s in _structures:
		if s["kind"] == "campfire" and Vector2(s["pos"].x - pos.x, s["pos"].z - pos.z).length() < FIRE_RADIUS + extra:
			return true
	return false


## The nearest campfire's position to `pos`, or null if there are none.
func nearest_fire(pos: Vector3) -> Variant:
	var best = null
	for s in _structures:
		if s["kind"] == "campfire" and (best == null or s["pos"].distance_to(pos) < best.distance_to(pos)):
			best = s["pos"]
	return best


## Campfires flicker.
func _flicker() -> void:
	var t := Time.get_ticks_msec() * 0.001
	for s in _structures:
		if s.has("light"):
			var wobble := sin(t * 11.0 + s["pos"].x) * 0.5 + sin(t * 23.0 + s["pos"].z) * 0.3
			s["light"].light_energy = 2.5 + wobble * 0.5
			s["flames"].scale = Vector3(1.0 + wobble * 0.08, 1.0 + wobble * 0.18, 1.0 + wobble * 0.08)
			s["flames"].rotation.y = t * 0.7


func remove_structure(s: Dictionary) -> void:
	_structures.erase(s)
	s["node"].queue_free()


## The crafting bench the player at `from`, looking along `forward`, can use, or {}.
func find_structure(from: Vector3, forward: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_dist := INF
	for s in _structures:
		if s["kind"] != "crafting_bench":
			continue
		var to: Vector3 = s["pos"] - from
		if absf(to.y) > 2.5:
			continue
		to.y = 0.0
		var dist: float = to.length() - s["radius"]
		if dist > reach or (dist > 0.5 and forward.dot(to.normalized()) < 0.2):
			continue
		if dist < best_dist:
			best_dist = dist
			best = s
	return best


## Grows back things whose regrow time has passed.
func _regrow() -> void:
	var now := Time.get_unix_time_from_system()
	for id in _harvested.keys():
		if _harvested[id] > now:
			continue
		_harvested.erase(id)
		var node = _resource_by_id.get(id)
		if node != null and not node["alive"]:
			node["alive"] = true
			node["hp"] = Harvestables.get_info(node["kind"])["hits"]
			if node["collider"]:
				node["collider"].set_deferred("disabled", false)
			_animate(node, "grow", Vector3.ZERO)


func _animate(node: Dictionary, how: String, from: Vector3) -> void:
	if node["tween"]:
		node["tween"].kill()
	var xf: Transform3D = node["xform"]
	var tween := create_tween()
	node["tween"] = tween
	match how:
		"shake":
			var axis := Vector3(randf() - 0.5, 0.0, randf() - 0.5).normalized()
			var shake := func(f: float) -> void:
				var wobble := sin(f * TAU * 2.0) * (1.0 - f)
				if node["tree"]:
					_set_instance(node, Transform3D(Basis(axis, wobble * 0.06) * xf.basis, xf.origin))
				else:
					_set_instance(node, Transform3D(xf.basis.scaled(Vector3.ONE * (1.0 - absf(wobble) * 0.1)), xf.origin))
			tween.tween_method(shake, 0.0, 1.0, 0.3)
		"fall":  # Tip over away from the player, then sink away.
			var away: Vector3 = node["pos"] - from
			away.y = 0.0
			away = away.normalized() if away.length() > 0.01 else Vector3.FORWARD
			var axis := Vector3.UP.cross(away).normalized()
			var tip := func(f: float) -> void:
				_set_instance(node, Transform3D(Basis(axis, f * PI * 0.47) * xf.basis, xf.origin))
			var sink := func(f: float) -> void:
				_set_instance(node, Transform3D(Basis(axis, PI * 0.47) * xf.basis.scaled(Vector3.ONE * f), xf.origin))
			tween.tween_method(tip, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_method(sink, 1.0, 0.0, 0.4)
		"shrink", "grow":
			var resize := func(f: float) -> void:
				_set_instance(node, Transform3D(xf.basis.scaled(Vector3.ONE * maxf(f, 0.0)), xf.origin))
			if how == "shrink":
				tween.tween_method(resize, 1.0, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			else:
				tween.tween_method(resize, 0.0, 1.0, 1.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _set_instance(node: Dictionary, xform: Transform3D) -> void:
	xform.origin -= PROPS_CENTER
	node["mm"].set_instance_transform(node["index"], xform)
	if node.has("mm_far"):
		node["mm_far"].set_instance_transform(node["index"], xform)


## Harvested things are squashed to nothing rather than removed, so the
## MultiMesh doesn't need rebuilding.
func _hidden(node: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), node["xform"].origin)


## Roots spreading out from the bottom of a trunk.
func _add_roots(st: SurfaceTool, count: int, reach: float, color: Color) -> void:
	for i in count:
		var angle := TAU * (i + 0.3) / count
		var out := Vector3(cos(angle), 0, sin(angle))
		LowPoly.add_limb(st, out * 0.1 + Vector3(0, 0.45, 0), out * reach + Vector3(0, -0.1, 0), 0.13, 0.04, 4, color, 0.08)


func _build_prop_meshes() -> void:
	var bark := Color(0.40, 0.27, 0.17)

	var stone := Color(0.55, 0.53, 0.50)

	# Pine: a straight trunk with root flares under five layers of branches,
	# darker at the bottom and lighter towards the tip.
	var pine := SurfaceTool.new()
	pine.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_limb(pine, Vector3(0, -0.2, 0), Vector3(0, 2.6, 0), 0.32, 0.18, 7, bark, 0.08)
	_add_roots(pine, 3, 0.45, bark)
	var tiers := [[2.1, 2.4, 2.9], [1.75, 2.2, 4.0], [1.4, 2.0, 5.0], [1.05, 1.7, 5.9], [0.65, 1.4, 6.8]]
	for i in tiers.size():
		var tier: Array = tiers[i]
		var green := Color(0.14, 0.36, 0.22).lerp(Color(0.25, 0.53, 0.31), float(i) / (tiers.size() - 1))
		LowPoly.add_cylinder(pine, 0.0, tier[0], tier[1], 9, Vector3(0, tier[2], 0), green, 0.09)
		# A darker lip under each layer makes the branches look like they droop.
		LowPoly.add_cylinder(pine, tier[0] * 0.75, tier[0] * 0.95, 0.22, 9, Vector3(0, tier[2] - tier[1] * 0.5 + 0.08, 0), green.darkened(0.25), 0.06)
	_prop_meshes["pine"] = pine.commit()

	# Oak: a thick trunk that splits into branches, under a crown of leafy clumps.
	var oak := SurfaceTool.new()
	oak.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_limb(oak, Vector3(0, -0.2, 0), Vector3(0, 2.5, 0), 0.4, 0.27, 7, bark, 0.08)
	_add_roots(oak, 4, 0.55, bark)
	for branch in [[1.8, Vector3(1.1, 3.2, 0.4)], [2.1, Vector3(-1.0, 3.4, -0.4)], [2.3, Vector3(0.2, 3.6, -0.9)]]:
		LowPoly.add_limb(oak, Vector3(0, branch[0], 0), branch[1], 0.15, 0.07, 5, bark, 0.08)
	var leaves := [
		[Vector3(0, 4.2, 0), 2.0, Color(0.36, 0.62, 0.24)],
		[Vector3(1.25, 3.6, 0.5), 1.35, Color(0.31, 0.57, 0.22)],
		[Vector3(-1.15, 3.8, -0.45), 1.3, Color(0.34, 0.60, 0.23)],
		[Vector3(0.3, 3.5, -1.15), 1.1, Color(0.29, 0.54, 0.21)],
		[Vector3(-0.25, 5.1, 0.35), 1.25, Color(0.41, 0.67, 0.27)],
	]
	for i in leaves.size():
		LowPoly.add_blob(oak, leaves[i][1], leaves[i][0], leaves[i][2], 11 + i, 0.08, 0.85, 1)
	_prop_meshes["oak"] = oak.commit()

	# Rock: a big boulder with a smaller one and a pebble leaning on it.
	var rock := SurfaceTool.new()
	rock.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(rock, 1.0, Vector3(0, 0.3, 0), stone, 21, 0.08, 0.8, 1)
	LowPoly.add_blob(rock, 0.5, Vector3(0.8, 0.05, 0.35), stone.darkened(0.08), 22, 0.08, 0.8)
	LowPoly.add_blob(rock, 0.25, Vector3(-0.85, -0.05, -0.5), stone.lightened(0.05), 23, 0.08)
	_prop_meshes["rock"] = rock.commit()

	# Ore deposits: a dark boulder studded with chunks of the ore's colour.
	var ore_colors := {
		"coal": Color(0.10, 0.10, 0.11), "copper": Color(0.85, 0.50, 0.25),
		"iron": Color(0.78, 0.52, 0.42), "gold": Color(1.0, 0.82, 0.25),
	}
	for kind in ore_colors:
		var ore := SurfaceTool.new()
		ore.begin(Mesh.PRIMITIVE_TRIANGLES)
		var middle := Vector3(0, 0.35, 0)
		LowPoly.add_blob(ore, 0.9, middle, Color(0.42, 0.40, 0.38), 31, 0.08, 0.85, 1)
		LowPoly.add_blob(ore, 0.45, Vector3(-0.75, 0.05, 0.4), Color(0.38, 0.36, 0.34), 32, 0.08, 0.8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for j in 9:
			var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.05, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			var chunk_color: Color = ore_colors[kind].lightened(rng.randf_range(-0.1, 0.2))
			LowPoly.add_blob(ore, rng.randf_range(0.14, 0.26), middle + dir * Vector3(0.8, 0.7, 0.8), chunk_color, 40 + j, 0.15)
		_prop_meshes[kind] = ore.commit()

	# Crystals: six-sided spikes leaning out of a small rock.
	var crystal := SurfaceTool.new()
	crystal.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(crystal, 0.65, Vector3(0, 0.1, 0), Color(0.42, 0.40, 0.38), 33, 0.08, 0.7)
	for spike in [[Vector3(0, 1, 0), 1.7, 0.22], [Vector3(0.5, 0.8, 0.2), 1.2, 0.17], [Vector3(-0.45, 0.85, 0.3), 1.0, 0.15],
			[Vector3(0.15, 0.75, -0.6), 1.05, 0.15], [Vector3(-0.3, 0.9, -0.35), 0.7, 0.11]]:
		var dir: Vector3 = spike[0].normalized()
		var base := Vector3(dir.x * 0.25, 0.3, dir.z * 0.25)
		var tint := Color(0.55, 0.85, 0.95).lerp(Color(0.75, 0.6, 0.95), absf(dir.x))
		var tip: Vector3 = base + dir * spike[1]
		LowPoly.add_limb(crystal, base, base + dir * spike[1] * 0.75, spike[2], spike[2] * 0.9, 6, tint, 0.12)
		LowPoly.add_limb(crystal, base + dir * spike[1] * 0.75, tip, spike[2] * 0.9, 0.0, 6, tint.lightened(0.15), 0.12)
	_prop_meshes["crystal"] = crystal.commit()

	# Berry bush: a few leafy puffs dotted with red berries.
	var bush := SurfaceTool.new()
	bush.begin(Mesh.PRIMITIVE_TRIANGLES)
	var puffs := [
		[Vector3(0, 0.55, 0), 0.72, Color(0.24, 0.50, 0.22)],
		[Vector3(0.5, 0.42, 0.3), 0.52, Color(0.28, 0.55, 0.24)],
		[Vector3(-0.45, 0.4, 0.2), 0.48, Color(0.22, 0.47, 0.21)],
		[Vector3(0.05, 0.4, -0.5), 0.45, Color(0.26, 0.52, 0.23)],
	]
	for i in puffs.size():
		LowPoly.add_blob(bush, puffs[i][1], puffs[i][0], puffs[i][2], 51 + i, 0.1, 0.85, 1)
	var berry_rng := RandomNumberGenerator.new()
	berry_rng.seed = 53
	for j in 14:
		var puff: Array = puffs[j % puffs.size()]
		var dir := Vector3(berry_rng.randf_range(-1.0, 1.0), berry_rng.randf_range(-0.1, 1.0), berry_rng.randf_range(-1.0, 1.0)).normalized()
		var berry := Color(0.80, 0.12, 0.22).lightened(berry_rng.randf_range(-0.1, 0.15))
		LowPoly.add_blob(bush, 0.09, puff[0] + dir * puff[1] * 0.92, berry, 60 + j)
	_prop_meshes["berry_bush"] = bush.commit()

	# Simple versions for far away (see LOD_DISTANCE), about a third of the triangles.
	var pine_far := SurfaceTool.new()
	pine_far.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(pine_far, 0.2, 0.32, 2.6, 5, Vector3(0, 1.1, 0), bark)
	for i in tiers.size():
		var tier: Array = tiers[i]
		var green := Color(0.14, 0.36, 0.22).lerp(Color(0.25, 0.53, 0.31), float(i) / (tiers.size() - 1))
		LowPoly.add_cylinder(pine_far, 0.0, tier[0], tier[1], 7, Vector3(0, tier[2], 0), green)
	_prop_meshes["pine_far"] = pine_far.commit()

	var oak_far := SurfaceTool.new()
	oak_far.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(oak_far, 0.27, 0.4, 2.8, 5, Vector3(0, 1.2, 0), bark)
	LowPoly.add_blob(oak_far, 2.3, Vector3(0, 4.2, 0), Color(0.36, 0.62, 0.24), 11, 0.0, 0.85)
	LowPoly.add_blob(oak_far, 1.4, Vector3(1.1, 3.6, 0.4), Color(0.31, 0.57, 0.22), 12, 0.0, 0.85)
	_prop_meshes["oak_far"] = oak_far.commit()

	var rock_far := SurfaceTool.new()
	rock_far.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(rock_far, 1.05, Vector3(0, 0.3, 0), stone, 21, 0.0, 0.8)
	_prop_meshes["rock_far"] = rock_far.commit()

	var bush_far := SurfaceTool.new()
	bush_far.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(bush_far, 0.8, Vector3(0.05, 0.5, 0), Color(0.25, 0.51, 0.22), 51, 0.0, 0.85)
	_prop_meshes["berry_bush_far"] = bush_far.commit()

	# Campfire: a ring of stones around crossed logs. The flames are separate
	# (they glow and flicker).
	var fire := SurfaceTool.new()
	fire.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 9:
		var a := TAU * i / 9.0
		LowPoly.add_blob(fire, 0.16, Vector3(cos(a) * 0.62, 0.05, sin(a) * 0.62), stone.darkened(0.1), 70 + i, 0.1, 0.7)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var out := Vector3(cos(a), 0, sin(a))
		LowPoly.add_limb(fire, out * 0.5 + Vector3(0, 0.02, 0), -out * 0.15 + Vector3(0, 0.4, 0), 0.08, 0.07, 5, bark, 0.1)
	LowPoly.add_blob(fire, 0.3, Vector3(0, 0.0, 0), Color(0.12, 0.1, 0.09), 80, 0.1, 0.3)  # ash
	_prop_meshes["campfire"] = fire.commit()
	var flame := SurfaceTool.new()
	flame.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_cylinder(flame, 0.0, 0.34, 0.9, 6, Vector3(0, 0.45, 0), Color(1.0, 0.45, 0.1))
	LowPoly.add_cylinder(flame, 0.0, 0.22, 0.75, 5, Vector3(0.12, 0.4, 0.05), Color(1.0, 0.75, 0.25))
	LowPoly.add_cylinder(flame, 0.0, 0.18, 0.55, 5, Vector3(-0.12, 0.3, -0.06), Color(1.0, 0.9, 0.5))
	_flame_mesh = flame.commit()
	_flame_material = LowPoly.make_material()
	_flame_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_material.emission_enabled = true
	_flame_material.emission = Color(1.0, 0.5, 0.15)

	# Crafting bench: a plank table on four legs, with a hammer and a block of stone on top.
	var bench := SurfaceTool.new()
	bench.begin(Mesh.PRIMITIVE_TRIANGLES)
	var plank := Color(0.66, 0.48, 0.29)
	LowPoly.add_box(bench, Vector3(1.6, 0.14, 0.9), Vector3(0, 0.93, 0), plank)
	for x in [-0.68, 0.68]:
		for z in [-0.35, 0.35]:
			LowPoly.add_box(bench, Vector3(0.14, 0.86, 0.14), Vector3(x, 0.43, z), bark)
	LowPoly.add_box(bench, Vector3(1.4, 0.08, 0.08), Vector3(0, 0.3, 0.35), bark)  # Footrest.
	LowPoly.add_box(bench, Vector3(0.36, 0.22, 0.3), Vector3(0.45, 1.11, 0.05), Color(0.55, 0.53, 0.50))
	LowPoly.add_box(bench, Vector3(0.5, 0.05, 0.05), Vector3(-0.3, 1.03, 0.1), bark)  # Hammer handle.
	LowPoly.add_box(bench, Vector3(0.1, 0.1, 0.2), Vector3(-0.55, 1.05, 0.1), Color(0.62, 0.64, 0.68))
	_prop_meshes["crafting_bench"] = bench.commit()


func _build_water() -> void:
	var plane := PlaneMesh.new()
	var size := CHUNK_SIZE * (MAX_VIEW_RADIUS * 2 + 3)
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
