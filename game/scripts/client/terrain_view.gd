class_name TerrainView
extends Node3D
## The look of one generated realm (M20), client only: meshes of the chunks around the own player
## (the same grid points as the collision, with normals), a coarse shell of the whole realm so the
## horizon is never empty, and the scatter (Scatter.points) drawn with MultiMeshInstance3D.
## Triangles and scatter points are built on WorkerThreadPool; meshes and multimeshes are made on
## the main thread, a few per frame. View distance and scatter density come from Graphics.

const SHELL_CELLS := 96
## The shell hangs this far under the ground so it never shows through the near chunks (it is
## linear between its vertices, the ground is not).
const SHELL_SINK := 4.0
## Chunks are freed once they are this much farther than the view distance.
const HYSTERESIS := 48.0
const MAX_JOBS := 4
const MESHES_PER_FRAME := 2
## The chunk sets are recomputed after the player moved this far.
const REFRESH_DISTANCE := 16.0
const NATURE := "res://assets/kenney/nature/"
## Per Scatter.Kind: model file ("" for the mound, a squashed sphere), meters per unit of the
## model (scale = base * (0.8 + 0.5 * the point's size roll)), the main color (foliage, rock),
## meters sunk into the ground, a stretch of the axes and the accent color (bark, moss). The
## models' own colors are teal and orange; these are dark and muted: color is reserved for
## meaning.
const LOOKS := {
	Scatter.Kind.PINE_TALL:
	[
		"tree_pineTallA",
		3.0,
		Color(0.2, 0.33, 0.24),
		0.3,
		Vector3(0.75, 1.9, 0.75),
		Color(0.3, 0.22, 0.17)
	],
	Scatter.Kind.PINE_FULL:
	[
		"tree_pineDefaultA",
		2.8,
		Color(0.18, 0.3, 0.22),
		0.3,
		Vector3(0.75, 1.8, 0.75),
		Color(0.3, 0.22, 0.17)
	],
	Scatter.Kind.BIRCH:
	[
		"tree_thin_dark",
		2.6,
		Color(0.45, 0.42, 0.2),
		0.3,
		Vector3(0.7, 1.6, 0.7),
		Color(0.72, 0.72, 0.68)
	],
	Scatter.Kind.BOULDER_A:
	[
		"rock_largeA",
		3.4,
		Color(0.4, 0.4, 0.42),
		0.5,
		Vector3(1.0, 2.0, 1.0),
		Color(0.22, 0.28, 0.18)
	],
	Scatter.Kind.BOULDER_B:
	[
		"rock_largeC",
		3.2,
		Color(0.38, 0.38, 0.4),
		0.5,
		Vector3(1.0, 2.0, 1.0),
		Color(0.22, 0.28, 0.18)
	],
	Scatter.Kind.STANDING_STONE:
	["stone_tallA", 3.2, Color(0.42, 0.44, 0.46), 0.8, Vector3(0.8, 1.5, 0.8), Color.WHITE],
	Scatter.Kind.MOUND: ["", 4.5, Color.WHITE, 0.0, Vector3(1.0, 0.4, 1.0), Color.WHITE],
}
## Model materials that take the accent color.
const ACCENTS := ["woodBarkDark", "grass"]

var realm: RealmDef
var world_seed := 0
var _index := 0
var _material: ShaderMaterial
var _meshes := {}
## Vector4i(realm index, face, x, y) -> Entry.
var _chunks := {}
var _jobs := {}
var _queue: Array[Vector4i] = []
var _keep := {}
var _scatter_wanted := {}
var _last_at := Vector3.INF
var _settings := Vector3.ZERO
var _density := -1.0


class Entry:
	extends RefCounted
	var mesh: MeshInstance3D
	var points: Array[Scatter.Point] = []
	var has_points := false
	var scatter: Node3D


## One build on a worker thread: triangles for a chunk or a shell face, and/or scatter points.
## Nothing here touches the scene tree.
class Job:
	extends RefCounted
	var key: Vector4i
	var realm: RealmDef
	var world_seed: int
	var shell := false
	var mesh := false
	var points := false
	var task := -1
	var arrays := []
	var found: Array[Scatter.Point] = []

	func run() -> void:
		if shell:
			arrays = TerrainView.shell_arrays(realm, world_seed, key.y)
		elif mesh:
			arrays = TerrainView.chunk_arrays(realm, world_seed, key.y, key.z, key.w)
		if points:
			found = Scatter.points(realm, world_seed, Vector3i(key.y, key.z, key.w))


func _init(for_realm: RealmDef, seed_value: int) -> void:
	realm = for_realm
	world_seed = seed_value
	name = "TerrainView"
	_index = Layout.realms().find(for_realm)


