class_name TerrainView
extends Node3D
## The look of one generated realm (M20, M37), client only: flat-shaded palette ground for the
## chunks around the own player (the same grid points as the collision), a coarse shell of the
## whole realm so the horizon is never empty, the scatter (Scatter.points: trees, rocks, stones)
## and the ground cover (GroundCover.points: grass, ferns, heather, bushes), the last two as
## MultiMeshInstance3D. Triangles, scatter points and the instance buffers are built on
## WorkerThreadPool; meshes and multimeshes are made on the main thread, a few per frame. View
## distance, scatter and cover radius and density come from Graphics.
## Models: `VARIANTS` meshes of every kind (`COVER_VARIANTS` for cover) are generated once per
## world from hash(world seed, kind, variant) through Generators, each with three levels of
## detail. A chunk holds one MultiMeshInstance3D per (kind, variant, level); the engine shows the
## level for the distance (visibility ranges), so a chunk swaps whole and chunk jobs only build
## nodes.

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
## Variants per kind: trees and rocks, cover.
const VARIANTS := 4
const COVER_VARIANTS := 3
## A level covers its own range plus this much (m, half a chunk) at both ends, so a chunk (64 m
## across, switched by its center's distance) is never missing a level for its near or far half.
const LOD_MARGIN := 32.0
## The engine's own hysteresis at the ends of a range (m).
const RANGE_MARGIN := 8.0
## A kind with fewer instances in a chunk than this per variant uses fewer variants (fewer draws).
const MIN_PER_VARIANT := 6
## Variants committed (their meshes made) per frame while the world loads.
const KIT_COMMITS_PER_FRAME := 12
## The terrain's vertex color encodes the height as (height - HEIGHT_MIN) / HEIGHT_RANGE.
const HEIGHT_MIN := -20.0
const HEIGHT_RANGE := 160.0
## Roles of the ground shader (palette -> uniform).
const GROUND_ROLES := {
	"grass_color": &"grass",
	"heather_color": &"heather",
	"earth_color": &"earth",
	"stone_color": &"stone",
}
## Frames between two counts of the visible triangles (debug builds).
const COUNT_EVERY := 6

## Triangles of the visible instance levels in the last count (instances times the triangles of
## the kind's mesh at that level; debug builds only, 0 in a release build). The F3 overlay.
static var visible_triangles := 0
## Nodes in that count.
static var visible_nodes := 0

var realm: RealmDef
var world_seed := 0
var _index := 0
var _material: ShaderMaterial
## Vector4i(realm index, face, x, y) -> Entry.
var _chunks := {}
var _jobs := {}
var _queue: Array[Vector4i] = []
var _keep := {}
var _scatter_wanted := {}
var _cover_wanted := {}
var _last_at := Vector3.INF
## view radius, scatter radius, scatter density (always 1: Graphics), cover radius, cover density
var _settings := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0])
var _shadows := false
var _frame := 0
## Model kinds: index = Scatter.Kind and GroundCover.Kind, the generator ids.
var _solid_ids: Array[String] = []
var _cover_ids: Array[String] = []
## Generator id -> per variant [mesh full, half, far] (ArrayMesh, no surface where not drawn).
var _meshes := {}
## Generator id -> triangles per level (the most of its variants).
var _tris := {}
var _kit_group := -1
var _kit_work: Array = []
var _kit_arrays: Array = []
var _kit_next := 0
var _kit_ready := false


class Entry:
	extends RefCounted
	var mesh: MeshInstance3D
	var points: Array[Scatter.Point] = []
	var has_points := false
	var has_cover := false
	var scatter: Node3D
	var cover: Node3D
	## Per MultiMeshInstance3D: [world center, triangles in it, range begin, range end].
	var scatter_recs: Array = []
	var cover_recs: Array = []


## One build on a worker thread: triangles for a chunk or a shell face, scatter points with their
## instance buffers, or the cover of a chunk. Nothing here touches the scene tree.
class Job:
	extends RefCounted
	var key: Vector4i
	var realm: RealmDef
	var world_seed: int
	var shell := false
	var mesh := false
	var points := false
	var cover := false
	var density := 1.0
	## Cover: the scatter points of the chunk and its neighbours.
	var given: Array[Scatter.Point] = []
	var task := -1
	var arrays := []
	var found: Array[Scatter.Point] = []
	## Per (kind, variant) key: [PackedFloat32Array buffer, instance count, center]
	var groups := {}

	func run() -> void:
		if shell:
			arrays = TerrainView.shell_arrays(realm, world_seed, key.y)
		elif mesh:
			arrays = TerrainView.chunk_arrays(realm, world_seed, key.y, key.z, key.w)
		if points:
			found = Scatter.points(realm, world_seed, Vector3i(key.y, key.z, key.w))
			groups = TerrainView.pack(found, density, TerrainView.VARIANTS)
		if cover:
			var list := GroundCover.points(
				realm, world_seed, Vector3i(key.y, key.z, key.w), density, given
			)
			groups = TerrainView.pack(list, 1.0, TerrainView.COVER_VARIANTS)


