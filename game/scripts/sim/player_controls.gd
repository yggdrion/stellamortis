class_name PlayerControls
extends Node
## A player's input for one network tick (PLAN §4.3). Owned by that player's peer; netfox's
## RollbackSynchronizer sends it to the server and replays it during rollback. The owning client
## fills it from `reader` before every tick loop.

enum Buttons { JUMP = 1, SPRINT = 2 }

## x right, y forward, length at most 1, relative to the look direction.
var move := Vector2.ZERO
## Radians around the player's up, from its reference forward (SimPlayer.ref_forward).
var yaw := 0.0
var buttons := 0
## Called on the owning peer before each tick loop to fill move, yaw and buttons.
var reader: Callable


func _ready() -> void:
	NetworkTime.before_tick_loop.connect(_gather)


func has(button: Buttons) -> bool:
	return buttons & button != 0


func _gather() -> void:
	if is_multiplayer_authority() and reader.is_valid():
		reader.call(self)
