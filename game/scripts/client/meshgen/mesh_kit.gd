class_name MeshKit
extends RefCounted
## Flat-shaded, vertex-colored models from code (M36, docs/STYLE.md). Every helper returns mesh
## arrays (Mesh.ARRAY_VERTEX, ARRAY_NORMAL, ARRAY_COLOR; no index) with three own vertices per
## triangle and the face's normal on all three, so shading is flat. The helpers touch no scene
## tree and create no resources: they run on a worker thread. Colors start white; `paint` gives
## them their palette color and variation. `commit` joins parts into one ArrayMesh on the main
## thread. Winding is never trusted: `_add` orients each triangle away from a point inside the
## shape (so profiles and paths need only be roughly convex per segment).

const EPS := 1e-6
const _T := 1.618034
const _ICO_VERTS: Array[Vector3] = [
	Vector3(-1, _T, 0),
	Vector3(1, _T, 0),
	Vector3(-1, -_T, 0),
	Vector3(1, -_T, 0),
	Vector3(0, -1, _T),
	Vector3(0, 1, _T),
	Vector3(0, -1, -_T),
	Vector3(0, 1, -_T),
	Vector3(_T, 0, -1),
	Vector3(_T, 0, 1),
	Vector3(-_T, 0, -1),
	Vector3(-_T, 0, 1),
]
const _ICO_FACES: Array[Vector3i] = [
	Vector3i(0, 11, 5),
	Vector3i(0, 5, 1),
	Vector3i(0, 1, 7),
	Vector3i(0, 7, 10),
	Vector3i(0, 10, 11),
	Vector3i(1, 5, 9),
	Vector3i(5, 11, 4),
	Vector3i(11, 10, 2),
	Vector3i(10, 7, 6),
	Vector3i(7, 1, 8),
	Vector3i(3, 9, 4),
	Vector3i(3, 4, 2),
	Vector3i(3, 2, 6),
	Vector3i(3, 6, 8),
	Vector3i(3, 8, 9),
	Vector3i(4, 9, 5),
	Vector3i(2, 4, 11),
	Vector3i(6, 2, 10),
	Vector3i(8, 6, 7),
	Vector3i(9, 8, 1),
]

static var _material: ShaderMaterial


## The one shared material of every generated model. Main thread.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/flat.gdshader")
	return _material


