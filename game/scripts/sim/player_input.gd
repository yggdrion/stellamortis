class_name PlayerInput
extends RefCounted
## One tick of a player's input, as the client sends it. The client predicts with the
## quantized() copy, so its prediction uses exactly what the server will decode.

enum Buttons { JUMP = 1, SPRINT = 2 }

## tick u32, move x s8, move y s8, yaw u16, buttons u8.
const SIZE := 9

var tick := 0
## x right, y forward, length at most 1, relative to the look direction.
var move := Vector2.ZERO
## Radians around the player's up, from its reference forward (SimPlayer.ref_forward).
var yaw := 0.0
var buttons := 0


func has(button: Buttons) -> bool:
	return buttons & button != 0


func encode_into(buf: PackedByteArray, at: int) -> void:
	buf.encode_u32(at, tick)
	buf.encode_s8(at + 4, roundi(clampf(move.x, -1.0, 1.0) * 127.0))
	buf.encode_s8(at + 5, roundi(clampf(move.y, -1.0, 1.0) * 127.0))
	buf.encode_u16(at + 6, roundi(fposmod(yaw, TAU) / TAU * 65535.0) % 65536)
	buf.encode_u8(at + 8, buttons)


static func decode_from(buf: PackedByteArray, at: int) -> PlayerInput:
	var input := PlayerInput.new()
	input.tick = buf.decode_u32(at)
	input.move = Vector2(buf.decode_s8(at + 4), buf.decode_s8(at + 5)) / 127.0
	input.yaw = buf.decode_u16(at + 6) / 65535.0 * TAU
	input.buttons = buf.decode_u8(at + 8)
	return input


func quantized() -> PlayerInput:
	var buf := PackedByteArray()
	buf.resize(SIZE)
	encode_into(buf, 0)
	return decode_from(buf, 0)
