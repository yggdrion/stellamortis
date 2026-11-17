class_name ItemSlot
extends Control
## One inventory cell (M23): a dark square with a rarity rim, the item's glyph, its count, a star
## for junk and, when empty, a faint caption (gear slots). No item art exists yet, so the glyph is
## drawn from the item's kind and slot in the rarity color. The panel's cells take drag and drop
## and clicks; the hotbar's are only shown (panel null).

const SIZE := 54.0
const BACK := Color(0.055, 0.047, 0.042, 0.95)
const RIM := Color(0.86, 0.8, 0.68, 0.2)
const CURSOR := Color(0.95, 0.88, 0.7, 0.9)
const HELD := Color(0.9, 0.55, 0.25, 0.95)
const JUNK := Color(0.85, 0.7, 0.25)

var cell := -1
var panel: InventoryPanel
var stack: Inventory.Stack
## Faint caption of an empty cell ("HELM").
var caption := ""
## A key shown in the corner (the hotbar).
var key_hint := ""
var junk := false
var cursor := false
var held := false


func _init() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_stack(value: Inventory.Stack, is_junk := false) -> void:
	stack = value
	junk = is_junk
	queue_redraw()


func mark(is_cursor: bool, is_held: bool) -> void:
	if cursor != is_cursor or held != is_held:
		cursor = is_cursor
		held = is_held
		queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, BACK)
	var def := Items.by_id(stack.id) if stack else null
	var color := RIM
	if def != null:
		color = ItemDef.RARITY_COLORS[def.rarity]
		draw_rect(rect.grow(-1.0), Color(color, 0.07))
		draw_rect(rect, Color(color, 0.55), false, 1.0)
		var icon := ItemIcons.texture(def.id)
		if icon != null:
			draw_texture_rect(icon, rect.grow(-3.0), false, Color(1, 1, 1, 0.45 if junk else 1.0))
		else:
			draw_glyph(
				self,
				def,
				rect.grow(-9.0),
				color.lightened(0.1) if not junk else color.darkened(0.35)
			)
		if stack.count > 1:
			var font := Menus.title_font()
			var text := str(stack.count)
			var at := Vector2(size.x - 5.0 - font.get_string_size(text, 0, -1, 13).x, size.y - 5.0)
			draw_string_outline(font, at, text, 0, -1, 13, 4, Color(0, 0, 0, 0.9))
			draw_string(font, at, text, 0, -1, 13, Menus.PARCHMENT)
		if junk:
			var star := PackedVector2Array()
			for i in 10:
				var radius := 6.0 if i % 2 == 0 else 2.6
				star.append(Vector2(11.0, 11.0) + Vector2.from_angle(-PI / 2 + i * PI / 5) * radius)
			draw_colored_polygon(star, JUNK)
	else:
		draw_rect(rect, RIM, false, 1.0)
		if caption != "":
			var font := Menus.title_font()
			var wide := font.get_string_size(caption, 0, -1, 10).x
			var at := Vector2((size.x - wide) / 2.0, size.y / 2.0 + 4.0)
			draw_string(font, at, caption, 0, -1, 10, Color(Menus.PARCHMENT, 0.22))
	if key_hint != "":
		draw_string(
			Menus.title_font(), Vector2(4.0, 13.0), key_hint, 0, -1, 11, Color(Menus.PARCHMENT, 0.7)
		)
	if held:
		draw_rect(rect, HELD, false, 2.0)
	elif cursor:
		draw_rect(rect, CURSOR, false, 2.0)


func _gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if panel == null or button == null or not button.pressed:
		return
	if (
		button.button_index == MOUSE_BUTTON_RIGHT
		or (button.button_index == MOUSE_BUTTON_LEFT and button.shift_pressed)
	):
		panel.activate(cell)
	elif button.button_index == MOUSE_BUTTON_LEFT and button.ctrl_pressed:
		panel.split_half(cell)


func _get_drag_data(_at: Vector2) -> Variant:
	if panel == null or stack == null:
		return null
	var preview := ItemSlot.new()
	preview.show_stack(stack)
	preview.modulate.a = 0.85
	var holder := Control.new()
	holder.add_child(preview)
	preview.position = -preview.custom_minimum_size / 2.0
	set_drag_preview(holder)
	return {"cell": cell}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return panel != null and data is Dictionary and panel.can_move(data.get("cell", -1), cell)


func _drop_data(_at: Vector2, data: Variant) -> void:
	panel.move(data["cell"], cell)


