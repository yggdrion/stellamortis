class_name MapPanel
extends Control
## The map (M33), a debug tool: the realm the own player stands on, seen from above in an
## azimuthal equidistant projection centered on the player and turned so the camera looks up.
## The terrain is an equirectangular height image built once per realm and seed on worker
## threads and drawn by a shader (inverse projection per pixel); markers are drawn on top through
## the forward projection. Client only: everything shown is a pure function of the realm and the
## world seed, or a node of the World.

const IMAGE_SIZE := Vector2i(1024, 512)
## The view is this many meters across at the most zoomed in; the full realm at the other end.
const MIN_SPAN := 150.0
const ZOOM_STEP := 1.25
const KIND_COLORS := {
	&"dummy": Color(0.7, 0.7, 0.7),
	&"swordsman": Color(0.85, 0.3, 0.2),
	&"archer": Color(0.9, 0.7, 0.2),
	&"warden": Color(0.75, 0.25, 0.85),
}
const GATE := Color(0.45, 0.8, 0.95)
const FRIEND := Color(0.6, 0.9, 0.6)
const OWN := Color.WHITE
const HOVER_RADIUS := 10.0
const RING_WAKE := Color(0.95, 0.85, 0.3, 0.8)
const RING_SLEEP := Color(0.4, 0.7, 0.95, 0.6)

## Image textures per "realm id:seed", and the Jobs still running.
static var _textures := {}
static var _jobs := {}

## What the panel follows: set by GameClient.
var me: SimPlayer
var camera: Camera3D
var world: World
## Meters across the view.
var span := 600.0
## Cleared camps, camp id -> seconds left, as the server last said (host or --debug-map only).
var cleared := {}

var _realm: RealmDef
var _key := ""
var _center := Vector3.UP
var _forward := Vector3.FORWARD
var _spawns: Array[Spawner.SpawnPoint] = []
## Camps: [direction, member count, camp id]; roamers are camps of one.
var _camps: Array = []
var _shader: ShaderMaterial
var _view: ColorRect
## Markers drawn this frame: [screen position, details].
var _hits: Array = []
var _mouse := Vector2(-1000.0, -1000.0)


## One realm's height image being built on the WorkerThreadPool, a task per image row.
class Job:
	extends RefCounted
	var realm: RealmDef
	var world_seed := 0
	var size := Vector2i.ONE
	var rows: Array[PackedFloat32Array] = []
	var group := -1

	func start() -> void:
		rows.resize(size.y)
		group = WorkerThreadPool.add_group_task(_row, size.y)

	func _row(y: int) -> void:
		rows[y] = MapPanel.height_row(realm, world_seed, y, size)

	func finished() -> bool:
		return WorkerThreadPool.is_group_task_completed(group)

	func image() -> Image:
		WorkerThreadPool.wait_for_group_task_completion(group)
		return MapPanel.rows_to_image(rows, size)


## The azimuthal equidistant projection of the unit direction d around `center` with `heading`
## (a unit tangent at center: it points up on the map), in `zoom` pixels per unit where the
## antipode is at distance 1. The antipode is one point mapping to the whole rim: it is put at
## the top.
static func project(center: Vector3, heading: Vector3, d: Vector3, zoom: float) -> Vector2:
	var angle := center.angle_to(d)
	var tangent := d - center * center.dot(d)
	if tangent.length_squared() < 0.0000001:
		return Vector2(0.0, -zoom) if angle > 1.0 else Vector2.ZERO
	tangent = tangent.normalized()
	var right := heading.cross(center)
	return Vector2(tangent.dot(right), -tangent.dot(heading)) * (angle / PI) * zoom


## The inverse of project(); a point beyond the rim is clamped to it.
static func unproject(center: Vector3, heading: Vector3, p: Vector2, zoom: float) -> Vector3:
	var m := p / zoom
	var distance := minf(m.length(), 1.0)
	if distance < 0.0000001:
		return center
	var angle := distance * PI
	var right := heading.cross(center)
	var tangent := (right * m.x - heading * m.y).normalized()
	return (center * cos(angle) + tangent * sin(angle)).normalized()


