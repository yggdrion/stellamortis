class_name Generators
extends RefCounted
## The registry of generated model kinds (M36, docs/STYLE.md generator contract). A generator is a
## static function `(rng, palette, lod) -> Array` (mesh arrays, colors from `palette.color` and
## `MeshKit.paint` only) for lod `Budgets.FULL`, `HALF` or `FAR`. `arrays` runs on a worker (no
## scene tree, no resources); `build` commits them to meshes on the main thread.

static var _kinds: Dictionary = {}
static var _lock := Mutex.new()


## Adds a kind: `budget_kind` is its row in `Budgets.kinds`.
static func register(id: String, budget_kind: String, generator: Callable) -> void:
	_lock.lock()
	_kinds[id] = {"budget": budget_kind, "generator": generator}
	_lock.unlock()


## Every kind id, sorted. A built-in kind is registered in `_builtins`.
static func ids() -> Array[String]:
	_ensure()
	var out: Array[String] = []
	out.assign(_kinds.keys())
	out.sort()
	return out


static func budget_kind(id: String) -> String:
	_ensure()
	return _kinds[id]["budget"]


## The three levels (full, half, far) as mesh arrays; an empty one where the budget table says the
## level is not drawn. Same id, seed and palette give the same arrays. The lower levels are fitted
## to the full level's bounding box, so a tree does not shrink when it switches level.
static func arrays(id: String, variant_seed: int, palette: Palette) -> Array:
	_ensure()
	var kind: Dictionary = _kinds[id]
	var out: Array = []
	for lod in 3:
		if Budgets.data().limit(kind["budget"], lod) < 0:
			out.append(MeshKit.merge([]))
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = variant_seed
		var built: Array = (kind["generator"] as Callable).call(rng, palette, lod)
		out.append(built if lod == Budgets.FULL else _fit(built, out[Budgets.FULL]))
	return out


## Main thread: `arrays` committed to meshes.
static func build(id: String, variant_seed: int, palette: Palette) -> Array[ArrayMesh]:
	var meshes: Array[ArrayMesh] = []
	for part: Array in arrays(id, variant_seed, palette):
		meshes.append(MeshKit.commit([part]))
	return meshes


static func bounds(mesh_arrays: Array) -> AABB:
	var v: PackedVector3Array = mesh_arrays[Mesh.ARRAY_VERTEX]
	if v.is_empty():
		return AABB()
	var box := AABB(v[0], Vector3.ZERO)
	for p in v:
		box = box.expand(p)
	return box


## Moves and scales `built` onto the bounding box of `reference` (flat normals follow).
static func _fit(built: Array, reference: Array) -> Array:
	var from := bounds(built)
	var to := bounds(reference)
	var smallest := minf(from.size[from.size.min_axis_index()], to.size[to.size.min_axis_index()])
	if smallest <= MeshKit.EPS:
		return built
	var factor := to.size / from.size
	var v: PackedVector3Array = (built[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
	for i in v.size():
		v[i] = to.position + (v[i] - from.position) * factor
	var n := PackedVector3Array()
	n.resize(v.size())
	for i in range(0, v.size(), 3):
		var face := (v[i] - v[i + 2]).cross(v[i] - v[i + 1]).normalized()
		n[i] = face
		n[i + 1] = face
		n[i + 2] = face
	var out := built.duplicate()
	out[Mesh.ARRAY_VERTEX] = v
	out[Mesh.ARRAY_NORMAL] = n
	return out


static func _ensure() -> void:
	_lock.lock()
	var empty := _kinds.is_empty()
	_lock.unlock()
	if empty:
		_builtins()


static func _builtins() -> void:
	for id in ["rock", "boulder", "outcrop"]:
		register(id, id, RockKind.build.bind(id))
	register("standing_stone", "standing_stone", StandingStoneKind.build)
	register("mound", "standing_stone", MoundKind.build)
	for id in ["grass_tuft", "grass_tall"]:
		register(id, "grass_tuft", GrassKind.build.bind(id))
	register("fern", "fern_heather_bush", FernKind.build)
	register("heather", "fern_heather_bush", HeatherKind.build)
	register("bush", "fern_heather_bush", BushKind.build)
	for id in ["log", "stump"]:
		register(id, "log_stump", LogKind.build.bind(id))
	register("pebble", "pebble", PebbleKind.build)
	TreeKit.register_all("pine", PineKind.build)
	TreeKit.register_all("spruce", SpruceKind.build)
	TreeKit.register_all("birch", BirchKind.build)
	TreeKit.register_all("oak", OakKind.build)
	TreeKit.register_all("dead_tree", DeadTreeKind.build)
