extends GdUnitTestSuite
## The view's pure parts (M37 task 4): the ground's flat faces and their numbers, and the instance
## buffers of scatter and cover.

const SEED := 1234

var _realm: RealmDef


func before_test() -> void:
	_realm = Layout.realms()[0]
	Layout.set_world_seed(SEED)


func after_test() -> void:
	Layout.set_world_seed(0)


func test_ground_faces_are_flat_and_unshared() -> void:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var arrays := TerrainView.chunk_arrays(_realm, SEED, at.x, at.y, at.z)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_int(vertices.size()).is_equal(Terrain.CHUNK_CELLS * Terrain.CHUNK_CELLS * 6)
	assert_int(normals.size()).is_equal(vertices.size())
	assert_int(colors.size()).is_equal(vertices.size())
	for i in range(0, vertices.size(), 3):
		var face := (vertices[i + 1] - vertices[i]).cross(vertices[i + 2] - vertices[i])
		if face.length() < 1e-6:
			continue
		# One normal and one set of numbers per face, the normal pointing out of the realm.
		assert_vector(normals[i]).is_equal_approx(normals[i + 1], Vector3.ONE * 1e-5)
		assert_vector(normals[i]).is_equal_approx(normals[i + 2], Vector3.ONE * 1e-5)
		assert_bool(colors[i] == colors[i + 1] and colors[i] == colors[i + 2]).is_true()
		assert_float(normals[i].dot(vertices[i].normalized())).is_greater(0.0)
		# Godot's front faces wind clockwise: the right hand cross product points inward.
		assert_float((-face.normalized()).dot(normals[i])).is_greater(0.99)


func test_ground_numbers_follow_the_ground() -> void:
	# The arrival is flat low moor: slope near 1, a small height.
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var colors: PackedColorArray = TerrainView.chunk_arrays(_realm, SEED, at.x, at.y, at.z)[
		Mesh.ARRAY_COLOR
	]
	var flat := 0
	for color in colors:
		if color.b > 0.95:
			flat += 1
	assert_int(flat).is_greater(colors.size() / 2)


func test_pack_groups_by_kind_and_variant() -> void:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var points := Scatter.points(_realm, SEED, Vector3i(at.x, at.y + 1, at.z))
	var groups := TerrainView.pack(points, 1.0, TerrainView.VARIANTS)
	var total := 0
	for key: int in groups:
		var group: Array = groups[key]
		assert_int((group[0] as PackedFloat32Array).size()).is_equal(int(group[1]) * 12)
		assert_int(key & 7).is_less(TerrainView.VARIANTS)
		total += int(group[1])
	assert_int(total).is_equal(points.size())
	var thin := TerrainView.pack(points, 0.5, TerrainView.VARIANTS)
	var thin_total := 0
	for key: int in thin:
		thin_total += int((thin[key] as Array)[1])
	assert_int(thin_total).is_less(total)
	assert_int(thin_total).is_greater(0)


func test_pack_buffer_is_the_points_transform() -> void:
	var at := Terrain.chunk_at(_realm, _realm.arrival)
	var points := Scatter.points(_realm, SEED, Vector3i(at.x, at.y + 1, at.z))
	var one: Array[Scatter.Point] = [points[0]]
	var groups := TerrainView.pack(one, 1.0, TerrainView.VARIANTS)
	assert_int(groups.size()).is_equal(1)
	var buffer: PackedFloat32Array = (groups.values()[0] as Array)[0]
	var origin := Vector3(buffer[3], buffer[7], buffer[11])
	assert_vector(origin).is_equal_approx(points[0].position, Vector3.ONE * 1e-3)
	# The model's up axis (the basis' y column) is the point's up, scaled like its shape.
	var up := Vector3(buffer[1], buffer[5], buffer[9])
	assert_vector(up.normalized()).is_equal_approx(points[0].up, Vector3.ONE * 1e-4)
	assert_float(up.length()).is_equal_approx(0.8 + 0.5 * points[0].size, 1e-4)