## Joins parts (arrays from the helpers) into one mesh arrays. Worker safe.
static func merge(parts: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for part: Array in parts:
		verts.append_array(part[Mesh.ARRAY_VERTEX])
		normals.append_array(part[Mesh.ARRAY_NORMAL])
		colors.append_array(part[Mesh.ARRAY_COLOR])
	return _arrays(verts, normals, colors)


## One ArrayMesh from parts, with the shared material. Main thread.
static func commit(parts: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var arrays := merge(parts)
	if not (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, material())
	return mesh


static func triangles(arrays: Array) -> int:
	return (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


## Per-instance jitter for `paint`: x scales the value, y the hue, both in -1..1. Draw it once
## per model and pass it to every part's `paint` so the parts share one instance variation.
static func jitter(rng: RandomNumberGenerator) -> Vector2:
	return Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0))


## Colors every face: the palette color (roughness in its alpha) with the style sheet's variation:
## per instance (value and hue, `instance`), per face (value) and darkening up to `down_darken`
## toward `down` (the only ambient occlusion drawn). Changes and returns `arrays`.
static func paint(
	arrays: Array,
	color: Color,
	rng: RandomNumberGenerator,
	down := Vector3.DOWN,
	instance := Vector2.INF
) -> Array:
	var budgets := Budgets.data()
	if instance == Vector2.INF:
		instance = jitter(rng)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var lo := INF
	var hi := -INF
	for v in verts:
		var d := v.dot(down)
		lo = minf(lo, d)
		hi = maxf(hi, d)
	var hue := fposmod(color.h + instance.y * budgets.instance_hue / 360.0, 1.0)
	var value := color.v * (1.0 + instance.x * budgets.instance_value)
	var colors := PackedColorArray()
	colors.resize(verts.size())
	for i in range(0, verts.size(), 3):
		var centroid := (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var low := 0.0 if hi - lo < EPS else (centroid.dot(down) - lo) / (hi - lo)
		var face := value * (1.0 + rng.randf_range(-1.0, 1.0) * budgets.face_value)
		face *= 1.0 - budgets.down_darken * low
		var painted := Color.from_hsv(hue, color.s, minf(face, 1.0), color.a)
		colors[i] = painted
		colors[i + 1] = painted
		colors[i + 2] = painted
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## A solid of revolution around Y: `profile` is (radius, height) points bottom to top, `sides`
## corners, each corner's radius off by up to `wobble` (a fraction, the same on every ring),
## starting at angle `phase`. A radius of 0 is a point (apex or pole): its quads become single
## triangles. Triangles: sides * (2 * (points - 1) - points with radius 0 at an end).
## No caps: close the shape with a profile point at radius 0. Segments must climb (or fall).
static func lathe(
	profile: PackedVector2Array, sides: int, wobble: float, rng: RandomNumberGenerator, phase := 0.0
) -> Array:
	var corner := PackedFloat32Array()
	for i in sides:
		corner.append(1.0 + rng.randf_range(-wobble, wobble))
	var rings: Array[PackedVector3Array] = []
	for p in profile:
		var ring := PackedVector3Array()
		for i in sides:
			var angle := phase + TAU * i / sides
			var r := p.x * corner[i] if p.x > EPS else 0.0
			ring.append(Vector3(cos(angle) * r, p.y, sin(angle) * r))
		rings.append(ring)
	var v := PackedVector3Array()
	for k in profile.size() - 1:
		var inside := Vector3(0.0, (profile[k].y + profile[k + 1].y) * 0.5, 0.0)
		for i in sides:
			var j := (i + 1) % sides
			_quad(v, rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], inside)
	return _finish(v)


## A prism: `outline` (points in the XY plane, roughly convex) pushed `depth` along Z, centered.
## With `bevel` (a length, under half of depth) the cap edges are cut by one chamfer.
## Triangles: 4n - 4 without bevel, 8n - 4 with (n = outline points).
static func extrude(outline: PackedVector2Array, depth: float, bevel: float) -> Array:
	var n := outline.size()
	var mid := Vector2.ZERO
	for p in outline:
		mid += p
	mid /= n
	var spread := 0.0
	for p in outline:
		spread += p.distance_to(mid)
	spread /= n
	var half := depth * 0.5
	var wall_z := half - bevel
	var k := clampf(1.0 - bevel / maxf(spread, EPS), 0.1, 1.0)
	var inset := PackedVector2Array()
	for p in outline:
		inset.append(mid + (p - mid) * k)
	var v := PackedVector3Array()
	for i in n:
		var j := (i + 1) % n
		var inside := Vector3(mid.x, mid.y, 0.0)
		_quad(
			v,
			_xyz(outline[i], -wall_z),
			_xyz(outline[j], -wall_z),
			_xyz(outline[j], wall_z),
			_xyz(outline[i], wall_z),
			inside
		)
		if bevel > 0.0:
			for s in [-1.0, 1.0]:
				var a: float = s * wall_z
				var b: float = s * half
				_quad(
					v,
					_xyz(outline[i], a),
					_xyz(outline[j], a),
					_xyz(inset[j], b),
					_xyz(inset[i], b),
					inside
				)
	var cap := inset if bevel > 0.0 else outline
	var tris := Geometry2D.triangulate_polygon(cap)
	assert(not tris.is_empty(), "extrude outline is not a simple polygon")
	for s in [-1.0, 1.0]:
		for t in range(0, tris.size(), 3):
			var z: float = s * half
			_add(
				v,
				_xyz(cap[tris[t]], z),
				_xyz(cap[tris[t + 1]], z),
				_xyz(cap[tris[t + 2]], z),
				Vector3(mid.x, mid.y, 0.0)
			)
	return _finish(v)


## A box of `size`, centered. With `bevel` (a length) every edge and corner is chamfered:
## 12 triangles without bevel, 44 with.
static func box(size: Vector3, bevel: float) -> Array:
	var h := size * 0.5
	var v := PackedVector3Array()
	if bevel <= 0.0:
		for axis in 3:
			for s in [-1.0, 1.0]:
				var q := PackedVector3Array()
				for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
					q.append(_corner(h, axis, s, c, 0.0))
				_quad(v, q[0], q[1], q[2], q[3], Vector3.ZERO)
		return _finish(v)
	# Corner (sx, sy, sz) has one vertex on each of its three faces, pulled in by `bevel`.
	for axis in 3:
		for s in [-1.0, 1.0]:
			var q := PackedVector3Array()
			for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				q.append(_corner(h, axis, s, c, bevel))
			_quad(v, q[0], q[1], q[2], q[3], Vector3.ZERO)
	for a in 3:
		var b := (a + 1) % 3
		var along := (a + 2) % 3
		for sa in [-1.0, 1.0]:
			for sb in [-1.0, 1.0]:
				var ends: Array[PackedVector3Array] = []
				for sc in [-1.0, 1.0]:
					var pair := PackedVector3Array()
					for axis in [a, b]:
						var s := Vector3.ZERO
						s[a] = sa
						s[b] = sb
						s[along] = sc
						pair.append(_chamfer_vertex(h, s, axis, bevel))
					ends.append(pair)
				_quad(v, ends[0][0], ends[0][1], ends[1][1], ends[1][0], Vector3.ZERO)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var s := Vector3(sx, sy, sz)
				_add(
					v,
					_chamfer_vertex(h, s, 0, bevel),
					_chamfer_vertex(h, s, 1, bevel),
					_chamfer_vertex(h, s, 2, bevel),
					Vector3.ZERO
				)
	return _finish(v)


## A tube along `path` with a radius per point (`radii`), `sides` corners off by up to `wobble`
## (fraction), closed with a fan at each end that has a radius. Trunks, limbs, horns.
## Triangles: sides * (2 * (points - 1) + ends with a radius - ends without one).
static func tube(
	path: PackedVector3Array,
	radii: PackedFloat32Array,
	sides: int,
	wobble: float,
	rng: RandomNumberGenerator
) -> Array:
	var corner := PackedFloat32Array()
	for i in sides:
		corner.append(1.0 + rng.randf_range(-wobble, wobble))
	var count := path.size()
	var up := (path[1] - path[0]).normalized().cross(Vector3.RIGHT)
	if up.length_squared() < 0.01:
		up = (path[1] - path[0]).normalized().cross(Vector3.UP)
	var rings: Array[PackedVector3Array] = []
	for k in count:
		var before := path[maxi(k - 1, 0)]
		var after := path[mini(k + 1, count - 1)]
		var tangent := (after - before).normalized()
		up = (up - tangent * up.dot(tangent)).normalized()
		var side := tangent.cross(up)
		var ring := PackedVector3Array()
		for i in sides:
			var angle := TAU * i / sides
			var r := radii[k] * corner[i]
			ring.append(path[k] + (up * cos(angle) + side * sin(angle)) * r)
		rings.append(ring)
	var v := PackedVector3Array()
	for k in count - 1:
		var inside := (path[k] + path[k + 1]) * 0.5
		for i in sides:
			var j := (i + 1) % sides
			_quad(v, rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i], inside)
	for end in [0, count - 1]:
		if radii[end] <= EPS:
			continue
		var inside := path[1] if end == 0 else path[count - 2]
		for i in sides:
			_add(v, path[end], rings[end][i], rings[end][(i + 1) % sides], inside)
	return _finish(v)


