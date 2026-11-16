class_name Items
extends RefCounted
## The item kinds by index, like Combat.ENEMY_KINDS: the index is what travels in rolled back
## state (SimPlayer.main_hand and friends), 0 is "none". APPEND ONLY: a reorder changes the wire
## meaning, which is a protocol bump. The id is the file name in res://data/items/.

const IDS: Array[StringName] = [
	&"",
	&"sword",
	&"axe_bronze",
	&"sword_runed",
	&"shield_wood",
	&"shield_iron",
	&"crossbow",
	&"crossbow_ash",
	&"helm_leather",
	&"chest_chain",
	&"legs_barrow",
	&"ring_ember",
	&"charm_bone",
	&"bolt",
	&"hide",
	&"iron_scrap",
	&"bone",
	&"ember",
	&"bandage",
]

static var _defs := {}


static func has(id: StringName) -> bool:
	return id != &"" and IDS.has(id)


## The definition of an id, null for "" and ids that are not in IDS.
static func by_id(id: StringName) -> ItemDef:
	if not has(id):
		return null
	if not _defs.has(id):
		_defs[id] = load("res://data/items/%s.tres" % id) as ItemDef
	return _defs[id]


## The index of an id in IDS, 0 (none) for unknown ones.
static func index(id: StringName) -> int:
	return maxi(0, IDS.find(id))


## The definition behind an index, null for 0 and out of range.
static func def(item_index: int) -> ItemDef:
	if item_index <= 0 or item_index >= IDS.size():
		return null
	return by_id(IDS[item_index])