## The item's picture, drawn into `rect` with lines and polygons in `color`.
static func draw_glyph(canvas: CanvasItem, def: ItemDef, rect: Rect2, color: Color) -> void:
	var c := rect.get_center()
	var u := minf(rect.size.x, rect.size.y) / 2.0
	var p := func(x: float, y: float) -> Vector2: return c + Vector2(x, y) * u
	var w := 2.0
	match def.kind:
		ItemDef.Kind.WEAPON:
			if String(def.id).begins_with("axe"):
				canvas.draw_line(p.call(-0.6, 0.9), p.call(0.5, -0.8), color, w)
				canvas.draw_colored_polygon(
					PackedVector2Array(
						[
							p.call(0.2, -0.9),
							p.call(0.95, -0.55),
							p.call(0.8, 0.1),
							p.call(0.35, -0.3)
						]
					),
					color
				)
			else:
				canvas.draw_line(p.call(-0.7, 0.7), p.call(0.75, -0.75), color, w + 1.0)
				canvas.draw_line(p.call(-0.55, 0.15), p.call(-0.15, 0.55), color, w)
				canvas.draw_line(p.call(-0.9, 0.9), p.call(-0.6, 0.6), color, w + 1.0)
		ItemDef.Kind.SHIELD:
			(
				canvas
				. draw_colored_polygon(
					PackedVector2Array(
						[
							p.call(-0.75, -0.8),
							p.call(0.75, -0.8),
							p.call(0.75, 0.0),
							p.call(0.0, 0.95),
							p.call(-0.75, 0.0),
						]
					),
					Color(color, 0.35)
				)
			)
			(
				canvas
				. draw_polyline(
					PackedVector2Array(
						[
							p.call(-0.75, -0.8),
							p.call(0.75, -0.8),
							p.call(0.75, 0.0),
							p.call(0.0, 0.95),
							p.call(-0.75, 0.0),
							p.call(-0.75, -0.8),
						]
					),
					color,
					w
				)
			)
			canvas.draw_line(p.call(0.0, -0.8), p.call(0.0, 0.8), color, 1.0)
		ItemDef.Kind.RANGED:
			canvas.draw_arc(p.call(0.0, 0.5), u * 1.0, PI * 1.15, PI * 1.85, 16, color, w)
			canvas.draw_line(p.call(-0.9, -0.15), p.call(0.9, -0.15), color, 1.0)
			canvas.draw_line(p.call(0.0, -0.15), p.call(0.0, 0.9), color, w + 1.0)
		ItemDef.Kind.ARMOR:
			_armor(canvas, def.slot, p, u, color, w)
		ItemDef.Kind.TRINKET:
			canvas.draw_arc(p.call(0.0, 0.2), u * 0.55, 0.0, TAU, 20, color, w)
			canvas.draw_colored_polygon(
				PackedVector2Array(
					[
						p.call(0.0, -0.9),
						p.call(0.28, -0.55),
						p.call(0.0, -0.3),
						p.call(-0.28, -0.55)
					]
				),
				color
			)
		ItemDef.Kind.BOLT:
			for x: float in [-0.5, 0.0, 0.5]:
				canvas.draw_line(p.call(x - 0.2, 0.85), p.call(x + 0.2, -0.6), color, 1.5)
				canvas.draw_colored_polygon(
					PackedVector2Array(
						[p.call(x + 0.2, -0.95), p.call(x + 0.38, -0.5), p.call(x + 0.02, -0.5)]
					),
					color
				)
		ItemDef.Kind.CONSUMABLE:
			canvas.draw_rect(Rect2(p.call(-0.85, -0.45), Vector2(1.7, 0.9) * u), Color(color, 0.3))
			canvas.draw_rect(Rect2(p.call(-0.85, -0.45), Vector2(1.7, 0.9) * u), color, false, w)
			canvas.draw_line(p.call(0.0, -0.3), p.call(0.0, 0.3), color, w)
			canvas.draw_line(p.call(-0.3, 0.0), p.call(0.3, 0.0), color, w)
		_:
			var shard := PackedVector2Array(
				[
					p.call(-0.1, -0.9),
					p.call(0.75, -0.2),
					p.call(0.5, 0.75),
					p.call(-0.5, 0.85),
					p.call(-0.85, 0.0),
				]
			)
			canvas.draw_colored_polygon(shard, Color(color, 0.35))
			shard.append(shard[0])
			canvas.draw_polyline(shard, color, w)


static func _armor(
	canvas: CanvasItem, slot: int, p: Callable, u: float, color: Color, w: float
) -> void:
	match slot:
		ItemDef.Slot.HELM:
			canvas.draw_arc(p.call(0.0, 0.1), u * 0.85, PI, TAU, 16, color, w)
			canvas.draw_line(p.call(-0.85, 0.1), p.call(-0.85, 0.8), color, w)
			canvas.draw_line(p.call(0.85, 0.1), p.call(0.85, 0.8), color, w)
			canvas.draw_line(p.call(-0.85, 0.8), p.call(0.85, 0.8), color, w)
			canvas.draw_line(p.call(0.0, 0.1), p.call(0.0, 0.8), color, 1.0)
		ItemDef.Slot.LEGS:
			canvas.draw_line(p.call(-0.8, -0.9), p.call(0.8, -0.9), color, w + 1.0)
			canvas.draw_line(p.call(-0.45, -0.9), p.call(-0.55, 0.9), color, w + 1.0)
			canvas.draw_line(p.call(0.45, -0.9), p.call(0.55, 0.9), color, w + 1.0)
		ItemDef.Slot.CAPE:
			canvas.draw_colored_polygon(
				PackedVector2Array(
					[p.call(-0.5, -0.9), p.call(0.5, -0.9), p.call(0.9, 0.9), p.call(-0.9, 0.9)]
				),
				Color(color, 0.35)
			)
			canvas.draw_line(p.call(-0.5, -0.9), p.call(-0.9, 0.9), color, w)
			canvas.draw_line(p.call(0.5, -0.9), p.call(0.9, 0.9), color, w)
		_:
			var tunic := PackedVector2Array(
				[
					p.call(-0.4, -0.9),
					p.call(-0.95, -0.5),
					p.call(-0.7, -0.1),
					p.call(-0.5, -0.25),
					p.call(-0.5, 0.9),
					p.call(0.5, 0.9),
					p.call(0.5, -0.25),
					p.call(0.7, -0.1),
					p.call(0.95, -0.5),
					p.call(0.4, -0.9),
					p.call(0.0, -0.6),
				]
			)
			canvas.draw_colored_polygon(tunic, Color(color, 0.3))
			tunic.append(tunic[0])
			canvas.draw_polyline(tunic, color, w)
