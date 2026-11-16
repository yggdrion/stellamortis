extends GdUnitTestSuite
## The boss site of M22 (BossSite): a pure function of the realm and the seed, far from the
## arrival, flat inside its disc and walkable around it, a ring of stones and nothing else
## standing on it, no camp near it.

const SEEDS := [1234, 99, 7]
## SimPlayer.floor_max_angle in degrees.
const WALKABLE_DEGREES := 50.0


func _realm() -> RealmDef:
	return Layout.realms()[0]


func test_same_seed_same_site_and_other_seeds_differ() -> void:
	var a := BossSite.at(_realm(), 1234)
	var b := BossSite.at(_realm(), 1234)
	assert_object(a).is_same(b)
	# A site found again from scratch (the cache aside) lands on the same spot.
	var again := BossSite._find(_realm(), 1234)
	assert_vector(again.direction).is_equal(a.direction)
	assert_float(again.level).is_equal(a.level)
	assert_vector(BossSite.at(_realm(), 99).direction).is_not_equal(a.direction)


func test_far_from_the_arrival() -> void:
	for world_seed: int in SEEDS:
		var site := BossSite.at(_realm(), world_seed)
		var meters := _realm().arrival.normalized().angle_to(site.direction) * _realm().radius
		assert_float(meters).is_between(BossSite.MIN_ARC - 1.0, BossSite.MAX_ARC + 1.0)


func test_the_ground_is_flat_inside_the_disc_and_blends_out() -> void:
	for world_seed: int in SEEDS:
		var site := BossSite.at(_realm(), world_seed)
		var field := Terrain.Field.new(_realm(), world_seed)
		var east := site.direction.cross(Vector3.UP).normalized()
		for n in 16:
			var around := east.rotated(site.direction, TAU * n / 16.0)
			for meters: float in [0.0, 8.0, BossSite.RING_RADIUS, BossSite.FLAT - 1.0]:
				var step := meters / _realm().radius
				var toward := (site.direction * cos(step) + around * sin(step)).normalized()
				assert_float(field.height(toward)).is_equal(site.level)
		# Past the blend the ground is the raw noise again.
		var far := (site.direction * cos(0.08) + east * sin(0.08)).normalized()
		assert_float(field.height(far)).is_equal(field.raw_height(far))


func test_the_ground_around_the_site_is_walkable() -> void:
	var limit := cos(deg_to_rad(WALKABLE_DEGREES))
	for world_seed: int in SEEDS:
		var site := BossSite.at(_realm(), world_seed)
		var field := Terrain.Field.new(_realm(), world_seed)
		var east := site.direction.cross(Vector3.UP).normalized()
		for n in 24:
			var around := east.rotated(site.direction, TAU * n / 24.0)
			for meters in range(0, int(BossSite.FLAT + BossSite.BLEND) + 10, 3):
				var step := float(meters) / _realm().radius
				var toward := (site.direction * cos(step) + around * sin(step)).normalized()
				assert_float(Terrain._normal(field, toward).dot(toward)).is_greater(limit)


func test_the_ring_is_stones_and_nothing_else_stands_on_the_disc() -> void:
	var site := BossSite.at(_realm(), 1234)
	var field := Terrain.Field.new(_realm(), 1234)
	var chunks := {}
	for stone in site.stones():
		chunks[Terrain.chunk_at(_realm(), stone)] = true
	# The disc and its blend may span chunks; take every chunk a probe around it lands in.
	var east := site.direction.cross(Vector3.UP).normalized()
	for n in 12:
		var around := east.rotated(site.direction, TAU * n / 12.0)
		for meters: float in [0.0, 20.0, 40.0, 60.0]:
			var step := meters / _realm().radius
			chunks[Terrain.chunk_at(_realm(), site.direction * cos(step) + around * sin(step))] = true
	var stones := 0
	for chunk: Vector3i in chunks:
		for point in Scatter.points(_realm(), 1234, chunk):
			var meters := site.distance(point.up)
			if meters > BossSite.FLAT + BossSite.BLEND:
				continue
			assert_int(point.kind).is_equal(Scatter.Kind.STANDING_STONE)
			assert_float(meters).is_equal_approx(BossSite.RING_RADIUS, 0.2)
			assert_float(point.position.distance_to(field.surface(point.up))).is_less(0.001)
			stones += 1
	assert_int(stones).is_equal(BossSite.STONES)


func test_no_camp_or_roamer_near_the_site() -> void:
	for world_seed: int in [1234, 99]:
		var site := BossSite.at(_realm(), world_seed)
		var nearest := INF
		for point in Spawner.points(_realm(), world_seed):
			nearest = minf(nearest, site.distance(point.up))
		assert_float(nearest).is_greater(BossSite.FLAT + BossSite.BLEND)


func test_two_worlds_from_one_seed_have_the_same_site_ground() -> void:
	var a: World = auto_free(World.new(false))
	var b: World = auto_free(World.new(false))
	add_child(a)
	add_child(b)
	a.build(1234, "x")
	b.build(1234, "y")
	assert_vector(a.encounter.site.center()).is_equal(b.encounter.site.center())
	assert_vector(a.encounter.boss.home.origin).is_equal(b.encounter.boss.home.origin)
	Layout.set_world_seed(0)
