class_name World
extends Node3D
## What server and client share at the same node path (/root/Main/Game/World): the arena and
## the players, spawned by the server through a MultiplayerSpawner so late joiners get them too.

signal player_spawned(player: SimPlayer)

var visual := false
## The seed everything generated comes from, set by build() (identical on every peer).
var world_seed := 0
var world_name := ""
var built := false
var arena: Arena
var players: Node3D
var encounter: Encounter
var chunks: TerrainChunks
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
	_add_encounter()


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
	if visual:
		arena.add_seeded_portals()
		arena.add_terrain_views(new_seed)


## The same dummies, same names and order, on every peer (netfox finds them by path).
func _add_dummies() -> void:
	for i in Layout.DUMMIES.size():
		var dummy := Enemy.new()
		dummy.name = "Dummy%d" % i
		dummy.index = i
		dummy.kind = Combat.enemy_kind(&"dummy")
		dummy.passive = Layout.DUMMIES[i][1]
		dummy.networked(Enemy.STATE)
		dummy.position = Layout.DUMMIES[i][0]
		dummy.facing = Vector3.BACK
		dummy.basis = SimPlayer.frame(Vector3.UP, dummy.facing)
		dummy.health = dummy.def.health
		dummy.max_health = dummy.def.health
		if visual:
			dummy.add_child(EnemyView.new(dummy))
		_enemies.add_child(dummy)


## The mobs and the Warden (hidden until the mobs are dead), indices after the dummies.
func _add_encounter() -> void:
	encounter = Encounter.new()
	var next := Layout.DUMMIES.size()
	for i in Layout.MOBS.size():
		var mob := Enemy.new()
		mob.name = "Mob%d" % i
		var id := &"archer" if Layout.MOBS[i][1] else &"swordsman"
		_add_enemy(mob, next + i, id, Layout.MOBS[i][0], Enemy.Action.IDLE)
		encounter.mobs.append(mob)
	var boss := Enemy.new()
	boss.name = "Warden"
	_add_enemy(boss, next + Layout.MOBS.size(), &"warden", Layout.BOSS, Enemy.Action.HIDDEN)
	encounter.boss = boss
	encounter.networked()
	add_child(encounter)


## A slot of a kind (its id in Combat.ENEMY_KINDS) with the bolt slots that kind needs.
func _add_enemy(enemy: Enemy, index: int, id: StringName, at: Vector3, start: Enemy.Action) -> void:
	enemy.index = index
	enemy.kind = Combat.enemy_kind(id)
	enemy.make_bolts(enemy.def.bolt_slots)
	enemy.home = Transform3D(SimPlayer.frame(Gravity.up_at(at), Vector3.FORWARD), at)
	enemy.networked(Enemy.STATE)
	if visual:
		enemy.add_child(EnemyView.new(enemy))
	_enemies.add_child(enemy)
	enemy.reset(start)


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