func _init(for_realm: RealmDef, seed_value: int) -> void:
	realm = for_realm
	world_seed = seed_value
	name = "TerrainView"
	_index = Layout.realms().find(for_realm)


func _ready() -> void:
	# Headless bots draw nothing: no model kit, no chunk jobs (they cost the bots seconds of CPU).
	if DisplayServer.get_name() == "headless":
		set_process(false)
		return
	_material = _ground_material()
	# The first call loads the shader (up to 12 ms): here, not in the first commit.
	MeshKit.material()
	for name_of: String in Scatter.Kind.keys():
		_solid_ids.append(name_of.to_lower())
	for name_of: String in GroundCover.Kind.keys():
		_cover_ids.append(name_of.to_lower())
	_start_kit()
	for face in 6:
		var job := _job(Vector4i(-1, face, 0, 0))
		job.shell = true
		_start(job)


func _exit_tree() -> void:
	for job: Job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()
	if _kit_group >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_kit_group)
		_kit_group = -1


func _process(_delta: float) -> void:
	_commit_kit()
	_pump()
	var me := _own_player()
	if me == null or Layout.realm_at(me.global_position) != realm:
		if not _chunks.is_empty():
			_clear()
		visible_triangles = 0
		visible_nodes = 0
		return
	var at := me.global_position
	var settings := PackedFloat32Array(
		[
			Graphics.view_radius(),
			Graphics.scatter_radius(),
			1.0,
			Graphics.cover_radius(),
			Graphics.cover_density()
		]
	)
	if at.distance_to(_last_at) >= REFRESH_DISTANCE or settings != _settings:
		_refresh(at, settings)
	elif _queue.is_empty() and _jobs.size() < MAX_JOBS and _frame % 15 == 0:
		_queue_cover()
	_frame += 1
	if OS.is_debug_build() and _frame % COUNT_EVERY == 0:
		_count_triangles()


## The triangles of a chunk as mesh arrays: its grid as unshared faces with their flat normals
## and the numbers the ground shader colors them by (see terrain.gdshader).
static func chunk_arrays(realm_def: RealmDef, seed_value: int, face: int, x: int, y: int) -> Array:
	var points := Terrain.chunk_points(realm_def, seed_value, face, x, y, 1)
	return _grid_arrays(points, Terrain.CHUNK_CELLS, 0.0, realm_def, seed_value)


## One face of the coarse shell, a little under the ground.
static func shell_arrays(realm_def: RealmDef, seed_value: int, face: int) -> Array:
	var points := Terrain.grid_points(
		realm_def, seed_value, face, SHELL_CELLS, Vector2i.ZERO, SHELL_CELLS, 1
	)
	return _grid_arrays(points, SHELL_CELLS, SHELL_SINK, realm_def, seed_value)


## Mesh arrays of a span x span grid whose points come with one ring of margin: two triangles a
## cell, each with its own three vertices, its flat normal (outward) and, in every vertex's color,
## the face's numbers: r the forest noise (0 to 1 for -1 to 1), g the height, b the cosine of the
## slope, a a roll in [0, 1) from the face's place. Same winding as the collision.
static func _grid_arrays(
	points: PackedVector3Array, span: int, sink: float, realm_def: RealmDef, seed_value: int
) -> Array:
	var side := span + 3
	var forest := Scatter._noise(realm_def, seed_value, 11, Scatter.FOREST_WAVELENGTH)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := span * span * 6
	vertices.resize(count)
	normals.resize(count)
	colors.resize(count)
	var n := 0
	for b in span:
		for a in span:
			var c := (b + 1) * side + a + 1
			var p00 := points[c]
			var p10 := points[c + 1]
			var p01 := points[c + side]
			var p11 := points[c + side + 1]
			var tri_a := [p00, p01, p10]
			var tri_b := [p10, p01, p11]
			for tri: Array in [tri_a, tri_b]:
				var u: Vector3 = tri[0]
				var v: Vector3 = tri[1]
				var w: Vector3 = tri[2]
				var normal := (v - u).cross(w - u).normalized()
				var middle := (u + v + w) / 3.0
				var up := middle.normalized()
				var roll := float(hash(Vector3i(middle * 8.0)) & 1023) / 1024.0
				if normal.dot(up) < 0.0:
					normal = -normal
				var at := up * realm_def.radius
				var color := Color(
					forest.get_noise_3d(at.x, at.y, at.z) * 0.5 + 0.5,
					clampf(
						(middle.length() - realm_def.radius - HEIGHT_MIN) / HEIGHT_RANGE, 0.0, 1.0
					),
					clampf(normal.dot(up), 0.0, 1.0),
					roll
				)
				for q: Vector3 in tri:
					vertices[n] = q - q.normalized() * sink
					normals[n] = normal
					colors[n] = color
					n += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	return arrays


