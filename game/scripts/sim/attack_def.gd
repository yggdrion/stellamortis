class_name AttackDef
extends Resource
## One melee attack (PLAN §4.5), for players and enemies. Times are in seconds and become
## network ticks through Combat.ticks. Files live in res://data/attacks/, the id is the file name.

## Telegraph before the hit: the attacker is committed and can't turn.
@export var windup := 0.3
## The hit window: targets in reach and arc during it get hit (once per swing).
@export var active := 0.12
@export var recover := 0.3
@export var damage := 20.0
@export var stamina := 12.0
@export var reach := 2.3
@export var arc_degrees := 110.0
## Forward speed during windup and active, m/s (a step into the swing).
@export var lunge := 2.0
## Whether a well-timed block (parry) can stagger the attacker.
@export var parryable := true
## Next attack in the combo when attack is pressed again during recover; empty ends it.
@export var next: StringName = &""
## Animation in the KayKit rig, stretched to windup + active + recover.
@export var animation: StringName = &"1H_Melee_Attack_Slice_Diagonal"


func windup_ticks() -> int:
	return Combat.ticks(windup)


func active_end_ticks() -> int:
	return Combat.ticks(windup + active)


func total_ticks() -> int:
	return Combat.ticks(windup + active + recover)
