class_name Encounter
extends Node
## The PoC fight (PLAN §4.6): three mobs, then the Warden rises; when it falls the arena rests
## and starts over. If every player is dead at once, it resets to the start. Rolled back like the
## enemies (netfox, prediction), so clients show phase changes without waiting for the server.

enum Phase { MOBS, BOSS, CLEARED }

const STATE := ["phase", "phase_time"]
## Seconds after the Warden falls before the encounter starts over.
const RESTART_AFTER := 20.0
## A wipe only counts this long after a reset, so players still lying dead from the wipe don't
## reset it again.
const WIPE_GRACE := 4.0

var phase := Phase.MOBS
var phase_time := 0
var mobs: Array[Mob] = []
var boss: Warden


func _init() -> void:
	name = "Encounter"


func networked() -> void:
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in STATE:
		rollback.state_properties.append(":" + property)
	add_child(rollback)


func mobs_left() -> int:
	var left := 0
	for mob in mobs:
		if mob.alive():
			left += 1
	return left


func _rollback_tick(_delta: float, _tick: int, _is_fresh: bool) -> void:
	phase_time += 1
	if phase_time > Combat.ticks(WIPE_GRACE) and _wiped():
		reset()
		return
	match phase:
		Phase.MOBS:
			if mobs_left() == 0:
				_set_phase(Phase.BOSS)
				boss.wake(get_tree().get_nodes_in_group(SimPlayer.GROUP).size())
				SimPlayer._mutate(boss)
		Phase.BOSS:
			if boss.action == Enemy.Action.DOWN:
				_set_phase(Phase.CLEARED)
		Phase.CLEARED:
			if phase_time >= Combat.ticks(RESTART_AFTER):
				reset()


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


func _wiped() -> bool:
	var players := get_tree().get_nodes_in_group(SimPlayer.GROUP)
	if players.is_empty():
		return false
	for node in players:
		if (node as SimPlayer).action != SimPlayer.Action.DEAD:
			return false
	return true
