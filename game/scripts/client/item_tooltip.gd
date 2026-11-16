class_name ItemTooltip
extends PanelContainer
## What an item is (M23): name in its rarity color, kind and slot, its stats, weight, and for a
## bag item that can be worn, the same stats against the worn item of its slot with the
## differences in green (better) and red (worse). `rows` is the data, the node only prints it.

const GOOD := Color(0.45, 0.85, 0.4)
const BAD := Color(0.9, 0.35, 0.3)
const RARITIES: Array[String] = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
const KINDS: Array[String] = [
	"Weapon", "Shield", "Crossbow", "Armor", "Trinket", "Material", "Bolts", "Consumable"
]
const SLOTS: Array[String] = [
	"", "Main hand", "Off hand", "Ranged", "Helm", "Chest", "Legs", "Cape", "Trinket", "Bolts"
]

var _text: RichTextLabel


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.043, 0.04, 0.97)
	box.border_color = Color(Menus.PARCHMENT, 0.3)
	box.set_border_width_all(1)
	box.set_content_margin_all(10)
	add_theme_stylebox_override("panel", box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_font_size_override("bold_font_size", 20)
	_text.add_theme_font_override("bold_font", Menus.title_font())
	add_child(_text)
	visible = false


## Shows `stack`, compared with `worn` (the stack in the gear cell of its slot, may be null).
func show_item(stack: Inventory.Stack, worn: Inventory.Stack, compare: bool) -> void:
	var def := Items.by_id(stack.id)
	var color := ItemDef.RARITY_COLORS[def.rarity].to_html(false)
	var text := "[b][color=#%s]%s[/color][/b]\n" % [color, def.title]
	text += "[color=#9a927f]%s %s" % [RARITIES[def.rarity], KINDS[def.kind]]
	if def.slot != ItemDef.Slot.NONE:
		text += " · %s" % SLOTS[def.slot]
	text += "[/color]\n"
	var other := Items.by_id(worn.id) if worn != null and compare else null
	for row in rows(def, other):
		text += "%s  %s" % [row["name"], row["value"]]
		if row["diff"] != "":
			text += (
				"  [color=#%s]%s[/color]"
				% [(GOOD if row["better"] else BAD).to_html(false), row["diff"]]
			)
		text += "\n"
	if stack.count > 1:
		text += (
			"[color=#9a927f]%d held, %.1f together[/color]\n"
			% [stack.count, def.weight * stack.count]
		)
	if compare:
		text += (
			"[color=#9a927f]%s[/color]"
			% ("Worn: %s" % other.title if other != null else "Nothing worn there")
		)
	_text.text = text.strip_edges()
	size = Vector2.ZERO
	visible = true


## The stat rows of an item: {name, value, diff, better}; `diff` is "" without a worn item to
## compare or when equal. Weight is last and never compared (lighter is not a goal).
static func rows(def: ItemDef, worn: ItemDef) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stats := [
		[
			"Damage",
			def.damage,
			worn.damage if worn else 0.0,
			"x%.2f",
			(
				def.damage != 1.0
				or def.kind in [ItemDef.Kind.WEAPON, ItemDef.Kind.RANGED, ItemDef.Kind.BOLT]
			)
		],
		["Defense", def.defense, worn.defense if worn else 0.0, "%.0f", def.defense > 0.0],
		["Stamina", def.stamina, worn.stamina if worn else 0.0, "%+.0f", def.stamina != 0.0],
		["Heals", def.heal, 0.0, "%.0f", def.heal > 0.0],
	]
	for stat: Array in stats:
		if not stat[4]:
			continue
		var diff := ""
		var delta: float = stat[1] - stat[2]
		var better := delta > 0.0
		if worn != null and absf(delta) > 0.001:
			diff = ("%+.2f" if stat[0] == "Damage" else "%+.0f") % delta
		result.append({"name": stat[0], "value": stat[3] % stat[1], "diff": diff, "better": better})
	result.append({"name": "Weight", "value": "%.1f" % def.weight, "diff": "", "better": false})
	return result
