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
## Outfits (Quaternius Modular Character Outfits - Fantasy): rigged without clips, imported with
## the humanoid bone map (assets/quaternius/outfits/outfit_bone_map.tres), so they play the UAL
## clips.
const OUTFITS := "res://assets/quaternius/outfits/"
const RANGER_MALE := OUTFITS + "Male_Ranger.gltf"
const RANGER_FEMALE := OUTFITS + "Female_Ranger.gltf"
const PEASANT_MALE := OUTFITS + "Male_Peasant.gltf"
const PEASANT_FEMALE := OUTFITS + "Female_Peasant.gltf"

## Base characters (Quaternius Universal Base Characters): full bodies whose head, eyes and brows
## go on an outfit, and hair rigged to the head bone. Same rig and bone map as the outfits.
const CHARACTERS := "res://assets/quaternius/characters/"
const BODY_MALE := CHARACTERS + "Superhero_Male_FullBody.gltf"
const BODY_FEMALE := CHARACTERS + "Superhero_Female_FullBody.gltf"
## Bones whose skin stays when a full body is cut down to its head.
const HEAD_BONES := [&"Head", &"Neck"]

## Borrowed clips by library path and target skeleton path, retargeted once.
static var _cache := {}
## Scene paths whose own clips were pinned in place (_pin_root); the clips are shared resources.
static var _pinned := {}
## Full body meshes cut down to the head, by body path.
static var _heads := {}

var animation: AnimationPlayer
var skeleton: Skeleton3D
## Props by name, to show and hide them.
var props := {}
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _flash_left := 0.0
var _looping: StringName = &""