func _ready() -> void:
	_material = _ground_material()
	for kind: int in LOOKS:
		_meshes[kind] = _kind_mesh(kind)
	for face in 6:
		var job := _job(Vector4i(-1, face, 0, 0))
		job.shell = true
		_start(job)


func _exit_tree() -> void:
	for job: Job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()


func _process(_delta: float) -> void:
	_pump()
	var me := _own_player()
	if me == null or Layout.realm_at(me.global_position) != realm:
		if not _chunks.is_empty():
			_clear()
		return
	var at := me.global_position
	var settings := Vector3(
		Graphics.view_radius(), Graphics.scatter_radius(), Graphics.scatter_density()
	)
	if at.distance_to(_last_at) >= REFRESH_DISTANCE or settings != _settings:
		_refresh(at, settings)
	if settings.z != _density:
		_density = settings.z
		for entry: Entry in _chunks.values():
			_build_scatter(entry)


## The triangles of a chunk as mesh arrays: its grid, smooth normals from the ring of
## neighbours' points (no seams), indexed with the collision's winding.
static func chunk_arrays(realm_def: RealmDef, seed_value: int, face: int, x: int, y: int) -> Array:
	var points := Terrain.chunk_points(realm_def, seed_value, face, x, y, 1)
	return _grid_arrays(points, Terrain.CHUNK_CELLS, 0.0)


## One face of the coarse shell, a little under the ground.
static func shell_arrays(realm_def: RealmDef, seed_value: int, face: int) -> Array:
	var points := Terrain.grid_points(
		realm_def, seed_value, face, SHELL_CELLS, Vector2i.ZERO, SHELL_CELLS, 1
	)
	return _grid_arrays(points, SHELL_CELLS, SHELL_SINK)


## Mesh arrays of a span x span grid whose points come with one ring of margin.
static func _grid_arrays(points: PackedVector3Array, span: int, sink: float) -> Array:
	var side := span + 3
	var out := span + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(out * out)
	normals.resize(out * out)
	for b in out:
		for a in out:
			var c := (b + 1) * side + a + 1
			var p := points[c]
			var normal := (points[c + 1] - points[c - 1]).cross(points[c + side] - points[c - side])
			normal = normal.normalized()
			if normal.dot(p) < 0.0:
				normal = -normal
			vertices[b * out + a] = p - p.normalized() * sink
			normals[b * out + a] = normal
	var indices := PackedInt32Array()
	indices.resize(span * span * 6)
	var n := 0
	for b in span:
		for a in span:
			var p00 := b * out + a
			var p10 := p00 + 1
			var p01 := p00 + out
			var p11 := p01 + 1
			indices[n] = p00
			indices[n + 1] = p01
			indices[n + 2] = p10
			indices[n + 3] = p10
			indices[n + 4] = p01
			indices[n + 5] = p11
			n += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _job(key: Vector4i) -> Job:
	var job := Job.new()
	job.key = key
	job.realm = realm
	job.world_seed = world_seed
	return job


func _start(job: Job) -> void:
	job.task = WorkerThreadPool.add_task(job.run)
	_jobs[job.key] = job


func _own_player() -> SimPlayer:
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if player.peer_id == multiplayer.get_unique_id():
			return player
	return null


## Recomputes which chunks are shown and which have scatter, frees the ones out of range and
## queues the missing builds, nearest first.
func _refresh(at: Vector3, settings: Vector3) -> void:
	_last_at = at
	_settings = settings
	var want := TerrainChunks.around(at, settings.x)
	_keep = TerrainChunks.around(at, settings.x + HYSTERESIS)
	_scatter_wanted = TerrainChunks.around(at, settings.y)
	var scatter_keep := TerrainChunks.around(at, settings.y + HYSTERESIS)
	for key: Vector4i in _chunks.keys():
		if not _keep.has(key):
			_free(key)
		elif not scatter_keep.has(key):
			var entry: Entry = _chunks[key]
			entry.has_points = false
			entry.points = []
			_build_scatter(entry)
	var missing := {}
	for key: Vector4i in want:
		if not _chunks.has(key):
			missing[key] = want[key]
	for key: Vector4i in _scatter_wanted:
		var entry: Entry = _chunks.get(key)
		if entry != null and not entry.has_points:
			missing[key] = _scatter_wanted[key]
	var keys: Array = missing.keys()
	keys.sort_custom(func(p: Vector4i, q: Vector4i) -> bool: return missing[p] < missing[q])
	_queue.assign(keys)


func _pump() -> void:
	var added := 0
	for key: Vector4i in _jobs.keys():
		if added >= MESHES_PER_FRAME:
			break
		var job: Job = _jobs[key]
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(key)
		_finish(job)
		added += 1
	while _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var key: Vector4i = _queue.pop_front()
		if _jobs.has(key) or not _keep.has(key):
			continue
		var entry: Entry = _chunks.get(key)
		var job := _job(key)
		job.mesh = entry == null
		job.points = _scatter_wanted.has(key) and (entry == null or not entry.has_points)
		if job.mesh or job.points:
			_start(job)


