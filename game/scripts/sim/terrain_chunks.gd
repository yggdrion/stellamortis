class_name TerrainChunks
extends Node3D
## Streams the collision of the generated realms (M20): one StaticBody3D with a
## ConcavePolygonShape3D per chunk (Terrain.chunk_arrays) on the world layer, kept alive around
## the anchors (server: every player, M21 adds enemies; client: the own player) and freed
## beyond them. Triangles are built on WorkerThreadPool, shapes and bodies on the main
## thread with a per-frame budget. Chunks are static and a pure function of the world seed, so
## streaming never touches rollback state: peers only ever differ in which chunks far from every
## anchor exist.
##
## Radii: a body would have to outrun the build queue to meet a missing chunk. A build plus its
## wait in the queue is a few hundred ms (debug: ~15 ms a chunk on a worker, jobs start nearest
## first), the fastest things are launches (17 m/s) and falls from the gravity reach (~90 m/s
## after 300 m): LOAD_RADIUS 150 m, minus the refresh slack and the sampling gap, still leaves
## 100 m, over a second at 90 m/s. Gate arrivals and spawns inside a realm skip the race: they
## build the chunks under the arrival synchronously (ensure_around).

signal chunk_added(key: Vector4i)
signal chunk_removed(key: Vector4i)

const GROUP := &"terrain_chunks"
## Chunks within this distance of an anchor are queued...
const LOAD_RADIUS := 150.0
## ...and freed once their center is farther than this plus CHUNK_BOUND (hysteresis).
const UNLOAD_RADIUS := 200.0
## A chunk's farthest point from its center: half the diagonal of 32 cells of up to 2 m, plus
## the ground's relief.
const CHUNK_BOUND := 50.0
## Tangent-plane grid used to find the chunks around a point (chunks are at least ~28 m wide).
const SAMPLE_STEP := 24.0
## An anchor's chunk set is recomputed after it moved this far.
const REFRESH_DISTANCE := 16.0
## Bodies added to the tree per physics frame (the first use of a shape builds its Jolt tree).
const BODIES_PER_FRAME := 2
const MAX_JOBS := 6
## Chunks built synchronously around gate arrivals and new anchors.
const ARRIVAL_RADIUS := 40.0

## Replaceable (tests): returns the Node3Ds to keep ground under.
var anchors := _default_anchors
var world_seed := 0
## Client: only the own player anchors.
var own_only := false
## Vector4i(realm index, face, x, y) -> StaticBody3D.
var bodies := {}
var _jobs := {}
var _queue: Array[Vector4i] = []
var _pinned := {}
## Anchor instance id -> {pos, near: Dictionary key -> squared distance}.
var _tracked := {}


## One chunk build, run on a worker thread: only the triangles. Nothing here touches the scene
## tree or the physics server (not thread safe in this project); the shape is made on the main
## thread in _add_body.
class Job:
	extends RefCounted
	var key: Vector4i
	var realm: RealmDef
	var world_seed: int
	var task := -1
	var faces: PackedVector3Array

	func run() -> void:
		faces = Terrain.chunk_arrays(realm, world_seed, key.y, key.z, key.w)


func _init(seed_value := 0, for_client := false) -> void:
	name = "Chunks"
	world_seed = seed_value
	own_only = for_client
	add_to_group(GROUP)


func _exit_tree() -> void:
	for job: Job in _jobs.values():
		WorkerThreadPool.wait_for_task_completion(job.task)
	_jobs.clear()


func _physics_process(_delta: float) -> void:
	var nodes: Array = anchors.call()
	_track(nodes)
	_pump()
	_check_under(nodes)


## Builds, now, the chunks within radius of a point and keeps them for good (a realm's arrival
## point on every peer).
func pin_around(point: Vector3, radius := ARRIVAL_RADIUS) -> void:
	for key: Vector4i in around(point, radius):
		_pinned[key] = true
	ensure_around(point, radius)


## Builds, now, the chunks within radius of a point that are not there yet. A gate calls it
## before it moves a player; it is a no-op when the chunks stand.
func ensure_around(point: Vector3, radius := ARRIVAL_RADIUS) -> void:
	for key: Vector4i in around(point, radius):
		if bodies.has(key):
			continue
		var job: Job = _jobs.get(key)
		if job == null:
			job = _job(key)
			job.run()
		else:
			WorkerThreadPool.wait_for_task_completion(job.task)
			_jobs.erase(key)
		_add_body(key, job.faces)


## The key of the chunk under a world point, null outside every realm.
func key_at(point: Vector3) -> Variant:
	var realm := Layout.realm_at(point)
	if realm == null:
		return null
	return _key(realm, (point - realm.center).normalized())


static func _key(realm: RealmDef, direction: Vector3) -> Vector4i:
	var chunk := Terrain.chunk_at(realm, direction)
	return Vector4i(Layout.realms().find(realm), chunk.x, chunk.y, chunk.z)


