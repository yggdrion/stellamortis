class_name LootTable
extends Resource
## What something drops when it dies or opens (M23): one `.tres` per source in res://data/loot/,
## named by EnemyDef.loot or a chest's table id. `roll` is pure and seeded, so a restart gives the
## same pile.

static var _tables := {}

## Picks made from the entries, each by weight and then by its own chance.
@export var rolls := 1
## Each: {"item": id, "weight": relative odds, "min": count, "max": count, "chance": 0 to 1 that
## the pick pays out}.
@export var entries: Array[Dictionary] = []


## The table of an id, null for "" and ids without a file.
static func by_id(id: StringName) -> LootTable:
	if id == &"":
		return null
	if not _tables.has(id):
		var path := "res://data/loot/%s.tres" % id
		_tables[id] = load(path) as LootTable if ResourceLoader.exists(path) else null
	return _tables[id]


## The stacks one drop gives: same items merge up to their stack size, unknown items are skipped.
func roll(rng: RandomNumberGenerator) -> Array[Inventory.Stack]:
	var total := 0
	for entry in entries:
		total += maxi(int(entry.get("weight", 0)), 0)
	var counts := {}
	var order: Array[StringName] = []
	for i in rolls:
		if total <= 0:
			break
		var pick := rng.randi_range(0, total - 1)
		for entry in entries:
			pick -= maxi(int(entry.get("weight", 0)), 0)
			if pick >= 0:
				continue
			var id := StringName(entry.get("item", &""))
			if Items.has(id) and rng.randf() < float(entry.get("chance", 1.0)):
				var low := int(entry.get("min", 1))
				var count := rng.randi_range(low, maxi(low, int(entry.get("max", low))))
				if not counts.has(id):
					order.append(id)
				counts[id] = counts.get(id, 0) + maxi(count, 1)
			break
	var stacks: Array[Inventory.Stack] = []
	for id in order:
		var left: int = counts[id]
		var size := Items.by_id(id).stack
		while left > 0:
			stacks.append(Inventory.Stack.new(id, mini(left, size)))
			left -= size
	return stacks
