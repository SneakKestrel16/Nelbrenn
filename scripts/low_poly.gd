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


## `color` made a little lighter or darker, the same way every time for the
## same `key`. Gives flat faces a hand-painted, uneven look.
static func shade(color: Color, amount: float, key: int) -> Color:
	if amount <= 0.0:
		return color
	var r := fposmod(sin(float(key) * 12.9898 + 78.233) * 43758.5453, 1.0) * 2.0 - 1.0
	return color.lightened(r * amount) if r > 0.0 else color.darkened(-r * amount)


## A capped tube from `a` to `b` in any direction (branches, arms, legs).
## `vary` shades each face slightly differently.
static func add_limb(st: SurfaceTool, a: Vector3, b: Vector3, radius_a: float, radius_b: float, sides: int, color: Color, vary := 0.0) -> void:
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3.UP if absf(axis.y) < 0.95 else Vector3.RIGHT).normalized()
	var up := side.cross(axis)
	var middle := (a + b) * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := side * cos(a0) + up * sin(a0)
		var d1 := side * cos(a1) + up * sin(a1)
		var c := shade(color, vary, i * 7 + sides)
		add_tri(st, a + d0 * radius_a, a + d1 * radius_a, b + d1 * radius_b, middle, c)
		add_tri(st, a + d0 * radius_a, b + d1 * radius_b, b + d0 * radius_b, middle, c)
		if radius_b > 0.0:
			add_tri(st, b, b + d0 * radius_b, b + d1 * radius_b, a, c)
		if radius_a > 0.0:
			add_tri(st, a, a + d1 * radius_a, a + d0 * radius_a, b, c)


## A capped cylinder (or cone when top_radius is 0) centred on `center`.
## `vary` shades each face slightly differently.
static func add_cylinder(st: SurfaceTool, top_radius: float, bottom_radius: float, height: float, sides: int, center: Vector3, color: Color, vary := 0.0) -> void:
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
		var c := shade(color, vary, i * 13 + sides)
		if top_radius > 0.0:
			add_tri(st, b0, b1, t1, center, c)
			add_tri(st, b0, t1, t0, center, c)
			add_tri(st, top, t0, t1, center, c)
		else:
			add_tri(st, b0, b1, top, center, c)
		add_tri(st, bottom, b1, b0, center, c)


## A box of the given size centred on `center`.
static func add_box(st: SurfaceTool, size: Vector3, center: Vector3, color: Color) -> void:
	var h := size * 0.5
	var c := func(x: float, y: float, z: float) -> Vector3: return center + Vector3(x * h.x, y * h.y, z * h.z)
	var faces := [
		[c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, 1, -1), c.call(-1, 1, -1)],
		[c.call(-1, -1, 1), c.call(1, -1, 1), c.call(1, 1, 1), c.call(-1, 1, 1)],
		[c.call(-1, -1, -1), c.call(-1, 1, -1), c.call(-1, 1, 1), c.call(-1, -1, 1)],
		[c.call(1, -1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(1, -1, 1)],
		[c.call(-1, -1, -1), c.call(1, -1, -1), c.call(1, -1, 1), c.call(-1, -1, 1)],
		[c.call(-1, 1, -1), c.call(1, 1, -1), c.call(1, 1, 1), c.call(-1, 1, 1)],
	]
	for f in faces:
		add_tri(st, f[0], f[1], f[2], center, color)
		add_tri(st, f[0], f[2], f[3], center, color)


## A lumpy low-poly sphere, used for bushy tree tops and rocks.
## `vary` shades each face slightly differently; `squash` scales it vertically;
## `detail` 1 gives a few more faces.
static func add_blob(st: SurfaceTool, radius: float, center: Vector3, color: Color, rng_seed: int, vary := 0.0, squash := 1.0, detail := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var sides := 7 + detail * 2
	var rings := 4 + detail
	var points := []
	for r in rings + 1:
		var row := []
		var phi := PI * r / rings
		for s in sides:
			var theta := TAU * s / sides
			var dir := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var jitter := 1.0 if r == 0 or r == rings else rng.randf_range(0.8, 1.15)
			var offset := dir * radius * jitter
			offset.y *= squash
			row.append(center + offset)
		points.append(row)

	for r in rings:
		for s in sides:
			var s1 := (s + 1) % sides
			var a: Vector3 = points[r][s]
			var b: Vector3 = points[r][s1]
			var c: Vector3 = points[r + 1][s]
			var d: Vector3 = points[r + 1][s1]
			if r > 0:
				add_tri(st, a, b, d, center, shade(color, vary, rng_seed + r * 31 + s * 2))
			if r < rings - 1:
				add_tri(st, a, d, c, center, shade(color, vary, rng_seed + r * 31 + s * 2 + 1))
