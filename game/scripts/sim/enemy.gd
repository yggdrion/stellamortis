class_name Enemy
extends CharacterBody3D
## What players fight (PLAN §4.5): server-owned, rolled back by netfox with prediction, so
## clients simulate it between server states. Players check enemy swings in their own rollback
## tick (SimPlayer._defend) and hit enemies with take_hit + NetworkRollback.mutate. M2 has only
## the TrainingDummy; M5 adds mobs and the boss on the same interface.

enum Action { IDLE, WINDUP, STRIKE, RECOVER, STAGGER, DOWN }

const HEIGHT := 1.8
const RADIUS := 0.5
const GROUP := &"enemies"
## Rolled back state; subclasses append their own.
const STATE := ["transform", "facing", "health", "action", "action_time", "parried", "quiet_time"]

## Stable across peers (World assigns it): the bit in a player's swing_hits.
var index := 0
var max_health := 400.0
var attack_id: StringName = &"dummy_swing"
## Damage multiplier for hits while staggered by a parry.
var riposte := 2.5
var stagger_time := 1.5
var down_time := 2.0

var facing := Vector3.FORWARD
var health := 400.0
var action := Action.IDLE
var action_time := 0
## Staggered by a parry (riposte bonus), not by something else.
var parried := false
## Ticks since it last took damage.
var quiet_time := 0


func _init() -> void:
	collision_layer = SimPlayer.LAYER_WORLD
	collision_mask = SimPlayer.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = HEIGHT
	capsule.radius = RADIUS
	shape.shape = capsule
	shape.position = Vector3(0.0, HEIGHT / 2.0, 0.0)
	add_child(shape)
	add_to_group(GROUP)


## Server-owned, predicted on clients. Call before adding it to the tree, on every peer.
func networked(state: Array) -> void:
	var rollback := RollbackSynchronizer.new()
	rollback.name = "Rollback"
	rollback.root = self
	rollback.enable_prediction = true
	for property: String in state:
		rollback.state_properties.append(":" + property)
	add_child(rollback)


func attack_def() -> AttackDef:
	return Combat.attack(attack_id)


func center() -> Vector3:
	return global_position + global_basis.y * (HEIGHT / 2.0)


func up() -> Vector3:
	return global_basis.y


func alive() -> bool:
	return action != Action.DOWN


## In the hit window of its attack this tick.
func striking() -> bool:
	return action == Action.STRIKE


## A player's hit. Returns the damage dealt.
func take_hit(amount: float) -> float:
	if not alive():
		return 0.0
	if action == Action.STAGGER and parried:
		amount *= riposte
	health -= amount
	quiet_time = 0
	if health <= 0.0:
		health = 0.0
		_set_action(Action.DOWN)
	return amount


## A player parried its swing.
func parry() -> void:
	_set_action(Action.STAGGER)
	parried = true


func _set_action(next: Action) -> void:
	action = next
	action_time = 0
	if next != Action.STAGGER:
		parried = false


## Nearest living player within range, null if none.
func nearest_player(within: float) -> SimPlayer:
	var best: SimPlayer = null
	var best_distance := within
	for node in get_tree().get_nodes_in_group(SimPlayer.GROUP):
		var player := node as SimPlayer
		if player.action == SimPlayer.Action.DEAD:
			continue
		var distance := player.global_position.distance_to(global_position)
		if distance < best_distance:
			best = player
			best_distance = distance
	return best