## The instance buffers of `things` (Scatter.Point or GroundCover.Point: kind, position, up, yaw,
## size, rank): those with a rank under `density`, grouped by kind and variant. The variant is
## picked from the rank; a kind with few instances uses fewer variants. Key = kind * 8 +
## variant, value [buffer, count, center]; the buffer is a Transform3D per instance (12 floats:
## three rows of the basis, each followed by the origin's component). The model stands on the
## ground along the point's up, turned by its yaw, scaled like its ScatterShape (0.8 + 0.5 size).
static func pack(things: Array, density: float, max_variants: int) -> Dictionary:
	var counts := {}
	for thing in things:
		if thing.rank < density:
			counts[thing.kind] = int(counts.get(thing.kind, 0)) + 1
	var lists := {}
	for thing in things:
		if thing.rank >= density:
			continue
		var variants := clampi(int(counts[thing.kind]) / MIN_PER_VARIANT, 1, max_variants)
		var variant := mini(int(thing.rank / density * variants), variants - 1)
		var key: int = int(thing.kind) * 8 + variant
		if not lists.has(key):
			lists[key] = []
		(lists[key] as Array).append(thing)
	var groups := {}
	for key: int in lists:
		var list: Array = lists[key]
		var buffer := PackedFloat32Array()
		buffer.resize(list.size() * 12)
		var low := Vector3.INF
		var high := -Vector3.INF
		for i in list.size():
			var thing = list[i]
			var up: Vector3 = thing.up
			var forward := SimPlayer._tangent(Vector3.FORWARD, up)
			var basis := SimPlayer.frame(up, forward).rotated(up, thing.yaw)
			basis = basis.scaled_local(Vector3.ONE * (0.8 + 0.5 * thing.size))
			var at: Vector3 = thing.position
			low = low.min(at)
			high = high.max(at)
			var o := i * 12
			buffer[o] = basis.x.x
			buffer[o + 1] = basis.y.x
			buffer[o + 2] = basis.z.x
			buffer[o + 3] = at.x
			buffer[o + 4] = basis.x.y
			buffer[o + 5] = basis.y.y
			buffer[o + 6] = basis.z.y
			buffer[o + 7] = at.y
			buffer[o + 8] = basis.x.z
			buffer[o + 9] = basis.y.z
			buffer[o + 10] = basis.z.z
			buffer[o + 11] = at.z
		groups[key] = [buffer, list.size(), (low + high) * 0.5]
	return groups


# --- the models ---


## Every kind's variants are generated on workers (one task per kind and variant), then made
## into meshes a few per frame in `_commit_kit`; chunk jobs wait for `_kit_ready`.
func _start_kit() -> void:
	# Warm what the workers read, so none of them loads it.
	Palette.of(realm.id)
	Budgets.data()
	Generators.ids()
	for id in _solid_ids:
		for variant in VARIANTS:
			_kit_work.append([id, variant])
	for id in _cover_ids:
		for variant in COVER_VARIANTS:
			_kit_work.append([id, variant])
	_kit_arrays.resize(_kit_work.size())
	_kit_group = WorkerThreadPool.add_group_task(_build_variant, _kit_work.size())


func _build_variant(i: int) -> void:
	var work: Array = _kit_work[i]
	var seed_of := hash(Vector3i(world_seed, (work[0] as String).hash() & 0x7fffffff, work[1]))
	_kit_arrays[i] = Generators.arrays(work[0], seed_of, Palette.of(realm.id))


