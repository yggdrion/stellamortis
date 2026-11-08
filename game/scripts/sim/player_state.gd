class_name PlayerState
extends RefCounted
## What the server tells clients about a player each tick, and what the client restores before
## replaying its unacknowledged inputs.

## position, velocity, up, ref_forward, facing (4 × 3 f32 + 3 f32), flags u8.
const SIZE := 61
const GROUNDED := 1

var position := Vector3.ZERO
var velocity := Vector3.ZERO
var up := Vector3.UP
var ref_forward := Vector3.FORWARD
var facing := Vector3.FORWARD
var grounded := false


func encode_into(buf: PackedByteArray, at: int) -> void:
	var offset := at
	for v: Vector3 in [position, velocity, up, ref_forward, facing]:
		buf.encode_float(offset, v.x)
		buf.encode_float(offset + 4, v.y)
		buf.encode_float(offset + 8, v.z)
		offset += 12
	buf.encode_u8(offset, GROUNDED if grounded else 0)


static func decode_from(buf: PackedByteArray, at: int) -> PlayerState:
	var state := PlayerState.new()
	var v: Array[Vector3] = []
	for i in 5:
		var o := at + i * 12
		v.append(Vector3(buf.decode_float(o), buf.decode_float(o + 4), buf.decode_float(o + 8)))
	state.position = v[0]
	state.velocity = v[1]
	state.up = v[2]
	state.ref_forward = v[3]
	state.facing = v[4]
	state.grounded = buf.decode_u8(at + 60) & GROUNDED != 0
	return state


## How far apart two states are, for deciding whether a prediction needs correcting.
func error_to(other: PlayerState) -> float:
	return maxf(position.distance_to(other.position), velocity.distance_to(other.velocity) * 0.1)
