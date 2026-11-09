class_name Tuning
extends Resource
## Every movement number, loaded once from res://data/tuning.tres (PLAN §4.5: numbers live in
## data, not code).

const PATH := "res://data/tuning.tres"

static var _data: Tuning

@export var walk_speed := 5.0
@export var sprint_speed := 8.0
## m/s² toward the wished horizontal velocity on the ground and in the air.
@export var ground_accel := 40.0
@export var air_accel := 8.0
@export var jump_speed := 6.0
## How fast the body turns toward where it walks, per second (exponential).
@export var turn_rate := 12.0
## Seconds the up vector takes to follow a new gravity direction.
@export var up_turn_time := 0.25

@export_group("Combat")
@export var max_health := 100.0
@export var max_stamina := 100.0
## Per second, once stamina_delay passed since the last spend.
@export var stamina_regen := 35.0
@export var stamina_delay := 0.8
@export var sprint_stamina := 10.0
@export var roll_time := 0.6
## The roll's invulnerable window, seconds from its start.
@export var roll_iframes_start := 0.06
@export var roll_iframes_end := 0.4
@export var roll_speed := 8.5
@export var roll_stamina := 20.0
@export var block_speed := 2.5
## Share of damage a block stops; the rest goes through.
@export var block_reduction := 0.8
## Stamina lost per point of damage blocked; at zero stamina the guard breaks.
@export var block_stamina := 1.0
## A block started this soon before a parryable hit parries it.
@export var parry_window := 0.2
@export var guard_break_time := 1.0
## Hit stun when struck unguarded, and the invulnerability after any hit (no double hits).
@export var hurt_time := 0.35
@export var hurt_invulnerable := 0.45
## Seconds a pressed action waits for the current one to allow it.
@export var input_buffer := 0.3
@export var death_time := 3.0


static func data() -> Tuning:
	if _data == null:
		_data = load(PATH) as Tuning
	return _data
