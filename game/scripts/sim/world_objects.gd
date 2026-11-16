class_name WorldObjects
extends RefCounted
## The things lying in the world that are not enemies (M23): drops, chests, graves (task 4), later
## resource nodes and built pieces. Server data, never rollback nodes; clients hear of changes by
## reliable RPC and draw them (ObjectsView). Pure: Looting (net/looting.gd) decides, this keeps
## the registry and turns it into dictionaries for the wire and for the world file.

enum Kind { DROP, CHEST, GRAVE }

## A drop nobody picks up goes after this many world seconds.
const DROP_LIFETIME := 600.0
## from_dict keeps at most this many objects (a hostile or broken file).
const MAX_OBJECTS := 5000

## Object id (counting up, never reused) -> Entry.
var entries := {}
var next_id := 1


class Entry:
	extends RefCounted
	var kind := Kind.DROP
	## What it holds: a drop one stack in bag cell 0, a chest or grave a whole inventory.
	var contents := Inventory.new()
	var position := Vector3.ZERO
	## The direction away from the realm's center, where up is.
	var up := Vector3.UP
	## Player ID (a string) that may open a grave first, "" for everyone.
	var owner := ""
	## World seconds it appeared.
	var born := 0.0
	## Small state that is saved and sent: a chest's "opened", "realm", "camp" and "yaw".
	var flags := {}
	## Not saved: world seconds before which nobody picks a dropped item up, and whether the
	## bag was full the last time it tried.
	var hold_until := 0.0
	var warned := false

	## The first stack of a drop.
	func stack() -> Inventory.Stack:
		return contents.cells[0]

	## What clients get: kind, place, the item of a drop, flags.
	func to_net() -> Dictionary:
		var data := {"kind": kind, "pos": position, "up": up, "flags": flags}
		var held := stack()
		if kind == Kind.DROP and held != null:
			data["item"] = String(held.id)
			data["count"] = held.count
		return data

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"contents": contents.cell_dict(),
			"position": [position.x, position.y, position.z],
			"up": [up.x, up.y, up.z],
			"owner": owner,
			"born": born,
			"flags": flags,
		}


## Adds an object and returns its id.
func add(
	kind: Kind,
	contents: Inventory,
	position: Vector3,
	up: Vector3,
	born := 0.0,
	owner := "",
	flags := {}
) -> int:
	var entry := Entry.new()
	entry.kind = kind
	entry.contents = contents
	entry.position = position
	entry.up = up
	entry.born = born
	entry.owner = owner
	entry.flags = flags
	var id := next_id
	next_id += 1
	entries[id] = entry
	return id


## A drop of one stack.
func add_drop(stack: Inventory.Stack, position: Vector3, up: Vector3, born: float) -> int:
	var contents := Inventory.new()
	contents.cells[0] = stack
	return add(Kind.DROP, contents, position, up, born)


func remove(id: int) -> bool:
	return entries.erase(id)


## The entry of an id, null when it is gone (`get` would clash with Object.get).
func at(id: int) -> Entry:
	return entries.get(id)


## Merges changes into an object's flags; false when it is gone.
func update(id: int, changes: Dictionary) -> bool:
	var entry := at(id)
	if entry == null:
		return false
	entry.flags.merge(changes, true)
	return true


## Ids of the drops that lay there long enough at world second `now`.
func expired(now: float) -> Array[int]:
	var gone: Array[int] = []
	for id: int in entries:
		var entry: Entry = entries[id]
		if entry.kind == Kind.DROP and now - entry.born >= DROP_LIFETIME:
			gone.append(id)
	return gone


## Whether a chest with this key ("realm:camp") exists already.
func has_chest(key: String) -> bool:
	for id: int in entries:
		var entry: Entry = entries[id]
		if entry.kind == Kind.CHEST and entry.flags.get("key", "") == key:
			return true
	return false


## Every object as clients know it: id -> Entry.to_net().
func snapshot() -> Dictionary:
	var all := {}
	for id: int in entries:
		all[id] = (entries[id] as Entry).to_net()
	return all


func to_dict() -> Dictionary:
	var saved := {}
	for id: int in entries:
		saved[id] = (entries[id] as Entry).to_dict()
	return {"next_id": next_id, "entries": saved}


## Reads what to_dict wrote; what cannot be read is skipped, counts are clamped like an
## inventory's, and nothing throws.
static func from_dict(data: Variant) -> WorldObjects:
	var objects := WorldObjects.new()
	if not data is Dictionary:
		return objects
	var saved: Variant = (data as Dictionary).get("entries")
	if saved is Dictionary:
		for key: Variant in saved:
			if objects.entries.size() >= MAX_OBJECTS:
				break
			var entry := _entry_from(saved[key])
			if entry != null and (key is int or key is float or String(key).is_valid_int()):
				objects.entries[int(key)] = entry
	var top := 0
	for id: int in objects.entries:
		top = maxi(top, id)
	var next: Variant = (data as Dictionary).get("next_id")
	objects.next_id = maxi(top + 1, int(next) if next is int or next is float else 1)
	return objects


static func _entry_from(data: Variant) -> Entry:
	if not data is Dictionary:
		return null
	var raw: Dictionary = data
	var kind: Variant = raw.get("kind")
	if not (kind is int or kind is float) or int(kind) < 0 or int(kind) >= Kind.size():
		return null
	var entry := Entry.new()
	entry.kind = int(kind) as Kind
	entry.contents = Inventory.from_dict(raw.get("contents"))
	entry.position = _vector(raw.get("position"))
	entry.up = _vector(raw.get("up")).normalized()
	if entry.up == Vector3.ZERO:
		entry.up = Vector3.UP
	var owner: Variant = raw.get("owner")
	entry.owner = String(owner).substr(0, 64) if owner is String else ""
	var born: Variant = raw.get("born")
	entry.born = float(born) if born is int or born is float else 0.0
	var flags: Variant = raw.get("flags")
	entry.flags = (flags as Dictionary).duplicate() if flags is Dictionary else {}
	if entry.kind == Kind.DROP and entry.stack() == null:
		return null
	return entry


static func _vector(data: Variant) -> Vector3:
	if not data is Array or (data as Array).size() != 3:
		return Vector3.ZERO
	var parts: Array = data
	for part: Variant in parts:
		if not (part is int or part is float) or not is_finite(float(part)):
			return Vector3.ZERO
	return Vector3(parts[0], parts[1], parts[2])
