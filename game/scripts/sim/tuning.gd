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
@export var roll_speed := 11.5
@export var roll_stamina := 20.0
@export var block_speed := 2.5
## Share of damage a block stops; the rest goes through.
@export var block_reduction := 0.8
## Stamina lost per point of damage blocked; at zero stamina the guard breaks.
@export var block_stamina := 1.0
## Share of an attack's knockback a block lets through.
@export var block_knockback := 0.25
## Damage multiplier with no weapon in the main hand or no crossbow (Loadout.damage_scale).
@export var unarmed_damage := 0.35
## A block never stops more than this share of a hit, whatever a shield adds.
@export var block_cap := 0.95
## A block started this soon before a parryable hit parries it.
@export var parry_window := 0.2
@export var guard_break_time := 1.0
## Hit stun when struck unguarded, and the invulnerability after any hit (no double hits).
@export var hurt_time := 0.35
@export var hurt_invulnerable := 0.45
## Seconds a pressed action waits for the current one to allow it.
@export var input_buffer := 0.3
@export var death_time := 3.0

@export_group("Equip load")
## The worn load (Loadout.equip_load) at which the player cannot roll any more.
@export var equip_load_max := 25.0
## Load shares of the max below which the player is LIGHT and MEDIUM; below 1.0 is HEAVY.
@export var load_light_ratio := 0.4
@export var load_medium_ratio := 0.7
## Scale factors on the LIGHT numbers above, one entry per Loadout.Burden (LIGHT is 1.0). The
## OVERLOADED roll entries are never used (there is no roll). Read them through SimPlayer's
## static helpers only.
@export var roll_time_scale := PackedFloat32Array([1.0, 1.15, 1.4, 1.0])
@export var roll_speed_scale := PackedFloat32Array([1.0, 0.9, 0.7, 1.0])
@export var roll_stamina_scale := PackedFloat32Array([1.0, 1.2, 1.6, 1.0])
## On the start and end of the invulnerable window.
@export var roll_iframe_scale := PackedFloat32Array([1.0, 0.9, 0.7, 1.0])
@export var regen_scale := PackedFloat32Array([1.0, 0.85, 0.6, 0.4])
## On stamina_delay: the longer recovery.
@export var delay_scale := PackedFloat32Array([1.0, 1.0, 1.4, 1.6])
## On walk and sprint speed.
@export var move_scale := PackedFloat32Array([1.0, 0.95, 0.9, 0.75])

@export_group("Crossbow")
## Seconds to a full draw; charge scales bolt speed, damage and stamina.
@export var draw_time := 0.9
@export var bolt_speed_min := 22.0
@export var bolt_speed_max := 55.0
@export var bolt_damage_min := 10.0
@export var bolt_damage_max := 38.0
@export var bolt_stamina_min := 6.0
@export var bolt_stamina_max := 18.0
@export var shoot_recover := 0.3
@export var bolt_knockback := 4.0
@export var bolt_flinch := 0.15
@export var bolt_life := 3.0
## Walk speed while aiming or drawing.
@export var aim_speed := 3.0

## Seconds of a gravity well's pull that become drift toward it (PLAN §4.6).
@export var well_drag := 0.4


static func data() -> Tuning:
	if _data == null:
		_data = load(PATH) as Tuning
	return _data
