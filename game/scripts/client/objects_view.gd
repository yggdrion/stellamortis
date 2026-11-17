class_name ObjectsView
extends Node
## What the client draws of the world objects (M23, WorldObjects): one node per drop or chest,
## made from the server's RPC deltas (Net.object_added and friends) under the realm place the
## object stands in, so Arena.show_place hides what is in another place. Drops burst out of the
## kill on an arc, land with a bounce and a thud, then bob and turn, glow in their rarity's color
## (the one place color is spent: white, green, blue, purple, gold), and from blue up stand under
## a light beam. Materials are pulled toward a player close by (the server takes them at 1.2 m).
## The object the own player could take is the one `focus_id` names (nearest within REACH, the
## prompt says what E does). The server decides everything; nothing here changes state.

## The own player's prompt and E reach (m); the server's is a little longer (Looting).
const REACH := 2.5
const PULL_REACH := 3.0
const AUTO_REACH := 1.2
## Seconds an arc takes, its height (m), the bounce on landing (m, seconds).
const ARC_TIME := 0.55
const ARC_HEIGHT := 1.5
const BOUNCE := 0.16
const BOUNCE_TIME := 0.3
## How high a resting item floats and how much it bobs (m), turn speed (rad/s).
const HOVER := 0.4
const BOB := 0.07
const SPIN := 0.9
## Longest side (m) a model is fitted to, lying and standing.
const MODEL_SIZE := 1.0
const CHEST_SCALE := 1.25
## Beams start at this rarity.
const BEAM_RARITY := 2
const BEAM_HEIGHT := 7.0
const ITEM_SOLID := {
	&"hide": Color(0.5, 0.33, 0.2),
	&"iron_scrap": Color(0.55, 0.57, 0.62),
	&"bone": Color(0.88, 0.85, 0.74),
	&"ember": Color(1.0, 0.45, 0.12),
	&"bandage": Color(0.86, 0.82, 0.72),
	&"bolt": Color(0.6, 0.5, 0.38),
}
const KIND_SOLID := {
	ItemDef.Kind.ARMOR: Color(0.5, 0.52, 0.56),
	ItemDef.Kind.TRINKET: Color(0.82, 0.72, 0.4),
}
const BEAM_SHADER := preload("res://shaders/loot_beam.gdshader")
const CHEST_MODEL := "res://assets/quaternius/props/Chest_Wood.gltf"

static var _ring_texture: GradientTexture2D
static var _materials := {}

## The own player, to pull items and pick the one in reach.
var me: SimPlayer
var world: World
## What the HUD shows for the object in reach, "" for none, and which one E acts on.
var prompt := ""
var prompt_color := Color.WHITE
var focus_id := -1
var focus_is_chest := false

var _nodes := {}
var _focus_node: Lying


func _process(_delta: float) -> void:
	_pick_focus()


## Where the objects the own player could take lie (bots walk to them).
func spots() -> Array[Vector3]:
	var found: Array[Vector3] = []
	for id: int in _nodes:
		var node: Lying = _nodes[id]
		if node.usable():
			found.append(node.rest)
	return found


## The server's whole list, once after joining: everything is already there, nothing animates.
func snapshot(all: Dictionary) -> void:
	for id: int in _nodes.keys():
		_forget(id)
	for id: int in all:
		_spawn(id, all[id])


## A new object; one that came with an arc ("from") bursts out, else it is just there.
func add(id: int, data: Dictionary) -> void:
	_spawn(id, data)


func update(id: int, data: Dictionary) -> void:
	var node := _nodes.get(id) as Lying
	if node is ChestLook:
		(node as ChestLook).set_opened(data.get("flags", {}).get("opened", false), true)
	elif node is Drop:
		(node as Drop).set_count(int(data.get("count", 1)))


## An object is gone: taken by `by` (it flies into that player) or expired (it shrinks away).
func remove(id: int, by: int) -> void:
	var node := _nodes.get(id) as Lying
	_nodes.erase(id)
	if node == null:
		return
	if node == _focus_node:
		_focus_node = null
		focus_id = -1
	var taker := world.player(by) if by != 0 and world != null else null
	if node is Drop:
		(node as Drop).leave(taker)
	else:
		node.queue_free()


func _forget(id: int) -> void:
	var node := _nodes.get(id) as Lying
	_nodes.erase(id)
	if node != null:
		node.queue_free()
	_focus_node = null if node == _focus_node else _focus_node