func _commit_kit() -> void:
	if _kit_ready:
		return
	if _kit_group >= 0:
		if not WorkerThreadPool.is_group_task_completed(_kit_group):
			return
		WorkerThreadPool.wait_for_group_task_completion(_kit_group)
		_kit_group = -1
	var last := mini(_kit_next + KIT_COMMITS_PER_FRAME, _kit_work.size())
	while _kit_next < last:
		var id: String = _kit_work[_kit_next][0]
		var levels: Array[ArrayMesh] = []
		var tris: PackedInt32Array = _tris.get(id, PackedInt32Array([0, 0, 0]))
		for lod in 3:
			var part: Array = _kit_arrays[_kit_next][lod]
			levels.append(MeshKit.commit([part]))
			tris[lod] = maxi(tris[lod], MeshKit.triangles(part))
		_tris[id] = tris
		if not _meshes.has(id):
			_meshes[id] = []
		(_meshes[id] as Array).append(levels)
		_kit_arrays[_kit_next] = null
		_kit_next += 1
	_kit_ready = _kit_next >= _kit_work.size()


func _own_player() -> SimPlayer:
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if player.peer_id == multiplayer.get_unique_id():
			return player
	return null


# --- chunks ---


func _job(key: Vector4i) -> Job:
	var job := Job.new()
	job.key = key
	job.realm = realm
	job.world_seed = world_seed
	return job


func _start(job: Job) -> void:
	job.task = WorkerThreadPool.add_task(job.run)
	_jobs[job.key] = job


## Recomputes which chunks are shown and which have scatter and cover, frees the ones out of
## range and queues the missing builds, nearest first. New settings rebuild scatter and cover.
func _refresh(at: Vector3, settings: PackedFloat32Array) -> void:
	_last_at = at
	var changed := settings != _settings
	_settings = settings
	_shadows = Graphics.preset >= Graphics.Preset.HIGH
	var want := TerrainChunks.around(at, settings[0])
	_keep = TerrainChunks.around(at, settings[0] + HYSTERESIS)
	_scatter_wanted = TerrainChunks.around(at, settings[1])
	_cover_wanted = TerrainChunks.around(at, settings[3])
	var scatter_keep := TerrainChunks.around(at, settings[1] + HYSTERESIS)
	var cover_keep := TerrainChunks.around(at, settings[3] + HYSTERESIS)
	for key: Vector4i in _chunks.keys():
		if not _keep.has(key):
			_free(key)
			continue
		var entry: Entry = _chunks[key]
		if changed or not scatter_keep.has(key):
			_drop_scatter(entry)
		if changed or not cover_keep.has(key):
			_drop_cover(entry)
	var missing := {}
	for key: Vector4i in want:
		if not _chunks.has(key):
			missing[key] = want[key]
	for key: Vector4i in _scatter_wanted:
		var entry: Entry = _chunks.get(key)
		if entry != null and not entry.has_points:
			missing[key] = _scatter_wanted[key]
	for key: Vector4i in _cover_wanted:
		var entry: Entry = _chunks.get(key)
		if entry != null and entry.has_points and not entry.has_cover:
			missing[key] = _cover_wanted[key]
	_sorted_queue(missing)


func _sorted_queue(missing: Dictionary) -> void:
	var keys: Array = missing.keys()
	keys.sort_custom(func(p: Vector4i, q: Vector4i) -> bool: return missing[p] < missing[q])
	_queue.assign(keys)


## Cover waits for the scatter points of its neighbours: this puts the chunks whose wait is over
## in the queue (the refresh does not run while the player stands still).
func _queue_cover() -> void:
	var missing := {}
	for key: Vector4i in _cover_wanted:
		var entry: Entry = _chunks.get(key)
		if entry != null and entry.has_points and not entry.has_cover and _cover_ready(key):
			missing[key] = _cover_wanted[key]
	_sorted_queue(missing)


## Every neighbour that is going to have scatter has it.
func _cover_ready(key: Vector4i) -> bool:
	for other in GroundCover.neighbours(realm, Vector3i(key.y, key.z, key.w)):
		var other_key := Vector4i(key.x, other.x, other.y, other.z)
		if not _scatter_wanted.has(other_key):
			continue
		var entry: Entry = _chunks.get(other_key)
		if entry == null or not entry.has_points:
			return false
	return true


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
	while _kit_ready and _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var key: Vector4i = _queue.pop_front()
		if _jobs.has(key) or not _keep.has(key):
			continue
		var entry: Entry = _chunks.get(key)
		var job := _job(key)
		job.mesh = entry == null
		job.points = _scatter_wanted.has(key) and (entry == null or not entry.has_points)
		job.density = _settings[2]
		if (
			not job.points
			and entry != null
			and entry.has_points
			and not entry.has_cover
			and _cover_wanted.has(key)
			and _cover_ready(key)
		):
			job.cover = true
			job.density = _settings[4]
			job.given = entry.points.duplicate()
			for other in GroundCover.neighbours(realm, Vector3i(key.y, key.z, key.w)):
				var near: Entry = _chunks.get(Vector4i(key.x, other.x, other.y, other.z))
				if near != null and near.has_points:
					job.given.append_array(near.points)
		if job.mesh or job.points or job.cover:
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
	if entry == null:
		return
	if job.points and _scatter_wanted.has(job.key) and job.density == _settings[2]:
		entry.points = job.found
		entry.has_points = true
		entry.scatter = _make_nodes(job.groups, false, entry.scatter_recs)
	if job.cover and _cover_wanted.has(job.key) and job.density == _settings[4]:
		entry.has_cover = true
		entry.cover = _make_nodes(job.groups, true, entry.cover_recs)


