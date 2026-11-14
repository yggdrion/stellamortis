class_name EnemyDef
extends Resource
## One kind of enemy (M21): body, stats, ranges and which behavior runs it. Files live in
## res://data/enemies/, listed by Combat.ENEMY_KINDS (a slot's rolled back `kind` indexes it).
## Times are in seconds, speeds in m/s.

## Which logic moves it (Enemy._rollback_tick): DUMMY stands and swings, MELEE and RANGED are
## the mob (Mob.tick), BOSS_WARDEN is the Warden's (Warden.tick). NONE is the free slot.
enum Behavior { NONE, DUMMY, MELEE, RANGED, BOSS_WARDEN }

## How EnemyView dresses it: free (nothing), squire, swordsman, archer, warden.
@export var look: StringName = &"free"
@export var behavior := Behavior.NONE
@export var health := 90.0
@export var speed := 3.6
## Radians per second it turns toward a target.
@export var turn_rate := 6.0
@export var radius := 0.5
@export var height := 1.8
## Shortest flinch (AttackDef.flinch) that interrupts a swing in progress.
@export var poise := 0.3
@export var flinches := true
## Share of an attack's knockback it takes (heavy bodies slide less).
@export var shove := 1.0
## Damage multiplier for hits while staggered by a parry.
@export var riposte := 2.5
@export var stagger_time := 1.5
## Dummy: seconds on the ground before it gets back up.
@export var down_time := 2.0
## Dummy: seconds without damage before it heals up.
@export var heal_after := 0.0
## It notices players this far away (plus its distance from its post).
@export var notice := 16.0
## It gives up on players this far from its post and walks back.
@export var leash := 24.0
## Ranged: the distance band it tries to keep.
@export var keep_near := 7.0
@export var keep_far := 13.0
## Seconds between attacks.
@export var rest := 0.8
## Attack ids it uses (the rolled back `attack` indexes this), and the one its bolts deal.
@export var attacks: Array[StringName] = [&"dummy_swing"]
@export var shot_attack: StringName = &""
## Bolt slots it needs (World gives a slot node that many).
@export var bolt_slots := 0
## Seconds it takes to rise when woken.
@export var rise_time := 3.0
## Extra health per player beyond the first, as a share of `health` (bosses).
@export var per_player := 0.0
## Boss: below half health it winds up this much faster and walks at phase_2_speed.
@export var phase_2_pace := 1.0
@export var phase_2_speed := 0.0
## Boss: the attack that opens a gravity well (empty: none), how long it pulls, how far, how hard.
@export var well_attack: StringName = &""
@export var well_time := 0.0
@export var well_reach := 0.0
@export var well_pull := 0.0