## The unit direction of equirectangular image pixel (x, y); the shader reads it back the same
## way.
static func image_direction(x: int, y: int, size: Vector2i) -> Vector3:
	var lon := ((x + 0.5) / size.x - 0.5) * TAU
	var lat := (0.5 - (y + 0.5) / size.y) * PI
	return Vector3(sin(lon) * cos(lat), sin(lat), cos(lon) * cos(lat))


static func height_row(
	realm: RealmDef, world_seed: int, y: int, size: Vector2i
) -> PackedFloat32Array:
	var field := Terrain.Field.new(realm, world_seed)
	var row := PackedFloat32Array()
	row.resize(size.x)
	for x in size.x:
		row[x] = field.height(image_direction(x, y, size))
	return row


static func rows_to_image(rows: Array[PackedFloat32Array], size: Vector2i) -> Image:
	var data := PackedFloat32Array()
	for row in rows:
		data.append_array(row)
	return Image.create_from_data(size.x, size.y, false, Image.FORMAT_RF, data.to_byte_array())


## The height image (meters, FORMAT_RF) of a realm under a seed, built here on this thread.
static func terrain_image(realm: RealmDef, world_seed: int, size := IMAGE_SIZE) -> Image:
	var rows: Array[PackedFloat32Array] = []
	for y in size.y:
		rows.append(height_row(realm, world_seed, y, size))
	return rows_to_image(rows, size)


func _ready() -> void:
	theme = Menus.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	# Both draw behind the markers of _draw (children draw after their parent otherwise).
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.show_behind_parent = true
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_view = ColorRect.new()
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.show_behind_parent = true
	_shader = ShaderMaterial.new()
	_shader.shader = load("res://shaders/map.gdshader") as Shader
	_view.material = _shader
	add_child(_view)


func _process(_delta: float) -> void:
	if not visible:
		return
	_realm = Layout.realm_at(me.global_position) if me != null else null
	if _realm != null:
		_follow()
	_view.visible = _realm != null
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	var button := event as InputEventMouseButton
	if motion:
		_mouse = motion.position
	elif button and button.pressed and _realm != null:
		var factor := 0.0
		if button.button_index == MOUSE_BUTTON_WHEEL_UP:
			factor = 1.0 / ZOOM_STEP
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			factor = ZOOM_STEP
		if factor > 0.0:
			span = clampf(span * factor, MIN_SPAN, _full_span())
		accept_event()


## The square the map fills.
func _frame() -> Rect2:
	var side := minf(size.x, size.y) * 0.9
	return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))


func _full_span() -> float:
	return TAU * _realm.radius if _realm != null else MIN_SPAN


## Pixels per projection unit: the view's side is `span` meters of arc, the rim is PI * radius.
func _zoom() -> float:
	return _frame().size.x * 0.5 * (TAU * _realm.radius) / minf(span, _full_span())


func _follow() -> void:
	var key := "%s:%d" % [_realm.id, world.world_seed]
	if key != _key:
		_key = key
		_spawns = Spawner.points(_realm, world.world_seed)
		_group_camps()
		_request_image(key)
	_center = (me.global_position - _realm.center).normalized()
	if camera != null:
		var ahead := -camera.global_basis.z
		var tangent := ahead - _center * ahead.dot(_center)
		if tangent.length_squared() > 0.0001:
			_forward = tangent.normalized()
	_forward = (_forward - _center * _forward.dot(_center)).normalized()
	var frame := _frame()
	_view.position = frame.position
	_view.size = frame.size
	_shader.set_shader_parameter("center_dir", _center)
	_shader.set_shader_parameter("forward_dir", _forward)
	_shader.set_shader_parameter("right_dir", _forward.cross(_center))
	_shader.set_shader_parameter("zoom", _zoom())
	_shader.set_shader_parameter("view_size", frame.size)
	_shader.set_shader_parameter("realm_radius", _realm.radius)
	_shader.set_shader_parameter("image_size", Vector2(IMAGE_SIZE))
	var job: Job = _jobs.get(key)
	if job != null and job.finished():
		_textures[key] = ImageTexture.create_from_image(job.image())
		_jobs.erase(key)
	var texture: Texture2D = _textures.get(key)
	_shader.set_shader_parameter("ready", texture != null)
	if texture != null:
		_shader.set_shader_parameter("heights", texture)


