extends RefCounted
## Helpers for building flat-shaded, vertex-coloured low-poly meshes.
## Godot treats clockwise triangles as front-facing; face_normal() matches that.


static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	return mat


static func face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (c - a).cross(b - a).normalized()


## Adds one triangle facing away from `center`.
static func add_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, center: Vector3, color: Color) -> void:
	var normal := face_normal(a, b, c)
	if normal.dot((a + b + c) / 3.0 - center) < 0.0:
		var t := b
		b = c
		c = t
		normal = -normal
	st.set_color(color)
	st.set_normal(normal)
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## A capped cylinder (or cone when top_radius is 0) centred on `center`.
static func add_cylinder(st: SurfaceTool, top_radius: float, bottom_radius: float, height: float, sides: int, center: Vector3, color: Color) -> void:
	var top := center + Vector3(0, height * 0.5, 0)
	var bottom := center - Vector3(0, height * 0.5, 0)
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := bottom + d0 * bottom_radius
		var b1 := bottom + d1 * bottom_radius
		var t0 := top + d0 * top_radius
		var t1 := top + d1 * top_radius
		if top_radius > 0.0:
			add_tri(st, b0, b1, t1, center, color)
			add_tri(st, b0, t1, t0, center, color)
			add_tri(st, top, t0, t1, center, color)
		else:
			add_tri(st, b0, b1, top, center, color)
		add_tri(st, bottom, b1, b0, center, color)


## A lumpy low-poly sphere, used for bushy tree tops and rocks.
static func add_blob(st: SurfaceTool, radius: float, center: Vector3, color: Color, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var sides := 7
	var rings := 4
	var points := []
	for r in rings + 1:
		var row := []
		var phi := PI * r / rings
		for s in sides:
			var theta := TAU * s / sides
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var jitter := 1.0 if r == 0 or r == rings else rng.randf_range(0.8, 1.15)
			row.append(center + dir * radius * jitter)
		points.append(row)

	for r in rings:
		for s in sides:
			var s1 := (s + 1) % sides
			var a: Vector3 = points[r][s]
			var b: Vector3 = points[r][s1]
			var c: Vector3 = points[r + 1][s]
			var d: Vector3 = points[r + 1][s1]
			if r > 0:
				add_tri(st, a, b, d, center, color)
			if r < rings - 1:
				add_tri(st, a, d, c, center, color)