func _job(key: Vector4i) -> Job:
	var job := Job.new()
	job.key = key
	job.realm = Layout.realms()[key.x]
	job.world_seed = world_seed
	return job


## Chunk key -> squared distance (tangent plane) of the chunks within radius of a point.
static func around(point: Vector3, radius: float) -> Dictionary:
	var found := {}
	var realm := Layout.realm_at(point)
	if realm == null:
		return found
	var up := (point - realm.center).normalized()
	var east := up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT).normalized()
	var north := up.cross(east)
	var steps := ceili(radius / SAMPLE_STEP)
	var limit := (radius + SAMPLE_STEP * 0.5) * (radius + SAMPLE_STEP * 0.5)
	for b in range(-steps, steps + 1):
		for a in range(-steps, steps + 1):
			var offset := Vector2(a, b) * SAMPLE_STEP
			var gap := offset.length_squared()
			if gap > limit:
				continue
			var direction := (up * realm.radius + east * offset.x + north * offset.y).normalized()
			var key := _key(realm, direction)
			if gap < float(found.get(key, INF)):
				found[key] = gap
	return found


func _center(key: Vector4i) -> Vector3:
	var realm: RealmDef = Layout.realms()[key.x]
	var cells := Terrain.grid_cells(realm)
	var half := Terrain.CHUNK_CELLS / 2
	var at := Terrain.vertex_direction(
		key.y, key.z * Terrain.CHUNK_CELLS + half, key.w * Terrain.CHUNK_CELLS + half, cells
	)
	return realm.center + at * realm.radius


func _track(nodes: Array) -> void:
	var dirty := false
	var alive := {}
	for node: Node3D in nodes:
		var id := node.get_instance_id()
		alive[id] = true
		var at := node.global_position
		var entry: Dictionary = _tracked.get(id, {})
		if entry.is_empty():
			# A new anchor (spawn, respawn, join) may stand in a realm already.
			ensure_around(at)
		if entry.is_empty() or at.distance_to(entry.pos) >= REFRESH_DISTANCE:
			_tracked[id] = {"pos": at, "near": around(at, LOAD_RADIUS)}
			dirty = true
	for id: int in _tracked.keys():
		if not alive.has(id):
			_tracked.erase(id)
			dirty = true
	if dirty:
		_requeue()
		_unload()


## Missing chunks near any anchor, nearest first.
func _requeue() -> void:
	var nearest := {}
	for entry: Dictionary in _tracked.values():
		for key: Vector4i in entry.near:
			if not bodies.has(key) and not _jobs.has(key):
				nearest[key] = minf(float(nearest.get(key, INF)), entry.near[key])
	var keys: Array = nearest.keys()
	keys.sort_custom(func(p: Vector4i, q: Vector4i) -> bool: return nearest[p] < nearest[q])
	_queue.assign(keys)


func _keep(key: Vector4i) -> bool:
	if _pinned.has(key):
		return true
	var center := _center(key)
	var limit := UNLOAD_RADIUS + CHUNK_BOUND
	for entry: Dictionary in _tracked.values():
		if center.distance_to(entry.pos) <= limit:
			return true
	return false


func _unload() -> void:
	for key: Vector4i in bodies.keys():
		if not _keep(key):
			(bodies[key] as StaticBody3D).queue_free()
			bodies.erase(key)
			chunk_removed.emit(key)


func _pump() -> void:
	var added := 0
	for key: Vector4i in _jobs.keys():
		var job: Job = _jobs[key]
		if added >= BODIES_PER_FRAME:
			break
		if not WorkerThreadPool.is_task_completed(job.task):
			continue
		WorkerThreadPool.wait_for_task_completion(job.task)
		_jobs.erase(key)
		if _keep(key):
			_add_body(key, job.faces)
			added += 1
	while _jobs.size() < MAX_JOBS and not _queue.is_empty():
		var next: Vector4i = _queue.pop_front()
		if bodies.has(next) or _jobs.has(next):
			continue
		var job := _job(next)
		job.task = WorkerThreadPool.add_task(job.run)
		_jobs[next] = job


func _add_body(key: Vector4i, faces: PackedVector3Array) -> void:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var body := StaticBody3D.new()
	body.name = "Chunk_%d_%d_%d_%d" % [key.x, key.y, key.z, key.w]
	body.collision_layer = SimPlayer.LAYER_WORLD
	body.collision_mask = 0
	body.position = (Layout.realms()[key.x] as RealmDef).center
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	bodies[key] = body
	chunk_added.emit(key)


## Debug builds: a body over a missing chunk falls through the ground (a concave shape has no
## inside), so say so instead of letting it vanish.
func _check_under(nodes: Array) -> void:
	for node: Node3D in nodes:
		var key: Variant = key_at(node.global_position)
		assert(key == null or bodies.has(key), "no terrain chunk under %s" % node.name)


func _default_anchors() -> Array:
	var found := []
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if not own_only or player.peer_id == multiplayer.get_unique_id():
			found.append(player)
	return found