func _request_image(key: String) -> void:
	if _textures.has(key) or _jobs.has(key):
		return
	var job := Job.new()
	job.realm = _realm
	job.world_seed = world.world_seed
	job.size = IMAGE_SIZE
	job.start()
	_jobs[key] = job


func _group_camps() -> void:
	var grouped := {}
	for point in _spawns:
		if not grouped.has(point.camp):
			grouped[point.camp] = []
		grouped[point.camp].append(point)
	_camps.clear()
	for camp: int in grouped:
		var sum := Vector3.ZERO
		for point: Spawner.SpawnPoint in grouped[camp]:
			sum += point.up
		_camps.append([sum.normalized(), grouped[camp].size(), camp])


## Where a world point is on screen.
func _screen(point: Vector3) -> Vector2:
	var direction := (point - _realm.center).normalized()
	return _frame().get_center() + project(_center, _forward, direction, _zoom())


func _draw() -> void:
	var font := get_theme_font("font", "Label")
	var frame := _frame()
	if _realm == null:
		var text := "No map here"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28).x
		draw_string(font, (size - Vector2(width, -20.0)) * 0.5, text, 0, -1, 28, Menus.PARCHMENT)
		return
	draw_rect(frame, Menus.PARCHMENT * Color(1, 1, 1, 0.5), false, 2.0)
	_hits.clear()
	_draw_camps(font)
	_draw_gates(font)
	_draw_enemies()
	_draw_players()
	_draw_rings()
	_draw_legend(font)
	_draw_hover(font)


## The realm id the panel shows, "" when none (the client asks the server about its camps).
func realm_id() -> String:
	return str(_realm.id) if _realm != null else ""


func _inside(p: Vector2) -> bool:
	return _frame().grow(-4.0).has_point(p)


func _draw_camps(font: Font) -> void:
	var meters := _zoom() / (PI * _realm.radius)
	var color := Menus.PARCHMENT * Color(1, 1, 1, 0.8)
	for camp: Array in _camps:
		var p := _frame().get_center() + project(_center, _forward, camp[0], _zoom())
		if not _inside(p):
			continue
		var count: int = camp[1]
		if cleared.has(camp[2]):
			var left := ceili(cleared[camp[2]])
			var dim := color * Color(1, 1, 1, 0.5)
			draw_arc(p, 8.0, 0.0, TAU, 16, dim, 1.5)
			draw_line(p + Vector2(-5, -5), p + Vector2(5, 5), dim, 1.5)
			draw_line(p + Vector2(-5, 5), p + Vector2(5, -5), dim, 1.5)
			_hits.append([p, "camp %d, cleared, %d s left" % [camp[2], left]])
		elif count == 1:
			draw_circle(p, 3.0, color)
			_hits.append([p, "roamer, camp %d" % camp[2]])
		else:
			var radius := maxf(5.0 + count, Spawner.CAMP_RADIUS * meters)
			draw_arc(p, radius, 0.0, TAU, 24, color, 1.5)
			draw_string(font, p + Vector2(-4, 5), str(count), 0, -1, 14, color)
			_hits.append([p, "camp %d, %d enemies" % [camp[2], count]])


func _draw_gates(font: Font) -> void:
	for portal in Layout.portals():
		if Layout.realm_at(portal.position) != _realm:
			continue
		var p := _screen(portal.position)
		if not _inside(p):
			continue
		draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), GATE, false, 2.0)
		draw_string(font, p + Vector2(9, 5), portal.label, 0, -1, 15, GATE)
		_hits.append([p, "gate %s" % portal.label])