## A displaced icosphere (rocks, leaf clumps): 20 * 4^detail triangles, `radius`, each vertex
## moved along its direction by up to `noise` (a fraction of the radius) by a few low frequency
## waves, then Y scaled by `flatten` (1 round, 0.6 a flat rock).
static func blob(
	radius: float, detail: int, noise: float, flatten: float, rng: RandomNumberGenerator
) -> Array:
	var points: Array[Vector3] = []
	for p in _ICO_VERTS:
		points.append(p.normalized())
	var faces: Array[Vector3i] = _ICO_FACES.duplicate()
	for step in detail:
		var cache := {}
		var next: Array[Vector3i] = []
		for f in faces:
			var ab := _midpoint(points, cache, f.x, f.y)
			var bc := _midpoint(points, cache, f.y, f.z)
			var ca := _midpoint(points, cache, f.z, f.x)
			next.append(Vector3i(f.x, ab, ca))
			next.append(Vector3i(f.y, bc, ab))
			next.append(Vector3i(f.z, ca, bc))
			next.append(Vector3i(ab, bc, ca))
		faces = next
	var waves: Array[Vector3] = []
	var phases := PackedFloat32Array()
	for k in 3:
		var axis := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		waves.append(axis * rng.randf_range(1.0, 2.5))
		phases.append(rng.randf_range(0.0, TAU))
	var shaped := PackedVector3Array()
	for p in points:
		var bump := 0.0
		for k in 3:
			bump += sin(p.dot(waves[k]) * PI + phases[k]) / 3.0
		var q := p * radius * (1.0 + noise * bump)
		q.y *= flatten
		shaped.append(q)
	var v := PackedVector3Array()
	for f in faces:
		_add(v, shaped[f.x], shaped[f.y], shaped[f.z], Vector3.ZERO)
	return _finish(v)


## Conifer layers: `layers` is one Vector3 per layer (base height, base radius, height). Each is a
## cone with a shallow underside, `sides` corners, its own wobble and angle. 2 * sides triangles
## per layer.
static func cone_stack(
	layers: PackedVector3Array, sides: int, wobble: float, rng: RandomNumberGenerator
) -> Array:
	var parts: Array = []
	for layer in layers:
		var profile := PackedVector2Array(
			[
				Vector2(0.0, layer.x + layer.z),
				Vector2(layer.y, layer.x),
				Vector2(0.0, layer.x + layer.z * 0.15)
			]
		)
		parts.append(lathe(profile, sides, wobble, rng, rng.randf_range(0.0, TAU)))
	return merge(parts)


