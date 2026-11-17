class_name ItemIcons
extends Node
## Item icons (M39): each item with a `look` is rendered once, from its own generated mesh, in a
## small SubViewport at a fixed angle and light, and cached by item id. `warm` starts the queue at
## load (one icon every few frames, so nothing hitches); `texture` returns the icon, or null while
## it is not ready, for items without a look and in headless runs (the slot draws its glyph then).

const SIZE := 96
## Frames between two icons.
const GAP := 3
const REALM := "barrowlands"

static var _cache := {}
static var _host: ItemIcons

var _view: SubViewport
var _pivot: Node3D
var _camera: Camera3D


## Starts rendering every icon. Once; does nothing headless.
static func warm(parent: Node) -> void:
	if _host != null or DisplayServer.get_name() == "headless":
		return
	_host = ItemIcons.new()
	_host.name = "ItemIcons"
	parent.add_child(_host)


static func texture(id: StringName) -> Texture2D:
	return _cache.get(id)


func _ready() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(SIZE, SIZE)
	_view.transparent_bg = true
	_view.own_world_3d = true
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.position = Vector3(0, 0, 4)
	_view.add_child(_camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 35.0, 0.0)
	sun.light_energy = 1.4
	_view.add_child(sun)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.ambient_light_energy = 0.9
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_view.add_child(world_env)
	_pivot = Node3D.new()
	_view.add_child(_pivot)
	_render_all()


func _render_all() -> void:
	for id in Items.IDS:
		var def := Items.by_id(id)
		if def == null or def.look == &"" or _cache.has(id):
			continue
		for i in GAP:
			await get_tree().process_frame
		await _render(def)


func _render(def: ItemDef) -> void:
	var mesh := Generators.build(String(def.look), 1, Palette.of(REALM), def.look_params)[0]
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var box := mesh.get_aabb()
	# Hand gear is long along Y: lay it on the diagonal; shields and armor show a three quarter view.
	var hand := box.size.y > box.size.x * 1.8 and box.size.y > box.size.z * 1.8
	node.position = -(box.position + box.size * 0.5)
	_pivot.add_child(node)
	_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(-45.0)) if hand else Vector3(0.2, -0.6, 0.0)
	_camera.size = maxf(box.size.x, maxf(box.size.y, box.size.z)) * (0.85 if hand else 1.3)
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	_cache[def.id] = ImageTexture.create_from_image(_view.get_texture().get_image())
	node.queue_free()
