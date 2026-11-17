extends GdUnitTestSuite
## Generated gear (M39): every item look builds inside its triangle budget, the same item gives
## the same mesh, and a weapon's model does not reach past its attack.

const WEAPON_LOOKS: Array[StringName] = [&"sword", &"greatsword", &"axe", &"crossbow"]
const ARMOR_LOOKS: Array[StringName] = [
	&"helm", &"horns", &"crown", &"cape", &"pauldrons", &"cuirass", &"greaves"
]
const SHIELD_LOOKS: Array[StringName] = [&"round_shield", &"kite_shield", &"tower_shield"]


func _items_with_look() -> Array[ItemDef]:
	var out: Array[ItemDef] = []
	for id in Items.IDS:
		var def := Items.by_id(id)
		if def != null and def.look != &"":
			out.append(def)
	return out


func test_every_item_look_is_registered_and_inside_its_budget() -> void:
	var palette := Palette.of("barrowlands")
	var items := _items_with_look()
	assert_int(items.size()).is_greater(0)
	for def in items:
		assert_bool(Generators.ids().has(String(def.look))).is_true()
		var kind := Generators.budget_kind(String(def.look))
		var built := Generators.arrays(String(def.look), 1, palette, def.look_params)
		var limit := Budgets.data().limit(kind, Budgets.FULL)
		assert_int(MeshKit.triangles(built[Budgets.FULL])).is_between(1, limit)
		var half := Budgets.data().limit(kind, Budgets.HALF)
		assert_int(MeshKit.triangles(built[Budgets.HALF])).is_between(1, half)


func test_the_same_item_builds_the_same_mesh() -> void:
	var palette := Palette.of("barrowlands")
	for look in WEAPON_LOOKS + SHIELD_LOOKS:
		var a := Generators.arrays(String(look), 3, palette)[0] as Array
		var b := Generators.arrays(String(look), 3, palette)[0] as Array
		assert_bool(a[Mesh.ARRAY_VERTEX] == b[Mesh.ARRAY_VERTEX]).is_true()
		assert_bool(a[Mesh.ARRAY_COLOR] == b[Mesh.ARRAY_COLOR]).is_true()


func test_params_change_the_look_and_wear_darkens_it() -> void:
	var palette := Palette.of("barrowlands")
	var plain := Generators.arrays("sword", 1, palette)[0] as Array
	var long := Generators.arrays("sword", 1, palette, {"length": 1.0})[0] as Array
	assert_float(Generators.bounds(long).size.y).is_greater(Generators.bounds(plain).size.y)
	var worn := Generators.arrays("sword", 1, palette, {"wear": 0.9})[0] as Array
	var fresh := (plain[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	var rotten := (worn[Mesh.ARRAY_COLOR] as PackedColorArray)[0]
	assert_float(rotten.v).is_less(fresh.v)


## A blade does not suggest more reach than the swing has: tip to grip stays under the attack's
## reach (which is measured from the player's center, so this is a loose bound).
func test_a_weapon_is_not_longer_than_its_attack_reaches() -> void:
	var reach := 99.0
	for id in Combat.PLAYER_ATTACKS:
		reach = minf(reach, Combat.attack(id).reach)
	for def in _items_with_look():
		if def.kind != ItemDef.Kind.WEAPON:
			continue
		var length := 0.0
		match def.look:
			&"sword":
				length = SwordKind.total(def.look_params)
			&"greatsword":
				length = GreatswordKind.total(def.look_params)
			&"axe":
				length = AxeKind.total(def.look_params)
		assert_float(length).is_between(0.3, reach)
	assert_float(GreatswordKind.total({})).is_between(1.2, 1.6)


func test_gear_make_hangs_a_shield_from_the_forearm() -> void:
	var shield: Node3D = auto_free(Gear.make(&"round_shield"))
	assert_bool(shield is MeshInstance3D).is_false()
	assert_float(shield.rotation.y).is_equal_approx(PI / 2.0, 0.001)
	var sword: Node3D = auto_free(Gear.make(&"sword"))
	assert_bool(sword is MeshInstance3D).is_true()


func test_every_armor_look_stays_in_budget_at_every_level() -> void:
	var palette := Palette.of("barrowlands")
	for look in ARMOR_LOOKS:
		var kind := Generators.budget_kind(String(look))
		for variant in 4:
			var built := Generators.arrays(String(look), variant, palette)
			for lod in 2:
				var limit := Budgets.data().limit(kind, lod)
				assert_int(MeshKit.triangles(built[lod])).is_between(1, limit)


## Mirrored pieces are symmetric about X (wear and dents are not, and are not checked).
func test_mirrored_armor_is_symmetric() -> void:
	var palette := Palette.of("barrowlands")
	for look in [&"pauldrons", &"horns", &"helm", &"cuirass", &"cape"]:
		var box := Generators.bounds(Generators.arrays(String(look), 2, palette)[0])
		assert_float(box.position.x + box.end.x).is_equal_approx(0.0, 0.01)


func test_armor_names_the_body_parts_it_covers() -> void:
	assert_array(GearKit.covers(&"helm", {})).contains_exactly([&"Head"])
	assert_array(GearKit.covers(&"cuirass", {})).contains([&"UpperChest"])
	assert_array(GearKit.covers(&"greaves", {"side": "Right"})).contains_exactly([&"RightLowerLeg"])
	assert_array(GearKit.covers(&"cuirass", {"covers": ["Spine"]})).contains_exactly([&"Spine"])
	assert_array(GearKit.covers(&"cape", {})).is_empty()
	for def in _items_with_look():
		if def.kind == ItemDef.Kind.ARMOR:
			assert_array(GearKit.covers(def.look, def.look_params)).is_not_empty()