## A bent strip along `path` (grass, fronds): `width` at the base narrowing to a point at the
## tip, across the X axis (or `across`), seen from `facing`. One sided, or both with `two_sided`.
## Triangles: 2 * (points - 1) - 1, doubled when two sided.
static func blade(
	path: PackedVector3Array,
	width: float,
	facing := Vector3.BACK,
	two_sided := false,
	across := Vector3.RIGHT
) -> Array:
	var count := path.size()
	var v := PackedVector3Array()
	var towards := -facing * 10.0
	for k in count - 1:
		var w0 := width * (1.0 - float(k) / (count - 1)) * 0.5
		var w1 := width * (1.0 - float(k + 1) / (count - 1)) * 0.5
		var a := path[k] - across * w0
		var b := path[k] + across * w0
		var c := path[k + 1] + across * w1
		var d := path[k + 1] - across * w1
		_quad(v, a, b, c, d, path[k] + towards)
		if two_sided:
			_quad(v, a, b, c, d, path[k] - towards)
	return _finish(v)


## Cuts corners off: every vertex beyond a plane (on its positive side) is pushed onto it, so a
## corner becomes a flat facet. Same triangle count. Returns new arrays.
static func chip(arrays: Array, planes: Array[Plane]) -> Array:
	var v: PackedVector3Array = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in v.size():
		for plane in planes:
			if plane.distance_to(v[i]) > 0.0:
				v[i] = plane.project(v[i])
	var old: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in range(0, v.size(), 3):
		if _normal(v[i], v[i + 1], v[i + 2]).dot(old[i]) < 0.0:
			var swap := v[i + 1]
			v[i + 1] = v[i + 2]
			v[i + 2] = swap
	var out := _finish(v)
	out[Mesh.ARRAY_COLOR] = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	return out


## The unit normal of a face as the engine reads winding (clockwise is the front).
static func _normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (a - c).cross(a - b).normalized()


## Appends one triangle, wound so its normal points away from `inside`; flat ones are dropped.
static func _add(
	v: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, inside: Vector3
) -> void:
	var n := (a - c).cross(a - b)
	if n.length_squared() < EPS:
		return
	if n.dot((a + b + c) / 3.0 - inside) < 0.0:
		v.append_array(PackedVector3Array([a, c, b]))
	else:
		v.append_array(PackedVector3Array([a, b, c]))


static func _quad(
	v: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3
) -> void:
	_add(v, a, b, c, inside)
	_add(v, a, c, d, inside)


static func _xyz(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)


## Face vertex of a box: on the face `axis` * `s`, at corner `c` (-1 or 1 in the two other axes).
static func _corner(h: Vector3, axis: int, s: float, c: Vector2, bevel: float) -> Vector3:
	var p := Vector3.ZERO
	p[axis] = s * h[axis]
	p[(axis + 1) % 3] = c.x * (h[(axis + 1) % 3] - bevel)
	p[(axis + 2) % 3] = c.y * (h[(axis + 2) % 3] - bevel)
	return p


## The vertex of corner `s` (signs) that lies on face `axis`: full extent on that axis, pulled in
## by `bevel` on the other two.
static func _chamfer_vertex(h: Vector3, s: Vector3, axis: int, bevel: float) -> Vector3:
	var p := Vector3.ZERO
	for i in 3:
		p[i] = s[i] * (h[i] if i == axis else h[i] - bevel)
	return p


static func _midpoint(points: Array[Vector3], cache: Dictionary, a: int, b: int) -> int:
	var key := mini(a, b) * 1000003 + maxi(a, b)
	if not cache.has(key):
		points.append(((points[a] + points[b]) * 0.5).normalized())
		cache[key] = points.size() - 1
	return cache[key]


## Mesh arrays from triangle vertices: face normals, white color.
static func _finish(v: PackedVector3Array) -> Array:
	var normals := PackedVector3Array()
	normals.resize(v.size())
	var colors := PackedColorArray()
	colors.resize(v.size())
	colors.fill(Color.WHITE)
	for i in range(0, v.size(), 3):
		var n := _normal(v[i], v[i + 1], v[i + 2])
		normals[i] = n
		normals[i + 1] = n
		normals[i + 2] = n
	return _arrays(v, normals, colors)


static func _arrays(v: PackedVector3Array, n: PackedVector3Array, c: PackedColorArray) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	arrays[Mesh.ARRAY_COLOR] = c
	return arrays
