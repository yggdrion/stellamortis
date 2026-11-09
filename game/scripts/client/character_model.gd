class_name CharacterModel
extends Node3D
## A rigged model (Quaternius, CC0, docs/RESOURCES.md) scaled to its body and turned to face -Z,
## with props attached to bones (held: name -> [bone, Node3D or scene path]). play_timed()
## shows an action at a given progress, so the pose always follows the rolled back state
## instead of running its own clock.

## The humanoid model and the second animation library it borrows from. Both are imported with
## a humanoid bone map (assets/quaternius/ual/*_bone_map.tres), so their bones share names.
const HUMAN := "res://assets/quaternius/ual/UAL1.glb"
const HUMAN_EXTRA := "res://assets/quaternius/ual/UAL2.glb"

## Borrowed clips by library path, retargeted once (every humanoid shares the skeleton path).
static var _cache := {}

var animation: AnimationPlayer
var skeleton: Skeleton3D
## Props by name, to show and hide them.
var props := {}
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _flash_left := 0.0
var _looping: StringName = &""


## scale: model units to meters; lift: raises the model (hovering drones).
func _init(scene_path: String, held: Dictionary, scale_by := 1.0, lift := 0.0) -> void:
	var model := (load(scene_path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * scale_by
	model.rotation.y = PI
	model.position.y = lift
	add_child(model)
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	if scene_path == HUMAN:
		_borrow_animations(HUMAN_EXTRA)
	for node in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node)
	for prop: String in held:
		var slot := BoneAttachment3D.new()
		slot.bone_name = held[prop][0]
		skeleton.add_child(slot)
		var node: Node3D = held[prop][1]
		slot.add_child(node)
		props[prop] = node
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	for mesh in _meshes:
		mesh.material_overlay = _flash


## Raises the model above its body's feet (a drone's hover height).
func lift(height: float) -> void:
	(get_child(0) as Node3D).position.y = height


## A prop from a scene file, for held.
static func prop(scene_path: String, at := Transform3D.IDENTITY) -> Node3D:
	var node := (load(scene_path) as PackedScene).instantiate() as Node3D
	node.transform = at
	return node


## Replaces the materials of every surface; per_surface[i] wins for surface i if given.
func skin(material: Material, per_surface := {}) -> void:
	if _headless():
		return
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i, per_surface.get(i, material))


## Adds an emission map to the model's own materials (the packs ship them unused).
func light_up(texture: Texture2D, energy: float) -> void:
	if _headless():
		return
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			var source := mesh.mesh.surface_get_material(i) as StandardMaterial3D
			if source == null:
				continue
			var material := source.duplicate() as StandardMaterial3D
			material.emission_enabled = true
			material.emission_texture = texture
			material.emission = Color.WHITE
			material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
			material.emission_energy_multiplier = energy
			mesh.set_surface_override_material(i, material)


## A looping animation (idle, walk, run), blended in when it changes.
func loop(clip: StringName, speed := 1.0) -> void:
	if _looping != clip:
		# The robot packs export their cycles without a loop flag.
		var cycle := animation.get_animation(clip)
		if cycle.loop_mode == Animation.LOOP_NONE:
			cycle.loop_mode = Animation.LOOP_LINEAR
		animation.play(clip, 0.15)
		_looping = clip
	animation.speed_scale = speed


## A one-shot clip shown at progress 0..1 of its length (stretched to the action's length).
## reverse plays it backwards (a robot powering up from its power-down clip).
func play_timed(clip: StringName, progress: float, length_seconds: float, reverse := false) -> void:
	var clip_length := animation.get_animation(clip).length
	if animation.current_animation != clip or _looping != &"":
		animation.play(clip, 0.08)
		_looping = &""
	var at := clampf(progress, 0.0, 0.999)
	if reverse:
		at = 0.999 - at
	animation.speed_scale = (-1.0 if reverse else 1.0) * clip_length / maxf(length_seconds, 0.01)
	var expected := at * clip_length
	if absf(animation.current_animation_position - expected) > 0.08:
		animation.seek(expected, true)


func show_prop(name_of: String, shown: bool) -> void:
	(props[name_of] as Node3D).visible = shown


## Tints the whole body for a moment (hit, parry, telegraph).
func flash(color: Color, seconds: float) -> void:
	_flash.albedo_color = color
	_flash_left = seconds


## A steady tint (telegraph); a running flash() wins.
func glow(color: Color) -> void:
	if _flash_left > 0.0:
		return
	_flash.albedo_color = color
	_flash_left = 0.0


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.albedo_color.a = 0.0


## Headless bots draw nothing; the dummy renderer logs an error for every surface override.
static func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


## Copies the clips of another library on the same bone names into ours, pointing their tracks
## at our skeleton. Cached per path, since every humanoid needs them.
func _borrow_animations(path: String) -> void:
	var library := animation.get_animation_library(&"")
	var clips := _borrowed(path, animation.get_node(animation.root_node), skeleton)
	for clip_name: StringName in clips:
		if not library.has_animation(clip_name):
			library.add_animation(clip_name, clips[clip_name])


## The clips of path with tracks retargeted to skeleton (seen from root); one copy per path.
static func _borrowed(path: String, root: Node, target: Skeleton3D) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var source := (load(path) as PackedScene).instantiate()
	var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var from := String(player.get_node(player.root_node).get_path_to(source_skeleton))
	var to := String(root.get_path_to(target))
	var clips := {}
	for clip_name in player.get_animation_list():
		var clip := player.get_animation(clip_name).duplicate() as Animation
		for track in clip.get_track_count():
			var track_path := String(clip.track_get_path(track))
			if track_path.begins_with(from + ":"):
				clip.track_set_path(track, NodePath(to + track_path.substr(from.length())))
		clips[clip_name] = clip
	source.free()
	_cache[path] = clips
	return clips