## scale: model units to meters.
func _init(scene_path: String, held: Dictionary, scale_by := 1.0) -> void:
	var model := (load(scene_path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * scale_by
	model.rotation.y = PI
	add_child(model)
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		# A rig without clips (an outfit): give it a player with every UAL clip.
		animation = AnimationPlayer.new()
		animation.name = "AnimationPlayer"
		model.add_child(animation)
		animation.root_node = animation.get_path_to(model)
		animation.add_animation_library(&"", AnimationLibrary.new())
		_borrow_animations(HUMAN)
		_borrow_animations(HUMAN_EXTRA)
	else:
		animation = players[0]
	if not _pinned.has(scene_path):
		_pinned[scene_path] = true
		for clip_name in animation.get_animation_list():
			var clip := animation.get_animation(clip_name)
			for track in clip.get_track_count():
				if String(clip.track_get_path(track)).ends_with(":Root"):
					_pin_root(clip, track)
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
		# Some clips are exported without a loop flag.
		var cycle := animation.get_animation(clip)
		if cycle.loop_mode == Animation.LOOP_NONE:
			cycle.loop_mode = Animation.LOOP_LINEAR
		animation.play(clip, 0.15)
		_looping = clip
	animation.speed_scale = speed


## Puts a base character's head (its body cut to head and neck), eyes and brows on this
## model's skeleton, and pieces (hair, beard, brows: scene paths rigged to the head bone). skin
## replaces the face's color map (dark or light), null keeps it. For outfits, which ship without
## heads.
func wear_head(body_path: String, pieces: Array = [], skin_color: Texture2D = null) -> void:
	var body := (load(body_path) as PackedScene).instantiate()
	for source: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		var mesh := source.mesh
		if source.mesh.get_surface_count() > 0 and _is_body(source):
			mesh = _head_of(body_path, source)
		var part := _wear(mesh, source.skin)
		var own := mesh.surface_get_material(0) as StandardMaterial3D
		if skin_color and mesh != source.mesh and own:
			var face := own.duplicate() as StandardMaterial3D
			face.albedo_texture = skin_color
			part.set_surface_override_material(0, face)
	body.free()
	for path: String in pieces:
		var piece := (load(path) as PackedScene).instantiate()
		for source: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			_wear(source.mesh, source.skin)
		piece.free()


## Replaces a color map on every surface that uses it (a file name like T_Ranger_BaseColor.png)
## with another (an outfit's second color set).
func swap_albedo(file_name: String, texture: Texture2D) -> void:
	_each_material(
		func(material: StandardMaterial3D) -> StandardMaterial3D:
			if material.albedo_texture == null:
				return null
			if material.albedo_texture.resource_path.get_file() != file_name:
				return null
			var swapped := material.duplicate() as StandardMaterial3D
			swapped.albedo_texture = texture
			return swapped
	)


## Multiplies every surface's color (the dead's grey skin and faded clothes).
func tint(color: Color) -> void:
	_each_material(
		func(material: StandardMaterial3D) -> StandardMaterial3D:
			var tinted := material.duplicate() as StandardMaterial3D
			tinted.albedo_color = material.albedo_color * color
			return tinted
	)


## A one-shot clip shown at progress 0..1 of its length (stretched to the action's length).
## reverse plays it backwards (the Warden rising from its fall).
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


## The clips of path with tracks retargeted to skeleton (seen from root); one copy per path and
## skeleton path.
static func _borrowed(path: String, root: Node, target: Skeleton3D) -> Dictionary:
	var to := String(root.get_path_to(target))
	var key := path + "|" + to
	if _cache.has(key):
		return _cache[key]
	var source := (load(path) as PackedScene).instantiate()
	var player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var source_skeleton := source.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var from := String(player.get_node(player.root_node).get_path_to(source_skeleton))
	var clips := {}
	for clip_name in player.get_animation_list():
		var clip := player.get_animation(clip_name).duplicate() as Animation
		for track in clip.get_track_count():
			var track_path := String(clip.track_get_path(track))
			if track_path.begins_with(from + ":"):
				clip.track_set_path(track, NodePath(to + track_path.substr(from.length())))
			if track_path.ends_with(":Root"):
				_pin_root(clip, track)
		clips[clip_name] = clip
	source.free()
	_cache[key] = clips
	return clips


## Keeps a root bone position track in place sideways: some clips carry root motion (UAL2's
## Sword_Regular_A 0.9 m and Sword_Regular_C 1.7 m, UAL1's *_RM clips), which walked the model
## away from its body during the swing and snapped it back when the clip ended. The body moves
## in the sim; the model only animates in place. Height stays (a hop is fine).
static func _pin_root(clip: Animation, track: int) -> void:
	if (
		clip.track_get_type(track) != Animation.TYPE_POSITION_3D
		or clip.track_get_key_count(track) == 0
	):
		return
	var first: Vector3 = clip.track_get_key_value(track, 0)
	for key in clip.track_get_key_count(track):
		var at: Vector3 = clip.track_get_key_value(track, key)
		clip.track_set_key_value(track, key, Vector3(first.x, at.y, first.z))


## Adds a skinned mesh to this skeleton (the skin binds by bone name, so any mesh of the same rig
## fits) with the flash overlay.
func _wear(mesh: Mesh, skin_binds: Skin) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.skin = skin_binds
	# A new MeshInstance3D's skeleton path is empty (unskinned); point it at its parent.
	part.skeleton = NodePath("..")
	skeleton.add_child(part)
	part.material_overlay = _flash
	_meshes.append(part)
	return part


## Calls change on every surface's material (override or the mesh's own); a returned material
## becomes the override. Skipped headless, like skin().
func _each_material(change: Callable) -> void:
	if _headless():
		return
	for mesh in _meshes:
		for i in mesh.mesh.get_surface_count():
			var current := mesh.get_surface_override_material(i)
			if current == null:
				current = mesh.mesh.surface_get_material(i)
			var standard := current as StandardMaterial3D
			if standard == null:
				continue
			var changed: StandardMaterial3D = change.call(standard)
			if changed:
				mesh.set_surface_override_material(i, changed)


## The base character's body mesh: the one that isn't eyes or brows.
static func _is_body(source: MeshInstance3D) -> bool:
	var lower := String(source.name).to_lower()
	return not lower.contains("eye")


## The body mesh with only the triangles whose corners are mostly skinned to the head and neck
## (cached per body). The outfit covers the rest, so nothing pokes through it.
static func _head_of(body_path: String, source: MeshInstance3D) -> Mesh:
	if _heads.has(body_path):
		return _heads[body_path]
	var body := source.mesh
	var source_skeleton := source.get_node(source.skeleton) as Skeleton3D
	var keep_bones := {}
	for bind in source.skin.get_bind_count():
		var bone_name := source.skin.get_bind_name(bind)
		if bone_name == &"":
			bone_name = source_skeleton.get_bone_name(source.skin.get_bind_bone(bind))
		if bone_name in HEAD_BONES:
			keep_bones[bind] = true
	var arrays := body.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var per := bones.size() / maxi(count, 1)
	var kept := PackedByteArray()
	kept.resize(count)
	for vertex in count:
		var head := 0.0
		for k in per:
			if keep_bones.has(bones[vertex * per + k]):
				head += weights[vertex * per + k]
		kept[vertex] = 1 if head >= 0.5 else 0
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cut := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		if kept[indices[t]] and kept[indices[t + 1]] and kept[indices[t + 2]]:
			cut.append_array([indices[t], indices[t + 1], indices[t + 2]])
	arrays[Mesh.ARRAY_INDEX] = cut
	var head_mesh := ArrayMesh.new()
	var flags: int = body.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	head_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	head_mesh.surface_set_material(0, source.get_active_material(0))
	_heads[body_path] = head_mesh
	return head_mesh
