extends GdUnitTestSuite
## Terrain is a pure function of (realm, seed, direction): a fixed seed gives a fixed fingerprint,
## chunks share their edge vertices exactly (across cube faces too), most of the ground is
## walkable, and two Worlds built from one seed get the same ground.

const SEED := 1234
## Hash of the heights at Terrain.SAMPLES directions under SEED. If this changes on purpose
## (new noise numbers), print Terrain.fingerprint and update it; if it changes by accident,
## peers would desync. CI's check job runs this on ubuntu only (release.yml); the three export
## runners do not run tests.
const FINGERPRINT := -2947287787477998241
## SimPlayer.floor_max_angle in degrees.
const WALKABLE_DEGREES := 50.0


func _realm() -> RealmDef:
	return Layout.realms()[0]


func test_fixed_seed_gives_fixed_fingerprint() -> void:
	assert_int(Terrain.fingerprint(_realm(), SEED)).is_equal(FINGERPRINT)


func test_seeds_and_realms_differ() -> void:
	var realm := _realm()
	assert_int(Terrain.fingerprint(realm, SEED + 1)).is_not_equal(FINGERPRINT)
	var other := realm.duplicate() as RealmDef
	other.seed_salt += 1
	assert_int(Terrain.fingerprint(other, SEED)).is_not_equal(FINGERPRINT)


func test_world_built_twice_same_ground() -> void:
	var a: World = auto_free(World.new(false))
	var b: World = auto_free(World.new(false))
	a.build(SEED, "x")
	b.build(SEED, "y")
	assert_int(Terrain.fingerprint(_realm(), a.world_seed)).is_equal(
		Terrain.fingerprint(_realm(), b.world_seed)
	)


func test_realm_placement() -> void:
	var realm := _realm()
	assert_float(realm.center.length()).is_less(6000.0)
	assert_float(realm.center.length()).is_greater(realm.radius + 500.0)
	assert_float(realm.center.distance_to(Layout.HUB)).is_greater(realm.radius + 500.0)
	assert_object(Layout.realm_at(realm.center + Vector3(0, realm.radius + 100.0, 0))).is_same(
		realm
	)
	assert_object(Layout.realm_at(Vector3.ZERO)).is_null()
	assert_object(Layout.realm_at(Layout.HUB)).is_null()


## Vertex position -> set of cube faces that produced it, over the given chunks.
func _vertex_faces(realm: RealmDef, chunks: Array) -> Dictionary:
	var seen := {}
	for c: Array in chunks:
		for p in Terrain.chunk_arrays(realm, SEED, c[0], c[1], c[2]):
			if not seen.has(p):
				seen[p] = {}
			seen[p][c[0]] = true
	return seen


func test_neighbouring_chunks_share_edge() -> void:
	var across_x := _vertex_faces(_realm(), [[0, 3, 4], [0, 4, 4]])
	var across_y := _vertex_faces(_realm(), [[5, 7, 7], [5, 7, 8]])
	for seen: Dictionary in [across_x, across_y]:
		# Two chunks of (CHUNK_CELLS + 1)^2 vertices overlap in one row of CHUNK_CELLS + 1.
		assert_int(seen.size()).is_equal(
			2 * (Terrain.CHUNK_CELLS + 1) ** 2 - Terrain.CHUNK_CELLS - 1
		)


## A small realm keeps this fast (debug builds build a chunk in about 15 ms); the edge logic is
## the same at any radius.
func test_cube_edges_match() -> void:
	var realm := _realm().duplicate() as RealmDef
	realm.radius = 200.0
	var per_face := Terrain.chunks_per_face(realm)
	var chunks := []
	for face in 6:
		for k in per_face:
			for side in [0, per_face - 1]:
				chunks.append([face, k, side])
				chunks.append([face, side, k])
	var seen := _vertex_faces(realm, chunks)
	var on_two := 0
	var on_three := 0
	for p: Vector3 in seen:
		var faces := (seen[p] as Dictionary).size()
		on_two += 1 if faces == 2 else 0
		on_three += 1 if faces == 3 else 0
		assert_int(faces).is_less_equal(3)
	# 12 cube edges with cells - 1 inner vertices each shared by two faces, 8 corners by three.
	assert_int(on_two).is_equal(12 * (Terrain.grid_cells(realm) - 1))
	assert_int(on_three).is_equal(8)


func test_chunks_wind_outward() -> void:
	var tris := Terrain.chunk_arrays(_realm(), SEED, 2, 10, 10)
	var inward := (tris[1] - tris[0]).cross(tris[2] - tris[0])
	assert_float(inward.dot(tris[0])).is_less(0.0)


func test_mostly_walkable() -> void:
	var field := Terrain.Field.new(_realm(), SEED)
	var walkable := 0
	var dirs := Terrain.sample_directions(2000)
	for d in dirs:
		if Terrain._normal(field, d).dot(d) >= cos(deg_to_rad(WALKABLE_DEGREES)):
			walkable += 1
	assert_float(float(walkable) / dirs.size()).is_greater(0.95)
