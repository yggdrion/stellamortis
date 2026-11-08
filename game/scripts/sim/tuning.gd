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


static func data() -> Tuning:
	if _data == null:
		_data = load(PATH) as Tuning
	return _data
