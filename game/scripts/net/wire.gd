class_name Wire
extends RefCounted
## How synchronized properties go over the network (PLAN §4.3): one netfox schema serializer
## per property name, so nothing falls back to netfox's generic Variant encoding (4 bytes of
## type per value and 8-byte floats). A player's full state fits one 508 byte packet this way.
## Positions, directions and floats keep 32 bits: rollback resimulates from these values, so
## they stay as exact as the simulation's own.
##
## Groups of fields also travel packed into one byte array (pack/unpack, behind `net_*`
## properties with a getter and setter): netfox records, diffs and serializes every synced
## property separately for every peer on every resimulated tick, in GDScript, and that per
## property cost was what kept the server from holding 30 ticks with 10 players (PLAN M7).

## Property name -> serializer, for every name in SimPlayer.STATE, PlayerControls.INPUT,
## Enemy.STATE and Encounter.STATE.
static var _table := {}


## A RollbackSynchronizer schema for these properties of root ("" for the root node itself).
static func schema(properties: Array, node_path := "") -> Dictionary:
	var result := {}
	for property: String in properties:
		result["%s:%s" % [node_path, property]] = serializer(property)
	return result


static func serializer(property: String) -> NetworkSchemaSerializer:
	if _table.is_empty():
		_fill()
	assert(_table.has(property), "Wire has no serializer for %s" % property)
	return _table[property]


## The fields' values, encoded one after another.
static func pack(node: Object, fields: Array) -> PackedByteArray:
	var buffer := StreamPeerBuffer.new()
	for field: String in fields:
		serializer(field).encode(node.get(field), buffer)
	return buffer.data_array


## Sets the fields from bytes made by pack(); empty bytes change nothing. Returns how many bytes
## it read.
static func unpack(node: Object, fields: Array, bytes: PackedByteArray) -> int:
	if bytes.is_empty():
		return 0
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = bytes
	for field: String in fields:
		node.set(field, serializer(field).decode(buffer))
	return buffer.get_position()


static func has(property: String) -> bool:
	if _table.is_empty():
		_fill()
	return _table.has(property)


static func _fill() -> void:
	var vec := NetworkSchemas.vec3f32()
	var f32 := NetworkSchemas.float32()
	var u8 := NetworkSchemas.uint8()
	var u16 := NetworkSchemas.uint16()
	# Tick counters only grow from zero: 1 byte up to 127, 2 up to 16383.
	var counter := NetworkSchemas.varuint()
	var entries := {
		"transform": NetworkSchemas.transform3f32(),
		"velocity": vec,
		"up": vec,
		"ref_forward": vec,
		"facing": vec,
		"action_dir": vec,
		"grounded": NetworkSchemas.bool8(),
		"parried": NetworkSchemas.bool8(),
		"occupied": NetworkSchemas.bool8(),
		"health": f32,
		"max_health": f32,
		"stamina": f32,
		"charge": f32,
		"action": u8,
		"kind": u8,
		"attack": u8,
		"queued": u8,
		"weapon": u8,
		"phase": u8,
		"combo": counter,
		"action_time": counter,
		"action_length": counter,
		"stamina_wait": counter,
		"queued_age": counter,
		"invulnerable": counter,
		"respawns": counter,
		"quiet_time": counter,
		"flinch_time": counter,
		"well_time": counter,
		"phase_time": counter,
		"swing_hits": NetworkSchemas.uint32(),
		"last_buttons": u16,
		"bolt_pos": PackedVectors.new(),
		"bolt_vel": PackedVectors.new(),
		"bolt_life": PackedCounters.new(),
		"bolt_damage": PackedFloats.new(),
		# Packed groups (pack/unpack).
		"net_motion": Bytes.new(),
		"net_combat": Bytes.new(),
		"net_bolts": Bytes.new(),
		# Input.
		"move": NetworkSchemas.vec2f32(),
		"yaw": f32,
		"pitch": f32,
		"buttons": u16,
	}
	_table = entries


## A PackedByteArray with its length in front.
class Bytes:
	extends NetworkSchemaSerializer

	var _length := NetworkSchemas.varuint()

	func encode(value: Variant, buffer: StreamPeerBuffer) -> void:
		var bytes := value as PackedByteArray
		_length.encode(bytes.size(), buffer)
		buffer.put_data(bytes)

	func decode(buffer: StreamPeerBuffer) -> Variant:
		var size: int = _length.decode(buffer)
		return buffer.get_data(size)[1] as PackedByteArray


## A PackedVector3Array of up to 255 items, 32 bit floats.
class PackedVectors:
	extends NetworkSchemaSerializer

	func encode(value: Variant, buffer: StreamPeerBuffer) -> void:
		var items := value as PackedVector3Array
		buffer.put_u8(items.size())
		for item in items:
			buffer.put_float(item.x)
			buffer.put_float(item.y)
			buffer.put_float(item.z)

	func decode(buffer: StreamPeerBuffer) -> Variant:
		var items := PackedVector3Array()
		items.resize(buffer.get_u8())
		for i in items.size():
			items[i] = Vector3(buffer.get_float(), buffer.get_float(), buffer.get_float())
		return items


## A PackedInt32Array of up to 255 values from 0 to 255 (ticks left).
class PackedCounters:
	extends NetworkSchemaSerializer

	func encode(value: Variant, buffer: StreamPeerBuffer) -> void:
		var items := value as PackedInt32Array
		buffer.put_u8(items.size())
		for item in items:
			buffer.put_u8(clampi(item, 0, 255))

	func decode(buffer: StreamPeerBuffer) -> Variant:
		var items := PackedInt32Array()
		items.resize(buffer.get_u8())
		for i in items.size():
			items[i] = buffer.get_u8()
		return items


## A PackedFloat32Array of up to 255 items.
class PackedFloats:
	extends NetworkSchemaSerializer

	func encode(value: Variant, buffer: StreamPeerBuffer) -> void:
		var items := value as PackedFloat32Array
		buffer.put_u8(items.size())
		for item in items:
			buffer.put_float(item)

	func decode(buffer: StreamPeerBuffer) -> Variant:
		var items := PackedFloat32Array()
		items.resize(buffer.get_u8())
		for i in items.size():
			items[i] = buffer.get_float()
		return items
