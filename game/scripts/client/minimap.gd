class_name Minimap
extends Control
## The minimap (M43): a round, north-up view of the realm around the own player, in a corner of
## the HUD. The terrain is the map shader (the big map's, with `circle` on) fed by uniforms only,
## from the one height image MapPanel.texture_for builds per realm and seed; only the markers are
## drawn here. Markers past the rim stick to it. Client only.

## Meters of ground across the circle (the server wakes camps within Spawner.WAKE 90 m).
const SPAN := 200.0
## Pixels across.
const SIZE := 180.0
const RING := Color(0.85, 0.78, 0.6, 0.9)
const ENEMY_RADIUS := 3.5

## What the minimap follows: set by GameClient.
var me: Node3D
var camera: Camera3D
var world: World
## True while the big map is open (set by GameClient).
var map_open := false

var _realm: RealmDef
var _center := Vector3.UP
var _north := Vector3.BACK
var _look := Vector3.BACK
var _shader: ShaderMaterial
var _view: ColorRect


## Whether the minimap shows: not under the big map, only with the setting on, only in a realm.
static func shows(map_open_now: bool, setting: bool, in_realm: bool) -> bool:
	return setting and in_realm and not map_open_now


## Pixels per projection unit that put SPAN meters of ground across SIZE pixels.
static func zoom_for(radius: float) -> float:
	return SIZE * 0.5 * (TAU * radius) / SPAN


func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	# Behind the markers of _draw (children draw after their parent otherwise).
	_view = ColorRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.show_behind_parent = true
	_view.size = Vector2(SIZE, SIZE)
	_shader = ShaderMaterial.new()
	_shader.shader = load("res://shaders/map.gdshader") as Shader
	_shader.set_shader_parameter("circle", true)
	_shader.set_shader_parameter("view_size", Vector2(SIZE, SIZE))
	_shader.set_shader_parameter("image_size", Vector2(MapPanel.IMAGE_SIZE))
	_view.material = _shader
	add_child(_view)


func _process(_delta: float) -> void:
	_realm = Layout.realm_at(me.global_position) if me != null else null
	visible = shows(map_open, Settings.minimap, _realm != null)
	if not visible or world == null:
		return
	_center = (me.global_position - _realm.center).normalized()
	_north = Layout.north(_realm, _center)
	if camera != null:
		var ahead := -camera.global_basis.z
		var tangent := ahead - _center * ahead.dot(_center)
		if tangent.length_squared() > 0.0001:
			_look = tangent.normalized()
	_shader.set_shader_parameter("center_dir", _center)
	_shader.set_shader_parameter("forward_dir", _north)
	_shader.set_shader_parameter("right_dir", _north.cross(_center))
	_shader.set_shader_parameter("zoom", zoom_for(_realm.radius))
	_shader.set_shader_parameter("realm_radius", _realm.radius)
	var texture := MapPanel.texture_for(_realm, world.world_seed)
	_shader.set_shader_parameter("ready", texture != null)
	if texture != null:
		_shader.set_shader_parameter("heights", texture)
	queue_redraw()


## Where a world point is on the control, stuck to the rim when it is beyond it.
func _screen(point: Vector3) -> Vector2:
	var direction := (point - _realm.center).normalized()
	var offset := MapPanel.project(_center, _north, direction, zoom_for(_realm.radius))
	var limit := SIZE * 0.5 - 4.0
	if offset.length() > limit:
		offset = offset.normalized() * limit
	return size * 0.5 + offset


func _draw() -> void:
	if world == null or _realm == null:
		return
	var middle := size * 0.5
	draw_arc(middle, SIZE * 0.5 - 1.0, 0.0, TAU, 64, RING, 2.0)
	var font := get_theme_font("font", "Label")
	for portal in Layout.portals():
		if Layout.realm_at(portal.position) != _realm:
			continue
		var g := _screen(portal.position)
		draw_rect(Rect2(g - Vector2(4, 4), Vector2(8, 8)), MapPanel.GATE, false, 2.0)
	var site := BossSite.at(_realm, world.world_seed)
	var fallen := Encounter.flag_set(self, _realm.boss_flag)
	var site_color := MapPanel.SITE * Color(1, 1, 1, 0.45 if fallen else 1.0)
	draw_arc(_screen(site.center()), 5.0, 0.0, TAU, 16, site_color, 2.0)
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.action == Enemy.Action.HIDDEN:
			continue
		if Layout.realm_at(enemy.global_position) != _realm:
			continue
		var id: StringName = Combat.ENEMY_KINDS[enemy.kind]
		var p := _screen(enemy.global_position)
		draw_circle(p, ENEMY_RADIUS, MapPanel.KIND_COLORS.get(id, Color.WHITE))
		draw_arc(p, ENEMY_RADIUS, 0.0, TAU, 10, Color.BLACK, 1.0)
	for node in world.players.get_children():
		var player := node as SimPlayer
		if player == null or player == me or Layout.realm_at(player.global_position) != _realm:
			continue
		draw_circle(_screen(player.global_position), 4.0, MapPanel.FRIEND)
	var turn := Layout.bearing(_center, _north, _look)
	var tip := PackedVector2Array(
		[
			middle + Vector2(0, -8).rotated(turn),
			middle + Vector2(5, 6).rotated(turn),
			middle + Vector2(-5, 6).rotated(turn)
		]
	)
	draw_colored_polygon(tip, MapPanel.OWN)
	# Last, so a marker stuck to the rim never hides it.
	draw_string(font, Vector2(middle.x - 5.0, 15.0), "N", 0, -1, 13, MapPanel.OWN)