func _array_mesh(arrays: Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	return mesh


func _drop_scatter(entry: Entry) -> void:
	if entry.scatter != null:
		entry.scatter.queue_free()
		entry.scatter = null
	entry.scatter_recs.clear()
	entry.points = []
	entry.has_points = false


func _drop_cover(entry: Entry) -> void:
	if entry.cover != null:
		entry.cover.queue_free()
		entry.cover = null
	entry.cover_recs.clear()
	entry.has_cover = false


func _free(key: Vector4i) -> void:
	var entry: Entry = _chunks[key]
	entry.mesh.queue_free()
	_drop_scatter(entry)
	_drop_cover(entry)
	_chunks.erase(key)


func _clear() -> void:
	for key: Vector4i in _chunks.keys():
		_free(key)
	_queue.clear()
	_keep = {}
	_scatter_wanted = {}
	_cover_wanted = {}
	_last_at = Vector3.INF


## The nodes of a chunk's packed groups (`pack`): per kind and variant one MultiMeshInstance3D
## for each level of detail the kind has, shown by distance. `recs` gets one entry per node for
## the triangle count.
func _make_nodes(groups: Dictionary, cover: bool, recs: Array) -> Node3D:
	if groups.is_empty():
		return null
	var holder := Node3D.new()
	holder.position = realm.center
	var ids := _cover_ids if cover else _solid_ids
	var budgets := Budgets.data()
	var reach := (_settings[3] if cover else _settings[1]) + HYSTERESIS
	# Level ranges (begin, end): full, half, far.
	var ranges := [
		Vector2(0.0, budgets.full_distance + LOD_MARGIN),
		Vector2(budgets.full_distance - LOD_MARGIN, budgets.half_distance + LOD_MARGIN),
		Vector2(budgets.half_distance - LOD_MARGIN, reach),
	]
	var shadows := _shadows and not cover
	# Cover has no far level, nor has a scatter radius that ends in the half level (Low).
	var far := not cover and _settings[1] > budgets.half_distance
	for key: int in groups:
		var id := ids[key >> 3]
		var data: Array = groups[key]
		for lod in 3:
			var mesh: ArrayMesh = (_meshes[id][key & 7] as Array)[lod]
			var span: Vector2 = ranges[lod]
			span.y = minf(span.y, reach)
			if mesh.get_surface_count() == 0 or (lod == 2 and not far):
				continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = data[1]
			multi.buffer = data[0]
			var node := MultiMeshInstance3D.new()
			node.multimesh = multi
			node.visibility_range_begin = span.x
			node.visibility_range_end = span.y
			node.visibility_range_begin_margin = RANGE_MARGIN
			node.visibility_range_end_margin = RANGE_MARGIN
			node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			node.cast_shadow = (
				GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				if shadows
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			)
			holder.add_child(node)
			recs.append(
				[
					realm.center + (data[2] as Vector3),
					(_tris[id] as PackedInt32Array)[lod] * int(data[1]),
					span.x,
					span.y
				]
			)
	add_child(holder)
	return holder


## Debug builds: the triangles of every node whose level is in range of the camera (and, past
## 60 m, in its frustum), as `visible_triangles` for the F3 overlay.
func _count_triangles() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var eye := camera.global_position
	var total := 0
	var nodes := 0
	for entry: Entry in _chunks.values():
		for recs: Array in [entry.scatter_recs, entry.cover_recs]:
			for rec: Array in recs:
				var center: Vector3 = rec[0]
				var distance := eye.distance_to(center)
				if distance < rec[2] or distance >= rec[3]:
					continue
				if distance > 60.0 and not camera.is_position_in_frustum(center):
					continue
				total += rec[1]
				nodes += 1
	visible_triangles = total
	visible_nodes = nodes


func _ground_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	var palette := Palette.of(realm.id)
	for uniform: String in GROUND_ROLES:
		material.set_shader_parameter(uniform, palette.color(GROUND_ROLES[uniform]))
	material.set_shader_parameter("height_min", HEIGHT_MIN)
	material.set_shader_parameter("height_range", HEIGHT_RANGE)
	return material