func _finish(job: Job) -> void:
	if job.shell:
		var shell := MeshInstance3D.new()
		shell.name = "Shell%d" % job.key.y
		shell.mesh = _array_mesh(job.arrays)
		shell.position = realm.center
		add_child(shell)
		return
	if not _keep.has(job.key):
		return
	var entry: Entry = _chunks.get(job.key)
	if entry == null and job.mesh:
		entry = Entry.new()
		entry.mesh = MeshInstance3D.new()
		entry.mesh.name = "Chunk_%d_%d_%d" % [job.key.y, job.key.z, job.key.w]
		entry.mesh.mesh = _array_mesh(job.arrays)
		entry.mesh.position = realm.center
		add_child(entry.mesh)
		_chunks[job.key] = entry
	if entry != null and job.points and _scatter_wanted.has(job.key):
		entry.points = job.found
		entry.has_points = true
		_build_scatter(entry)


func _array_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


func _free(key: Vector4i) -> void:
	var entry: Entry = _chunks[key]
	entry.mesh.queue_free()
	if entry.scatter != null:
		entry.scatter.queue_free()
	_chunks.erase(key)


func _clear() -> void:
	for key: Vector4i in _chunks.keys():
		_free(key)
	_queue.clear()
	_keep = {}
	_scatter_wanted = {}
	_last_at = Vector3.INF


## (Re)builds a chunk's multimeshes from its points: one instance node per kind, only the
## points under the density.
func _build_scatter(entry: Entry) -> void:
	if entry.scatter != null:
		entry.scatter.queue_free()
		entry.scatter = null
	if not entry.has_points:
		return
	var by_kind := {}
	for point in entry.points:
		if point.rank >= _density:
			continue
		var list: Array = by_kind.get(point.kind, [])
		list.append(_transform(point))
		by_kind[point.kind] = list
	if by_kind.is_empty():
		return
	entry.scatter = Node3D.new()
	entry.scatter.position = realm.center
	var shadows := Graphics.preset >= Graphics.Preset.HIGH
	for kind: int in by_kind:
		var list: Array = by_kind[kind]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = _meshes[kind]
		multi.instance_count = list.size()
		for i in list.size():
			multi.set_instance_transform(i, list[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.visibility_range_end = _settings.y + HYSTERESIS
		node.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			if shadows
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		entry.scatter.add_child(node)
	add_child(entry.scatter)


## Standing on the ground along its local up, turned by its yaw, sunk a little.
func _transform(point: Scatter.Point) -> Transform3D:
	var look: Array = LOOKS[point.kind]
	var forward := SimPlayer._tangent(Vector3.FORWARD, point.up)
	var basis := SimPlayer.frame(point.up, forward).rotated(point.up, point.yaw)
	var scale_by: float = look[1] * (0.8 + 0.5 * point.size)
	basis = basis.scaled_local((look[4] as Vector3) * scale_by)
	return Transform3D(basis, point.position - point.up * look[3])


## The mesh of a kind: a model's first mesh with its colors tinted (dark, muted), or the mound.
func _kind_mesh(kind: int) -> Mesh:
	var look: Array = LOOKS[kind]
	if look[0] == "":
		var mound := SphereMesh.new()
		mound.radius = 1.0
		mound.height = 2.0
		mound.radial_segments = 24
		mound.rings = 12
		mound.material = _material
		return mound
	var root := (load(NATURE + look[0] + ".glb") as PackedScene).instantiate()
	var source := _first_mesh(root)
	var mesh := source.mesh.duplicate() as Mesh
	root.free()
	for surface in mesh.get_surface_count():
		var source_material := mesh.surface_get_material(surface) as StandardMaterial3D
		var material := (
			source_material.duplicate() as StandardMaterial3D
			if source_material != null
			else StandardMaterial3D.new()
		)
		material.albedo_color = look[5] if material.resource_name in ACCENTS else look[2]
		material.roughness = 1.0
		mesh.surface_set_material(surface, material)
	return mesh


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found != null:
			return found
	return null


func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var grass := Arena.AMBIENTCG + Arena.GROUND + "/"
	var rock := Arena.AMBIENTCG + Arena.ROCK + "/"
	material.set_shader_parameter("grass_albedo", load(grass + "Color.jpg"))
	material.set_shader_parameter("grass_normal", load(grass + "NormalGL.jpg"))
	material.set_shader_parameter("rock_albedo", load(rock + "Color.jpg"))
	material.set_shader_parameter("rock_normal", load(rock + "NormalGL.jpg"))
	material.set_shader_parameter("realm_center", realm.center)
	material.set_shader_parameter("realm_radius", realm.radius)
	return material
