class_name World
extends Node3D
## What server and client share at the same node path (/root/Main/Game/World): the arena and
## the players, spawned by the server through a MultiplayerSpawner so late joiners get them too.

signal player_spawned(player: SimPlayer)

## Enemy slots after the dummies (a fixed pool, PLAN §4.8).
const POOL := 20

var visual := false
## The seed everything generated comes from, set by build() (identical on every peer).
var world_seed := 0
var world_name := ""
var built := false
var arena: Arena
var players: Node3D
## The first realm's boss fight (encounters has one per realm, in Layout.realms() order).
var encounter: Encounter
var encounters: Array[Encounter] = []
var chunks: TerrainChunks
## Server only (add_spawner): wakes and frees pool slots.
var spawner: Spawner
var _spawner: MultiplayerSpawner
var _enemies: Node3D


func _init(with_visuals: bool) -> void:
	name = "World"
	visual = with_visuals


func _ready() -> void:
	arena = Arena.new(visual)
	add_child(arena)
	players = Node3D.new()
	players.name = "Players"
	add_child(players)
	_spawner = MultiplayerSpawner.new()
	_spawner.name = "Spawner"
	_spawner.spawn_path = NodePath("../Players")
	_spawner.spawn_function = _spawn_player
	add_child(_spawner)
	_enemies = Node3D.new()
	_enemies.name = "Enemies"
	add_child(_enemies)
	_add_dummies()
	_add_pool()


## Builds what is generated from the seed: the terrain collision of every realm, streamed
## (TerrainChunks) with the arrival chunks always there. Server at start, client when Net.world
## arrives; the nodes the netcode finds by path (the spawner, players, enemies) already exist
## from _ready. Once only.
func build(new_seed: int, new_name: String) -> void:
	if built:
		return
	world_seed = new_seed
	world_name = new_name
	built = true
	# One world per process (a server, or a client of one): gates and arrivals read this seed.
	Layout.set_world_seed(new_seed)
	chunks = TerrainChunks.new(new_seed, visual)
	add_child(chunks)
	for realm in Layout.realms():
		chunks.pin_around(Terrain.surface(realm, new_seed, realm.arrival))
	_post_dummies()
	_post_bosses()
	if arena != null:
		arena.add_arrival_solids()
	if visual:
		arena.add_seeded_portals()
		arena.add_terrain_views(new_seed)


## The same dummies, same names and order, on every peer (netfox finds them by path). They stand
## beside the first realm's arrival once the seed is known (build); the ground under them is
## pinned there, so they need no anchor.
func _add_dummies() -> void:
	for i in Layout.DUMMIES.size():
		var dummy := Enemy.new()
		dummy.name = "Dummy%d" % i
		dummy.index = i
		dummy.kind = Combat.enemy_kind(&"dummy")
		dummy.passive = Layout.DUMMIES[i][2]
		dummy.networked()
		dummy.health = dummy.def.health
		dummy.max_health = dummy.def.health
		if visual:
			dummy.add_child(EnemyView.new(dummy))
		_enemies.add_child(dummy)


## Stands the dummies on the ground by the arrival, facing the spawn ring.
func _post_dummies() -> void:
	if _enemies == null:
		return  # not in the tree yet (a bare build in a test)
	for i in Layout.DUMMIES.size():
		var post := Layout.dummy_post(i)
		var up: Vector3 = post[1]
		var facing := SimPlayer._tangent(Vector3.FORWARD, up)
		var dummy := _enemies.get_node("Dummy%d" % i) as Enemy
		dummy.become(
			dummy.kind, Transform3D(SimPlayer.frame(up, facing), post[0]), Enemy.Action.IDLE
		)


## Stands each realm's Warden, hidden, at the middle of its boss site (the seed is known now).
func _post_bosses() -> void:
	for encounter_node in encounters:
		encounter_node.site = BossSite.at(encounter_node.realm, world_seed)
		encounter_node.boss.become(
			Combat.enemy_kind(&"warden"), encounter_node.post(), Enemy.Action.HIDDEN
		)


## The world flags that are set (names, from the realms whose bosses have fallen), read from the
## encounters' rolled back phase.
func flags() -> Array[StringName]:
	var found: Array[StringName] = []
	for encounter_node in encounters:
		if encounter_node.phase == Encounter.Phase.CLEARED:
			found.append(encounter_node.realm.boss_flag)
	return found


## The enemy pool (M21): POOL free slots, hidden, at fixed names and indices after the dummies;
## waking one is `Enemy.become`, never a spawn. Every slot has room for the biggest kind's bolts.
## The first slots, one per realm, are its Warden's (Spawner.FIRST_SLOT): they stay hidden until
## a player enters the ring of its boss site (Encounter); the spawner has the rest.
func _add_pool() -> void:
	var bolts := 0
	for kind in Combat.ENEMY_KINDS.size():
		bolts = maxi(bolts, Combat.enemy_def(kind).bolt_slots)
	var free := Combat.enemy_kind(&"free")
	for i in POOL:
		var slot := Enemy.new()
		slot.name = "Pool%d" % i
		slot.index = Layout.DUMMIES.size() + i
		slot.kind = free
		slot.make_bolts(bolts)
		slot.networked()
		if visual:
			slot.add_child(EnemyView.new(slot))
		_enemies.add_child(slot)
		slot.reset(Enemy.Action.HIDDEN)
	assert(Layout.realms().size() <= Spawner.FIRST_SLOT, "a boss slot per realm")
	for i in Layout.realms().size():
		var fight := Encounter.new()
		fight.name = "Encounter_%s" % Layout.realms()[i].id
		fight.realm = Layout.realms()[i]
		fight.boss = pool_slot(i)
		fight.boss.kind = Combat.enemy_kind(&"warden")
		fight.networked()
		add_child(fight)
		encounters.append(fight)
	encounter = encounters[0]


## Pool slot i (0 to POOL - 1).
func pool_slot(i: int) -> Enemy:
	return _enemies.get_node("Pool%d" % i) as Enemy


## Server only, after build: the camps and roamers of the realms wake and sleep in pool slots.
func add_spawner() -> void:
	spawner = Spawner.new(self)
	add_child(spawner)


## Server only: spawns a player on every peer.
func spawn_player(peer_id: int, player_name: String, at: Vector3) -> void:
	_spawner.spawn([peer_id, player_name, at])


func player(peer_id: int) -> SimPlayer:
	return players.get_node_or_null("Player%d" % peer_id) as SimPlayer


func _spawn_player(data: Array) -> Node:
	var peer_id: int = data[0]
	var player_name: String = data[1]
	var body := SimPlayer.new()
	body.player_name = player_name
	body.networked(peer_id, visual)
	body.place(data[2], Vector3.BACK)
	if visual:
		var own := peer_id == multiplayer.get_unique_id()
		body.add_child(PlayerView.new(body, not own))
	player_spawned.emit.call_deferred(body)
	return body