func _spawn(id: int, data: Dictionary) -> void:
	if _nodes.has(id):
		return
	var pos: Vector3 = data.get("pos", Vector3.ZERO)
	var up: Vector3 = data.get("up", Vector3.UP)
	var node: Lying = null
	match int(data.get("kind", -1)):
		WorldObjects.Kind.DROP:
			var def := Items.by_id(StringName(data.get("item", "")))
			if def != null:
				var from: Variant = data.get("from")
				var drop := Drop.new(def, int(data.get("count", 1)), pos, up, from)
				drop.view = self
				node = drop
		WorldObjects.Kind.CHEST:
			var flags: Dictionary = data.get("flags", {})
			node = ChestLook.new(pos, up, float(flags.get("yaw", 0.0)), flags.get("opened", false))
	if node == null:
		return
	_nodes[id] = node
	_parent_for(pos).add_child(node)


## The node of the realm place a point is in (hidden with it), else the arena itself.
func _parent_for(point: Vector3) -> Node3D:
	var arena := world.arena
	var place := Layout.place_at(point)
	return arena.places[place] if arena.places.has(place) else arena


## The nearest object within REACH of the own player becomes the one E acts on.
func _pick_focus() -> void:
	var best: Lying = null
	var best_id := -1
	if me != null and me.action != SimPlayer.Action.DEAD:
		var best_distance := REACH
		for id: int in _nodes:
			var node: Lying = _nodes[id]
			var distance := me.global_position.distance_to(node.rest)
			if distance < best_distance and node.usable():
				best_distance = distance
				best = node
				best_id = id
	if best != _focus_node:
		if _focus_node != null and is_instance_valid(_focus_node):
			_focus_node.set_focus(false)
		if best != null:
			best.set_focus(true)
		_focus_node = best
	focus_id = best_id
	focus_is_chest = best is ChestLook
	prompt = best.prompt() if best != null else ""
	prompt_color = best.color() if best != null else Color.WHITE


# --- Shared pieces --------------------------------------------------------------------------


## A flat soft disc of light on the ground (a radial gradient, additive).
static func _ring(color: Color, size: float) -> MeshInstance3D:
	if _ring_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 0.9))
		gradient.set_color(1, Color(1, 1, 1, 0.0))
		_ring_texture = GradientTexture2D.new()
		_ring_texture.gradient = gradient
		_ring_texture.fill = GradientTexture2D.FILL_RADIAL
		_ring_texture.fill_from = Vector2(0.5, 0.5)
		_ring_texture.fill_to = Vector2(0.5, 0.0)
		_ring_texture.width = 64
		_ring_texture.height = 64
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.orientation = PlaneMesh.FACE_Y
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	paint.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	paint.albedo_texture = _ring_texture
	paint.albedo_color = Color(color, 0.4)
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.disable_fog = true
	quad.material = paint
	var disc := MeshInstance3D.new()
	disc.mesh = quad
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = 0.04
	return disc


## A column of light of a color, its base at the node's origin.
static func _beam(color: Color, strength: float) -> MeshInstance3D:
	var column := CylinderMesh.new()
	column.top_radius = 0.16
	column.bottom_radius = 0.26
	column.height = BEAM_HEIGHT
	column.radial_segments = 12
	column.rings = 1
	column.cap_top = false
	column.cap_bottom = false
	var paint := ShaderMaterial.new()
	paint.shader = BEAM_SHADER
	paint.set_shader_parameter("tint", color)
	paint.set_shader_parameter("strength", strength)
	paint.set_shader_parameter("beam_height", BEAM_HEIGHT)
	column.material = paint
	var beam := MeshInstance3D.new()
	beam.mesh = column
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.position.y = BEAM_HEIGHT * 0.5
	return beam


static func _light(color: Color, energy: float) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 4.0
	light.shadow_enabled = false
	light.position.y = 0.6
	return light


