class_name Encounter
extends Node
## The realm's fight (PLAN §4.6, §6 M12): three mobs, then the Warden rises; when it falls a
## portal home opens. Once nobody is left in the realm (they went home, or all died and woke at
## the keep), it resets for the next visit. Rolled back like the enemies (netfox, prediction), so
## clients show phase changes without waiting for the server.

enum Phase { MOBS, BOSS, CLEARED }

const STATE := ["phase", "phase_time", "occupied"]
const GROUP := &"encounter"

var phase := Phase.MOBS
var phase_time := 0
## Someone was in the realm last tick; when the last one leaves, the realm resets.
var occupied := false
var mobs: Array[Enemy] = []
var boss: Enemy


func _init() -> void:
	name = "Encounter"
	add_to_group(GROUP)


## The Warden is down: the victory portal is open.
static func won(from_node: Node) -> bool:
	var encounter := from_node.get_tree().get_first_node_in_group(GROUP) as Encounter
	return encounter != null and encounter.phase == Phase.CLEARED


func networked() -> void:
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in STATE:
		rollback.state_properties.append(":" + property)
	rollback.set_schema(Wire.schema(STATE))
	add_child(rollback)


func mobs_left() -> int:
	var left := 0
	for mob in mobs:
		if mob.alive():
			left += 1
	return left


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	phase_time += 1
	var someone := _anyone_in_realm()
	if occupied and not someone:
		occupied = false
		reset()
		return
	occupied = someone
	match phase:
		Phase.MOBS:
			if mobs_left() == 0:
				_set_phase(Phase.BOSS)
				boss.wake(get_tree().get_nodes_in_group(SimPlayer.GROUP).size())
				SimPlayer._mutate(boss)
		Phase.BOSS:
			if boss.action == Enemy.Action.DOWN:
				_set_phase(Phase.CLEARED)


## Mobs back at their posts, the Warden hidden again.
func reset() -> void:
	_set_phase(Phase.MOBS)
	for mob in mobs:
		mob.reset(Enemy.Action.IDLE)
		SimPlayer._mutate(mob)
	boss.reset(Enemy.Action.HIDDEN)
	SimPlayer._mutate(boss)


func _set_phase(next: Phase) -> void:
	phase = next
	phase_time = 0


func _anyone_in_realm() -> bool:
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		if Layout.place_at((node as SimPlayer).global_position) == Layout.ORIGIN_PLACE:
			return true
	return false
