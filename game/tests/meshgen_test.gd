extends GdUnitTestSuite
## The mesh kit (M36 task 1): helper triangle counts, determinism, flat shading, outward faces,
## the paint variation ranges, the palette's limits. Arrays only: nothing is committed to a mesh.

const EPS := 0.0001


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _count(arrays: Array) -> int:
	return MeshKit.triangles(arrays)


func _face_normal(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	return (a - c).cross(a - b).normalized()


## A rock and a trunk from every random helper, as a generator would build them.
func _build(seed_value: int) -> Array:
	var rng := _rng(seed_value)
	var palette := Palette.of("barrowlands")
	var rock := MeshKit.blob(1.0, 2, 0.2, 0.7, rng)
	rock = MeshKit.chip(rock, [Plane(Vector3(1, 1, 0).normalized(), 0.8)] as Array[Plane])
	var look := MeshKit.jitter(rng)
	MeshKit.paint(rock, palette.color(&"stone"), rng, Vector3.DOWN, look)
	var path := PackedVector3Array([Vector3(0, 0, 0), Vector3(0.1, 2, 0), Vector3(0.2, 4, 0.1)])
	var trunk := MeshKit.tube(path, PackedFloat32Array([0.4, 0.3, 0.15]), 8, 0.1, rng)
	MeshKit.paint(trunk, palette.color(&"bark"), rng, Vector3.DOWN, look)
	return MeshKit.merge([rock, trunk])


func test_triangle_counts() -> void:
	var rng := _rng(1)
	# Apex and bottom point: sides * (2 * 3 - 2).
	var profile := PackedVector2Array(
		[Vector2(0, 2), Vector2(1, 1), Vector2(1, 0), Vector2(0, -0.5)]
	)
	assert_int(_count(MeshKit.lathe(profile, 8, 0.1, rng))).is_equal(32)
	var hexagon := PackedVector2Array()
	for i in 6:
		hexagon.append(Vector2.from_angle(TAU * i / 6.0))
	assert_int(_count(MeshKit.extrude(hexagon, 1.0, 0.0))).is_equal(20)
	assert_int(_count(MeshKit.extrude(hexagon, 1.0, 0.1))).is_equal(44)
	assert_int(_count(MeshKit.box(Vector3(1, 2, 3), 0.0))).is_equal(12)
	assert_int(_count(MeshKit.box(Vector3(1, 2, 3), 0.1))).is_equal(44)
	var path := PackedVector3Array([Vector3.ZERO, Vector3.UP, Vector3.UP * 2, Vector3.UP * 3])
	var even := PackedFloat32Array([1, 1, 1, 1])
	assert_int(_count(MeshKit.tube(path, even, 6, 0.1, rng))).is_equal(48)
	var pointed := PackedFloat32Array([1, 1, 1, 0])
	assert_int(_count(MeshKit.tube(path, pointed, 6, 0.1, rng))).is_equal(36)
	for detail in 3:
		assert_int(_count(MeshKit.blob(1.0, detail, 0.2, 1.0, rng))).is_equal(20 * 4 ** detail)
	var layers := PackedVector3Array([Vector3(0, 2, 1), Vector3(1, 1.5, 1), Vector3(2, 1, 1)])
	assert_int(_count(MeshKit.cone_stack(layers, 7, 0.1, rng))).is_equal(42)
	var blade_path := PackedVector3Array(
		[Vector3.ZERO, Vector3(0, 0.1, 0), Vector3(0, 0.2, 0.05), Vector3(0, 0.3, 0.1)]
	)
	assert_int(_count(MeshKit.blade(blade_path, 0.05))).is_equal(5)
	assert_int(_count(MeshKit.blade(blade_path, 0.05, Vector3.BACK, true))).is_equal(10)


func test_same_seed_same_arrays() -> void:
	var a := _build(7)
	var b := _build(7)
	for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
		assert_bool(a[slot] == b[slot]).is_true()
	var other := _build(8)
	assert_bool(a[Mesh.ARRAY_VERTEX] == other[Mesh.ARRAY_VERTEX]).is_false()
	assert_bool(a[Mesh.ARRAY_COLOR] == other[Mesh.ARRAY_COLOR]).is_false()


func test_flat_and_unshared() -> void:
	var arrays := _build(3)
	var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_int(v.size() % 3).is_equal(0)
	assert_int(n.size()).is_equal(v.size())
	assert_int(c.size()).is_equal(v.size())
	for i in range(0, v.size(), 3):
		var face := _face_normal(v[i], v[i + 1], v[i + 2])
		for k in 3:
			assert_float(n[i + k].distance_to(face)).is_less(EPS)
			assert_bool(c[i + k] == c[i]).is_true()


func test_faces_point_outward() -> void:
	var rng := _rng(5)
	for arrays: Array in [MeshKit.blob(1.0, 2, 0.2, 0.7, rng), MeshKit.box(Vector3(1, 2, 3), 0.1)]:
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in range(0, v.size(), 3):
			assert_float(n[i].dot((v[i] + v[i + 1] + v[i + 2]) / 3.0)).is_greater(0.0)


func test_chip_flattens_corners() -> void:
	var rng := _rng(2)
	var plane := Plane(Vector3.RIGHT, 0.5)
	var rock := MeshKit.blob(1.0, 2, 0.1, 1.0, rng)
	var chipped := MeshKit.chip(rock, [plane] as Array[Plane])
	assert_int(_count(chipped)).is_equal(_count(rock))
	var cut := false
	for p in chipped[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		assert_float(plane.distance_to(p)).is_less(EPS)
		cut = cut or absf(plane.distance_to(p)) < EPS
	assert_bool(cut).is_true()


func test_paint_stays_in_the_variation() -> void:
	var budgets := Budgets.data()
	var base := Palette.of("barrowlands").color(&"stone")
	var arrays := MeshKit.blob(1.0, 2, 0.2, 1.0, _rng(9))
	for seed_value in 20:
		var painted := MeshKit.paint(arrays.duplicate(), base, _rng(seed_value))
		var v: PackedVector3Array = painted[Mesh.ARRAY_VERTEX]
		var c: PackedColorArray = painted[Mesh.ARRAY_COLOR]
		var most := (1.0 + budgets.instance_value) * (1.0 + budgets.face_value)
		var least := (1.0 - budgets.instance_value) * (1.0 - budgets.face_value)
		least *= 1.0 - budgets.down_darken
		for i in range(0, v.size(), 3):
			var ratio := c[i].v / base.v
			assert_float(ratio).is_between(least - EPS, most + EPS)
			assert_float(c[i].s).is_equal_approx(base.s, EPS)
			assert_float(c[i].a).is_equal(base.a)
			var hue := absf(c[i].h - base.h) * 360.0
			assert_float(hue).is_less(budgets.instance_hue + EPS)
	# Darkening: faces at the bottom are darker than at the top.
	var painted := MeshKit.paint(arrays.duplicate(), base, _rng(1), Vector3.DOWN, Vector2.ZERO)
	var v: PackedVector3Array = painted[Mesh.ARRAY_VERTEX]
	var c: PackedColorArray = painted[Mesh.ARRAY_COLOR]
	var low := 0
	var high := 0
	for i in range(0, v.size(), 3):
		if v[i].y < v[low].y:
			low = i
		if v[i].y > v[high].y:
			high = i
	assert_float(c[low].v).is_less(c[high].v)


func test_palette_follows_the_style_sheet() -> void:
	var palette := Palette.of("barrowlands")
	assert_bool(Palette.of("barrowlands") == palette).is_true()
	for role in Palette.ROLES:
		var c := palette.color(StringName(role))
		assert_float(c.a).is_between(0.05, 1.0)
		if role in Palette.MEANING:
			continue
		assert_float(c.s).is_less(0.45)
		assert_float(c.v).is_less(0.6)
	assert_int(palette.colors.size()).is_equal(Palette.ROLES.size())
	assert_int(palette.roughness.size()).is_equal(Palette.ROLES.size())


func test_budgets_table() -> void:
	var budgets := Budgets.data()
	assert_int(budgets.limit("tree_old", Budgets.FULL)).is_equal(1800)
	assert_int(budgets.limit("grass_tuft", Budgets.FAR)).is_equal(-1)
	for kind: String in budgets.kinds:
		var steps: Vector3i = budgets.kinds[kind]
		assert_bool(steps.x > steps.y and (steps.z < steps.y)).is_true()
	assert_float(budgets.full_distance).is_less(budgets.half_distance)


## Every registered generator is held to the style sheet (docs/STYLE.md), so a new kind needs no
## new test.
func test_every_generator_keeps_the_budgets() -> void:
	var palette := Palette.of("barrowlands")
	var budgets := Budgets.data()
	assert_array(Generators.ids()).contains(["rock", "pine_young"])
	for id in Generators.ids():
		for variant in 4:
			var levels := Generators.arrays(id, variant, palette)
			for lod in 3:
				var limit := budgets.limit(Generators.budget_kind(id), lod)
				var tris := _count(levels[lod])
				if limit < 0:
					assert_int(tris).is_equal(0)
				else:
					assert_int(tris).is_between(1, limit)


func test_every_generator_is_deterministic() -> void:
	var palette := Palette.of("barrowlands")
	for id in Generators.ids():
		var a := Generators.arrays(id, 11, palette)
		var b := Generators.arrays(id, 11, palette)
		var other := Generators.arrays(id, 12, palette)
		for lod in 3:
			for slot in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
				assert_bool(a[lod][slot] == b[lod][slot]).is_true()
		assert_bool(a[0][Mesh.ARRAY_VERTEX] == other[0][Mesh.ARRAY_VERTEX]).is_false()


## Every vertex color is one role's color within the variation of `MeshKit.paint`.
func test_every_generator_uses_only_palette_colors() -> void:
	var palette := Palette.of("barrowlands")
	var budgets := Budgets.data()
	var most := (1.0 + budgets.instance_value) * (1.0 + budgets.face_value)
	var least := (1.0 - budgets.instance_value) * (1.0 - budgets.face_value)
	least *= 1.0 - budgets.down_darken
	for id in Generators.ids():
		for lod_arrays: Array in Generators.arrays(id, 5, palette):
			for c in lod_arrays[Mesh.ARRAY_COLOR] as PackedColorArray:
				var found := false
				for role in Palette.ROLES:
					found = found or _within_role(c, palette.color(StringName(role)), least, most)
				assert_bool(found).is_true()


func _within_role(c: Color, base: Color, least: float, most: float) -> bool:
	var hue := absf(c.h - base.h)
	hue = minf(hue, 1.0 - hue) * 360.0
	var ratio := c.v / base.v
	return (
		absf(c.s - base.s) < 0.001
		and absf(c.a - base.a) < 0.001
		and hue < Budgets.data().instance_hue + 0.01
		and ratio > least - 0.001
		and ratio < most + 0.001
	)


func test_every_generator_far_level_keeps_the_size() -> void:
	var palette := Palette.of("barrowlands")
	for id in Generators.ids():
		for variant in 4:
			var levels := Generators.arrays(id, variant, palette)
			var full := Generators.bounds(levels[0])
			for lod in [1, 2]:
				if _count(levels[lod]) == 0:
					continue
				var box := Generators.bounds(levels[lod])
				for axis in 3:
					var slack: float = full.size[axis] * 0.1
					assert_float(box.size[axis]).is_equal_approx(full.size[axis], slack)
					assert_float(box.position[axis]).is_equal_approx(full.position[axis], slack)
