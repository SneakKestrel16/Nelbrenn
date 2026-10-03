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

var _resources := {}              ## Vector2i -> Array of harvestable nodes in that chunk
var _resource_by_id := {}         ## node id -> node, for loaded chunks
var _harvested := {}              ## node id -> unix time it grows back (saved)
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
		mm.mesh = _prop_meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			var node: Dictionary = list[i]
			node["mm"] = mm
			node["index"] = i
			if _harvested.has(node["id"]):  # Still regrowing since it was harvested.
				node["alive"] = false
				if node["collider"]:
					node["collider"].disabled = true
			_set_instance(node, node["xform"] if node["alive"] else _hidden(node))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _terrain_material
		chunk.add_child(mmi)

	_resources[coord] = nodes
	for node in nodes:
		_resource_by_id[node["id"]] = node


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
	return {"harvested": _harvested.duplicate()}


func apply_save_data(data: Dictionary) -> void:
	_harvested.clear()
	var saved = data.get("harvested", {})
	if saved is Dictionary:
		for id in saved:
			_harvested[String(id)] = float(saved[id])


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
	node["mm"].set_instance_transform(node["index"], xform)


## Harvested things are squashed to nothing rather than removed, so the
## MultiMesh doesn't need rebuilding.
func _hidden(node: Dictionary) -> Transform3D:
	return Transform3D(Basis.from_scale(Vector3.ZERO), node["xform"].origin)


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

	# Ore deposits: a dark boulder studded with lumps of the ore's colour.
	var ore_colors := {
		"coal": Color(0.10, 0.10, 0.11), "copper": Color(0.85, 0.50, 0.25),
		"iron": Color(0.78, 0.52, 0.42), "gold": Color(1.0, 0.82, 0.25),
	}
	for kind in ore_colors:
		var ore := SurfaceTool.new()
		ore.begin(Mesh.PRIMITIVE_TRIANGLES)
		var middle := Vector3(0, 0.35, 0)
		LowPoly.add_blob(ore, 0.9, middle, Color(0.42, 0.40, 0.38), 31)
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		for j in 7:
			var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.1, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
			LowPoly.add_blob(ore, rng.randf_range(0.18, 0.28), middle + dir * 0.82, ore_colors[kind], 40 + j)
		_prop_meshes[kind] = ore.commit()

	# Crystals: pale spikes growing out of a small rock.
	var crystal := SurfaceTool.new()
	crystal.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(crystal, 0.6, Vector3(0, 0.1, 0), Color(0.42, 0.40, 0.38), 33)
	for spike in [[0.0, 0.0, 0.22, 1.6], [0.35, 0.15, 0.16, 1.1], [-0.3, 0.2, 0.15, 0.9], [0.1, -0.35, 0.14, 1.0]]:
		var tint := Color(0.55, 0.85, 0.95).lerp(Color(0.75, 0.6, 0.95), absf(spike[0]) * 2.0)
		LowPoly.add_cylinder(crystal, 0.0, spike[2], spike[3], 5, Vector3(spike[0], 0.3 + spike[3] * 0.5, spike[1]), tint)
	_prop_meshes["crystal"] = crystal.commit()

	# Berry bush: two green puffs dotted with red berries.
	var bush := SurfaceTool.new()
	bush.begin(Mesh.PRIMITIVE_TRIANGLES)
	LowPoly.add_blob(bush, 0.75, Vector3(0, 0.55, 0), Color(0.24, 0.50, 0.22), 51)
	LowPoly.add_blob(bush, 0.55, Vector3(0.5, 0.45, 0.3), Color(0.28, 0.55, 0.24), 52)
	var berry_rng := RandomNumberGenerator.new()
	berry_rng.seed = 53
	for j in 9:
		var dir := Vector3(berry_rng.randf_range(-1.0, 1.0), berry_rng.randf_range(0.0, 1.0), berry_rng.randf_range(-1.0, 1.0)).normalized()
		LowPoly.add_blob(bush, 0.1, Vector3(0, 0.55, 0) + dir * 0.75, Color(0.80, 0.12, 0.22), 60 + j)
	_prop_meshes["berry_bush"] = bush.commit()


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