static func _solid(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var paint := StandardMaterial3D.new()
		paint.albedo_color = color
		paint.roughness = 0.6
		paint.emission_enabled = true
		paint.emission = color
		paint.emission_energy_multiplier = 0.25
		_materials[key] = paint
	return _materials[key]


## The union of the meshes' boxes under a node, in the node's space.
static func _bounds(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var relative := root.global_transform.affine_inverse() * mesh.global_transform
		var part := relative * mesh.get_aabb()
		box = part if first else box.merge(part)
		first = false
	return box


## What lies in the world and may be in reach: Drop and ChestLook.
class Lying:
	extends Node3D

	## Where it lies (world), and the up there.
	var rest := Vector3.ZERO
	var up := Vector3.UP
	var focused := false

	## Whether E may act on it now.
	func usable() -> bool:
		return false

	func color() -> Color:
		return Color.WHITE

	func prompt() -> String:
		return ""

	func set_focus(on: bool) -> void:
		focused = on


## One resting or flying item: a model (or a faceted stone for what has none), a glow on the
## ground, a light and a beam by rarity.
class Drop:
	extends Lying

	var def: ItemDef
	var count := 1
	## The view that holds it (it knows the own player).
	var view: ObjectsView
	var _item := Node3D.new()
	var _glow: MeshInstance3D
	var _beam: MeshInstance3D
	var _light: OmniLight3D
	var _from: Variant
	var _age := 0.0
	var _landed := false
	var _leaving := false
	var _phase := randf() * TAU
	var _forward := Vector3.FORWARD
	var _material := false

	func _init(item: ItemDef, amount: int, at: Vector3, normal: Vector3, from: Variant) -> void:
		def = item
		count = amount
		rest = at
		up = normal
		_from = from
		_material = item.kind == ItemDef.Kind.MATERIAL
		name = "Drop_%s" % item.id

	func _ready() -> void:
		var color := ItemDef.RARITY_COLORS[def.rarity]
		_forward = SimPlayer._tangent(Vector3.FORWARD, up)
		_forward = _forward.rotated(up, _phase)
		global_transform = Transform3D(SimPlayer.frame(up, _forward), rest)
		add_child(_item)
		_build_item()
		_glow = ObjectsView._ring(color, 1.6 if def.rarity > 0 else 1.1)
		add_child(_glow)
		if def.rarity > 0:
			_light = ObjectsView._light(color, 0.4 + 0.35 * def.rarity)
			add_child(_light)
		if def.rarity >= BEAM_RARITY:
			_beam = ObjectsView._beam(color, 0.5 + 0.12 * def.rarity)
			add_child(_beam)
		_landed = not _from is Vector3
		if _from is Vector3:
			_glow.visible = false
			if _beam:
				_beam.visible = false
			if _light:
				_light.visible = false

	func usable() -> bool:
		return not _leaving and _landed

	func color() -> Color:
		return ItemDef.RARITY_COLORS[def.rarity]

	func prompt() -> String:
		return "E   %s%s" % [def.title, "  x%d" % count if count > 1 else ""]

	func set_count(amount: int) -> void:
		count = amount

	## Taken: flies into the player (or shrinks away when nobody took it) and frees itself.
	func leave(taker: Node3D) -> void:
		_leaving = true
		_glow.visible = false
		if _beam:
			_beam.visible = false
		if _light:
			_light.visible = false
		var tween := create_tween()
		if taker != null and is_instance_valid(taker):
			var start := global_position
			tween.tween_method(
				func(t: float) -> void:
					if is_instance_valid(taker):
						global_position = start.lerp(taker.global_position + up * 0.9, t * t)
						scale = Vector3.ONE * (1.0 - 0.7 * t),
				0.0,
				1.0,
				0.22
			)
			Sounds.play(taker, &"loot_pickup", -4.0, 1.2)
		else:
			tween.tween_property(self, "scale", Vector3.ONE * 0.01, 0.4)
		tween.tween_callback(queue_free)

	func _process(delta: float) -> void:
		_age += delta
		_item.rotation.y += delta * (SPIN * 4.0 if _age < ARC_TIME else SPIN)
		if _leaving:
			return
		var at := rest
		var lift := HOVER
		if _from is Vector3 and _age < ARC_TIME:
			var s := _age / ARC_TIME
			var offset: Vector3 = (_from as Vector3) - rest
			var height := offset.dot(up)
			at += (offset - up * height) * (1.0 - s)
			at += up * (height * (1.0 - s) + ARC_HEIGHT * 4.0 * s * (1.0 - s))
			lift = 0.0
		else:
			if not _landed:
				_land()
			var b := clampf((_age - ARC_TIME) / BOUNCE_TIME, 0.0, 1.0)
			if _from is Vector3 and b < 1.0:
				at += up * BOUNCE * 4.0 * b * (1.0 - b)
			lift += BOB * sin(_age * 2.0 + _phase)
			at = _pulled(at)
		global_position = at
		_item.position = Vector3(0.0, lift, 0.0)
		var want := 1.3 if focused else 1.0
		_item.scale = _item.scale.lerp(Vector3.ONE * want, minf(delta * 10.0, 1.0))
		if _glow.visible:
			_glow.scale = _glow.scale.lerp(Vector3.ONE * (1.25 if focused else 1.0), delta * 10.0)

	## Landing: the glow, light and beam come on, with a thud and a few glints.
	func _land() -> void:
		_landed = true
		_glow.visible = true
		if _beam:
			_beam.visible = true
		if _light:
			_light.visible = true
		Sounds.play(self, &"loot_drop", -2.0, 1.3 - 0.1 * def.rarity)
		HitEffects.burst(self, rest + up * 0.15, up, HitEffects.Kind.GLINT)

	## Materials lean toward a player close by (the server takes them at AUTO_REACH).
	func _pulled(at: Vector3) -> Vector3:
		var player := view.me if view != null else null
		if not _material or player == null or player.action == SimPlayer.Action.DEAD:
			return at
		var distance := player.global_position.distance_to(rest)
		if distance > PULL_REACH:
			return at
		var pull := clampf((PULL_REACH - distance) / (PULL_REACH - AUTO_REACH), 0.0, 1.0)
		return at.lerp(player.global_position + up * 0.6, pull * pull * 0.85)

	func _build_item() -> void:
		var model := def.model
		if model != "" and ResourceLoader.exists(model):
			var node := (load(model) as PackedScene).instantiate() as Node3D
			_item.add_child(node)
			# Lies on its side (swords and axes) or stands a little tilted (shields).
			if def.kind == ItemDef.Kind.SHIELD:
				node.rotation.x = deg_to_rad(-20.0)
			else:
				node.rotation.x = deg_to_rad(-90.0)
			var box := ObjectsView._bounds(_item)
			var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
			if longest > 0.0:
				node.scale = Vector3.ONE * (MODEL_SIZE / longest)
			var centered := ObjectsView._bounds(_item)
			node.position = -(centered.position + centered.size * 0.5)
			return
		var stone := SphereMesh.new()
		stone.radius = 0.2
		stone.height = 0.38
		stone.radial_segments = 6
		stone.rings = 3
		var color: Color = ITEM_SOLID.get(def.id, KIND_SOLID.get(def.kind, Color(0.7, 0.7, 0.7)))
		stone.material = ObjectsView._solid(color)
		var mesh := MeshInstance3D.new()
		mesh.mesh = stone
		_item.add_child(mesh)


## The elite's chest: Chest_Wood with its own open and close clips, a gold light and beam while
## it is shut.
class ChestLook:
	extends Lying

	var opened := false
	var _yaw := 0.0
	var _player: AnimationPlayer
	var _beam: MeshInstance3D
	var _light: OmniLight3D

	func _init(at: Vector3, normal: Vector3, yaw: float, is_open: bool) -> void:
		rest = at
		up = normal
		_yaw = yaw
		opened = is_open
		name = "Chest"

	func _ready() -> void:
		var forward := SimPlayer._tangent(Vector3.FORWARD, up).rotated(up, _yaw)
		global_transform = Transform3D(SimPlayer.frame(up, forward), rest)
		var model := (load(CHEST_MODEL) as PackedScene).instantiate() as Node3D
		model.scale = Vector3.ONE * CHEST_SCALE
		add_child(model)
		_player = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var gold := ItemDef.RARITY_COLORS[4]
		add_child(ObjectsView._ring(gold, 2.6))
		_light = ObjectsView._light(gold, 0.9)
		add_child(_light)
		_beam = ObjectsView._beam(gold, 0.55)
		add_child(_beam)
		set_opened(opened, false)

	func usable() -> bool:
		return not opened

	func color() -> Color:
		return ItemDef.RARITY_COLORS[4]

	func prompt() -> String:
		return "E   Open the chest"

	## Shows the chest shut or open; `animate` plays the opening with its sound and a burst.
	func set_opened(is_open: bool, animate: bool) -> void:
		opened = is_open
		if _beam:
			_beam.visible = not is_open
		if _light:
			_light.visible = not is_open
		if _player == null:
			return
		var clip := ("Chest_Open" if animate else "Chest_Opened") if is_open else "Chest_Closed"
		if _player.has_animation(clip):
			_player.play(clip)
		if animate and is_open:
			Sounds.play(self, &"chest_open", 0.0, 1.0)
			HitEffects.burst(self, rest + up * 0.8, up, HitEffects.Kind.EMBERS)
