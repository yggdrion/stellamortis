class_name Encounter
extends Node
## A realm's boss fight (PLAN §4.6, M22), one per generated realm, at its BossSite: a player
## entering the ring raises the Warden from its reserved pool slot (health for the players in the
## ring); when no living player is left within the site's reach the fight resets; when the
## Warden falls the phase is CLEARED for good and the realm's world flag is set (World.flags).
## Rolled back like the enemies (netfox, prediction), so clients show phase changes without
## waiting for the server, and a client that joins late gets CLEARED with the rest of the state:
## the flag is that phase, there is nothing else to sync.

enum Phase { IDLE, BOSS, CLEARED }

const STATE := ["phase", "phase_time"]
const GROUP := &"encounter"

var phase := Phase.IDLE
var phase_time := 0
var realm: RealmDef
## Set once the world seed is known (World.build): where the ring stands.
var site: BossSite
## The reserved pool slot the Warden rises from.
var boss: Enemy


func _init() -> void:
	name = "Encounter"
	add_to_group(GROUP)


## The encounter of a realm (by id) among the nodes of this tree, null if none.
static func of(from_node: Node, realm_id: String) -> Encounter:
	for node in from_node.get_tree().get_nodes_in_group(GROUP):
		var encounter := node as Encounter
		if encounter.realm != null and encounter.realm.id == realm_id:
			return encounter
	return null


## Whether a world flag (World.flags) is set: the realm whose boss_flag it is has its boss down.
static func flag_set(from_node: Node, flag: StringName) -> bool:
	for node in from_node.get_tree().get_nodes_in_group(GROUP):
		var encounter := node as Encounter
		if encounter.phase == Phase.CLEARED and encounter.realm.boss_flag == flag:
			return true
	return false


func networked() -> void:
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in STATE:
		rollback.state_properties.append(":" + property)
	rollback.set_schema(Wire.schema(STATE))
	add_child(rollback)


## Where the Warden stands when it rises: the center of the ring, on the ground.
func post() -> Transform3D:
	var up := site.direction
	var feet := site.center() + up * Spawner.LIFT
	return Transform3D(SimPlayer.frame(up, SimPlayer._tangent(Vector3.FORWARD, up)), feet)


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	if site == null:
		return
	phase_time += 1
	match phase:
		Phase.IDLE:
			var inside := _living_within(BossSite.RING_RADIUS)
			if inside > 0:
				_set_phase(Phase.BOSS)
				_ensure_ground()
				boss.wake(inside)
				SimPlayer._mutate(boss)
		Phase.BOSS:
			if boss.action == Enemy.Action.DOWN:
				_set_phase(Phase.CLEARED)
			elif _living_within(BossSite.REACH) == 0:
				reset()


## A saved world whose Warden had fallen: the fight stays cleared and its corpse lies at the
## post. Called before any player is spawned, so no replayed tick can see the old state.
func restore_cleared() -> void:
	_set_phase(Phase.CLEARED)
	boss.become(Combat.enemy_kind(&"warden"), post(), Enemy.Action.DOWN)
	boss.health = 0.0
	SimPlayer._mutate(boss)


## The Warden hidden again, the ring waiting.
func reset() -> void:
	_set_phase(Phase.IDLE)
	boss.reset(Enemy.Action.HIDDEN)
	SimPlayer._mutate(boss)


func _set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0


## Living players within meters of the ring's center.
func _living_within(meters: float) -> int:
	var count := 0
	var center := site.center()
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if (
			player.action != SimPlayer.Action.DEAD
			and player.global_position.distance_to(center) <= meters
		):
			count += 1
	return count


## The ground under the Warden stands before it does (a no-op where it already does).
func _ensure_ground() -> void:
	var chunks := get_tree().get_first_node_in_group(TerrainChunks.GROUP) as TerrainChunks
	if chunks:
		chunks.ensure_around(site.center(), Spawner.GROUND_RADIUS)