func _draw_enemies() -> void:
	for node in get_tree().get_nodes_in_group(Enemy.GROUP):
		var enemy := node as Enemy
		if enemy == null or enemy.action == Enemy.Action.HIDDEN:
			continue
		if Layout.realm_at(enemy.global_position) != _realm:
			continue
		var p := _screen(enemy.global_position)
		if not _inside(p):
			continue
		var id: StringName = Combat.ENEMY_KINDS[enemy.kind]
		draw_circle(p, 4.5, KIND_COLORS.get(id, Color.WHITE))
		draw_arc(p, 4.5, 0.0, TAU, 12, Color.BLACK, 1.0)
		var action := str(Enemy.Action.keys()[enemy.action]).to_lower()
		_hits.append([p, "%s, slot %d, %s, camp %s" % [id, enemy.index, action, _camp(enemy)]])


func _draw_players() -> void:
	for node in world.players.get_children():
		var player := node as SimPlayer
		if player == null or Layout.realm_at(player.global_position) != _realm:
			continue
		var p := _screen(player.global_position)
		if not _inside(p):
			continue
		if player == me:
			var tip := PackedVector2Array(
				[p + Vector2(0, -9), p + Vector2(6, 7), p + Vector2(-6, 7)]
			)
			draw_colored_polygon(tip, OWN)
		else:
			draw_circle(p, 5.0, FRIEND)
		_hits.append([p, "player %s" % player.player_name])


## Debug: the distances the server wakes (WAKE) and frees (SLEEP) camps at, around every player.
func _draw_rings() -> void:
	var meters := _zoom() / (PI * _realm.radius)
	for node in world.players.get_children():
		var player := node as SimPlayer
		if player == null or Layout.realm_at(player.global_position) != _realm:
			continue
		var p := _screen(player.global_position)
		# Distances are along the ground; a circle is exact only at the map's center.
		draw_arc(p, Spawner.WAKE * meters, 0.0, TAU, 48, RING_WAKE, 1.5)
		draw_arc(p, Spawner.SLEEP * meters, 0.0, TAU, 48, RING_SLEEP, 1.5)


func _draw_legend(font: Font) -> void:
	var at := _frame().position + Vector2(14, 22)
	draw_string(font, at, "%d m across" % roundi(minf(span, _full_span())), 0, -1, 16, OWN)
	var rows := [[OWN, "you"], [FRIEND, "player"], [GATE, "gate"]]
	for id: StringName in KIND_COLORS:
		rows.append([KIND_COLORS[id], str(id)])
	rows.append([Menus.PARCHMENT, "camp (ring), roamer (dot)"])
	rows.append([RING_WAKE, "wake range"])
	rows.append([RING_SLEEP, "sleep range"])
	for row: Array in rows:
		at.y += 20.0
		draw_circle(at + Vector2(5, -5), 5.0, row[0])
		draw_string(font, at + Vector2(16, 0), row[1], 0, -1, 15, Menus.PARCHMENT)


func _draw_hover(font: Font) -> void:
	var best := HOVER_RADIUS
	var text := ""
	for hit: Array in _hits:
		var distance := _mouse.distance_to(hit[0])
		if distance < best:
			best = distance
			text = "%s, %d m" % [hit[1], roundi(_distance_to(hit[0]))]
	if text == "":
		return
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
	var box := Rect2(_mouse + Vector2(14, 14), Vector2(width + 12, 26))
	draw_rect(box, Color(0.04, 0.035, 0.03, 0.92))
	draw_rect(box, Menus.PARCHMENT * Color(1, 1, 1, 0.3), false)
	draw_string(font, box.position + Vector2(6, 19), text, 0, -1, 16, Menus.PARCHMENT)


## Meters along the ground from the own player to a screen point.
func _distance_to(p: Vector2) -> float:
	var direction := unproject(_center, _forward, p - _frame().get_center(), _zoom())
	return _center.angle_to(direction) * _realm.radius


## The camp of the spawn point nearest to the enemy, "-" when none is near (it may have walked).
func _camp(enemy: Enemy) -> String:
	var best := Spawner.CAMP_RADIUS * 4.0
	var found := "-"
	for point in _spawns:
		var distance := point.position.distance_to(enemy.global_position)
		if distance < best:
			best = distance
			found = str(point.camp)
	return found
