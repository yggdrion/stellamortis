class_name Compass
extends Control
## The compass bar (M43): a 180 degree window around the camera's bearing along the top of the
## HUD, with N, E, S, W, ticks, the bearing as a number and markers (the arrival, gates, the boss
## site) at their bearing from the player with the distance in meters. A marker outside the window
## is an arrow at the edge. Client only; nothing is computed per frame beyond a few projections.

const WIDTH := 480.0
const HEIGHT := 30.0
## Degrees across the window.
const WINDOW_DEGREES := 180.0
const PIXELS_PER_DEGREE := WIDTH / WINDOW_DEGREES
const TICK_STEP := 15
const LONG_STEP := 45
const LETTERS := {0: "N", 90: "E", 180: "S", 270: "W"}
const TEXT := Color(0.9, 0.86, 0.74, 0.95)
const TICK := Color(0.9, 0.86, 0.74, 0.55)
const ARRIVAL := MapPanel.GATE

## What the compass follows: set by GameClient.
var me: Node3D
var camera: Camera3D
var world: World

var _look := Vector3.BACK


## An angle in (-PI, PI].
static func wrap(angle: float) -> float:
	var wrapped := fposmod(angle + PI, TAU) - PI
	return PI if wrapped <= -PI else wrapped


## Signed angle (radians, positive is to the right) from the camera's bearing to a target's.
static func offset(bearing: float, target_bearing: float) -> float:
	return Compass.wrap(target_bearing - bearing)


## Bearing (radians clockwise from north) from the player's direction to a target direction.
static func bearing_to(center: Vector3, north: Vector3, target: Vector3) -> float:
	return Layout.bearing(center, north, target - center)


## Ground distance in meters between two directions of a realm.
static func distance(realm: RealmDef, from: Vector3, to: Vector3) -> float:
	return from.angle_to(to) * realm.radius


## The markers of a realm as [direction from the realm's center, color, label]. The boss site is
## greyed once the Warden has fallen. M54's pings and M56's downed allies add entries here.
static func markers(realm: RealmDef, world_seed: int, boss_fallen: bool) -> Array:
	var list := []
	list.append([realm.arrival.normalized(), ARRIVAL, "arrival"])
	for portal in Layout.portals():
		if Layout.realm_at(portal.position) != realm:
			continue
		list.append([(portal.position - realm.center).normalized(), MapPanel.GATE, portal.label])
	var site_color := MapPanel.SITE
	if boss_fallen:
		site_color = Color(0.55, 0.55, 0.55, 0.6)
	list.append([BossSite.at(realm, world_seed).direction, site_color, "boss site"])
	return list


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, HEIGHT)
	size = Vector2(WIDTH, HEIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


func _process(_delta: float) -> void:
	if not visible or me == null:
		return
	queue_redraw()


func _draw() -> void:
	if me == null or world == null:
		return
	var realm := Layout.realm_at(me.global_position)
	if realm == null:
		return
	var center := (me.global_position - realm.center).normalized()
	var north := Layout.north(realm, center)
	if camera != null:
		var ahead := -camera.global_basis.z
		var tangent := ahead - center * ahead.dot(center)
		if tangent.length_squared() > 0.0001:
			_look = tangent.normalized()
	var heading := Layout.bearing(center, north, _look)
	var font := get_theme_font("font", "Label")
	var mid := WIDTH * 0.5
	var base := HEIGHT - 1.0
	var first := int(floor(rad_to_deg(heading) - WINDOW_DEGREES * 0.5))
	first -= posmod(first, TICK_STEP)
	for degrees in range(first, first + int(WINDOW_DEGREES) + TICK_STEP * 2, TICK_STEP):
		var x := mid + (degrees - rad_to_deg(heading)) * PIXELS_PER_DEGREE
		if x < 0.0 or x > WIDTH:
			continue
		var compass_degrees := posmod(degrees, 360)
		var long := compass_degrees % LONG_STEP == 0
		if not LETTERS.has(compass_degrees):
			draw_line(Vector2(x, base), Vector2(x, base - (7.0 if long else 4.0)), TICK, 1.0)
		if LETTERS.has(compass_degrees):
			var letter: String = LETTERS[compass_degrees]
			var color := MapPanel.OWN if compass_degrees == 0 else TEXT
			draw_string(font, Vector2(x - 5.0, base - 4.0), letter, 0, -1, 15, color)
	for entry in markers(realm, world.world_seed, Encounter.flag_set(self, realm.boss_flag)):
		var direction: Vector3 = entry[0]
		var color: Color = entry[1]
		var target := bearing_to(center, north, direction)
		var turn := offset(heading, target)
		var meters := "%d m" % int(distance(realm, center, direction))
		var x := mid + turn * (WIDTH / PI)
		if absf(turn) <= PI * 0.5:
			var text: String = "%s %s" % [entry[2], meters]
			var width := font.get_string_size(text, 0, -1, 11).x
			var left := x - width * 0.5 + 5.0
			# The bearing number owns the middle of the top row: a marker there steps aside.
			if absf(x - mid) < width * 0.5 + 22.0:
				left = mid + 22.0 if x >= mid else mid - 22.0 - width
			draw_rect(Rect2(left - 9.0, 4.0, 6.0, 6.0), color, true)
			draw_string(font, Vector2(left, 12.0), text, 0, -1, 11, color)
		else:
			var side := signf(turn)
			var edge := mid + side * (mid - 6.0)
			var tip := PackedVector2Array(
				[
					Vector2(edge + side * 5.0, 8.0),
					Vector2(edge - side * 3.0, 3.0),
					Vector2(edge - side * 3.0, 13.0)
				]
			)
			draw_colored_polygon(tip, color)
	draw_string(
		font,
		Vector2(mid - 20.0, 12.0),
		"%03d" % posmod(int(round(rad_to_deg(heading))), 360),
		HORIZONTAL_ALIGNMENT_CENTER,
		40.0,
		12,
		Color.WHITE
	)
