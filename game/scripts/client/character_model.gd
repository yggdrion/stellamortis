class_name CharacterModel
extends Node3D
## A rigged model (Quaternius, CC0, docs/RESOURCES.md) scaled to its body and turned to face -Z,
## with props attached to bones (held: name -> [bone, Node3D or scene path]). play_timed()
## shows an action at a given progress, so the pose always follows the rolled back state
## instead of running its own clock.

## How a held prop sits on its bone, by bone name (the rig's hand bones run along the fingers with
## X toward the thumb in the T-pose, the forearm bones along the forearm). Props are built with
## the grip at the origin and the long axis +Y: the fist turns that across the palm so the blade
## leaves past the thumb; a shield faces away from the outer forearm.
const GRIPS := {
	&"RightHand": Transform3D(Basis(Vector3.BACK, -PI / 2.0), Vector3(0.0, 0.06, 0.0)),
	&"LeftHand": Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0.0, 0.06, 0.0)),
	&"LeftLowerArm": Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.1, 0.0)),
}

## Meta on a prop held like a pistol, along the hand: the crossbow's stock goes where the fingers
## point, so it skips GRIPS.
const PISTOL_GRIP := &"pistol_grip"

## The humanoid model and the second animation library it borrows from. Both are imported with
## a humanoid bone map (assets/quaternius/ual/*_bone_map.tres), so their bones share names.
## The dissolve shader of a dying body (dissolve()).
const BURN := "res://shaders/burn_away.gdshader"
const HUMAN := "res://assets/quaternius/ual/UAL1.glb"
const HUMAN_EXTRA := "res://assets/quaternius/ual/UAL2.glb"
## The generated bodies (tools/make_bodies.py, M40), skinned to the UAL1 skeleton and imported with
## its humanoid bone map: no clips of their own, they take every UAL clip.
const BODIES := "res://assets/bodies/"
## The body's vertex colors are role indices (red channel / 255), in the order of ROLES in
## tools/make_bodies.py; skin and hair come from the look, the rest from this palette map.
const ROLES: Array[StringName] = [
	&"skin", &"hair", &"tunic", &"sleeve", &"trousers", &"boot", &"belt", &"eye", &"bone", &"rot"
]
const ROLE_COLORS := {
	&"tunic": &"cloth",
	&"sleeve": &"cloth",
	&"trousers": &"cloth_dark",
	&"boot": &"leather",
	&"belt": &"leather",
	&"eye": &"iron",
	&"bone": &"bone",
	&"rot": &"rot",
}
## Bones a mixed clip (mix()) takes from its legs clip; every other track comes from the upper one.
const LEG_BONES := [
	&"Root",
	&"Hips",
	&"LeftUpperLeg",
	&"LeftLowerLeg",
	&"LeftFoot",
	&"LeftToes",
	&"RightUpperLeg",
	&"RightLowerLeg",
	&"RightFoot",
	&"RightToes",
]

## Borrowed clips by library path and target skeleton path, retargeted once.
static var _cache := {}
## Scene paths whose own clips were pinned in place (_pin_root); the clips are shared resources.
static var _pinned := {}
## Role-colored body meshes, by body path, look and mesh name.
static var _painted := {}

var animation: AnimationPlayer
var skeleton: Skeleton3D
## Props by name, to show and hide them.
var props := {}
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _flash_left := 0.0
var _looping: StringName = &""
## While burning away: the burn material in use.
var _burn_material: ShaderMaterial


## scale: model units to meters. look: for a generated body, the palette roles of its `skin` and
## `hair` (default skin_b, hair_b) and `roles`, a dictionary from a body role (&"belt") to a palette
## role or a Color.
func _init(scene_path: String, held: Dictionary, scale_by := 1.0, look := {}) -> void:
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
	if scene_path.begins_with(BODIES) and not _headless():
		_paint(scene_path, look)
	for prop: String in held:
		var slot := BoneAttachment3D.new()
		slot.bone_name = held[prop][0]
		skeleton.add_child(slot)
		var node: Node3D = held[prop][1]
		var holder := Node3D.new()
		holder.transform = _grip(slot.bone_name, node)
		slot.add_child(holder)
		holder.add_child(node)
		props[prop] = node
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	for mesh in _meshes:
		mesh.material_overlay = _flash


static func _grip(bone: StringName, node: Node3D) -> Transform3D:
	if node.has_meta(PISTOL_GRIP):
		return Transform3D.IDENTITY
	return GRIPS.get(bone, Transform3D.IDENTITY)


## Replaces the node of a held prop (same bone, same visibility); null puts nothing there.
func set_prop(name_of: String, node: Node3D) -> void:
	var old := props[name_of] as Node3D
	var holder := old.get_parent() as Node3D
	var shown := old.visible
	holder.remove_child(old)
	old.queue_free()
	var fresh := node if node != null else Node3D.new()
	fresh.visible = shown
	holder.transform = _grip((holder.get_parent() as BoneAttachment3D).bone_name, fresh)
	holder.add_child(fresh)
	props[name_of] = fresh


## A prop from a scene file, for held.
static func prop(scene_path: String, at := Transform3D.IDENTITY) -> Node3D:
	var node := (load(scene_path) as PackedScene).instantiate() as Node3D
	node.transform = at
	return node


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


## A looping clip named name with the legs of legs_clip and the rest of the body from upper_clip,
## built once per library: UAL has no walk with a raised shield or a crossbow at the ready.
## Lasts as long as legs_clip; a shorter upper clip holds its last key.
func mix(name: StringName, legs_clip: StringName, upper_clip: StringName) -> StringName:
	var library := animation.get_animation_library(&"")
	if library.has_animation(name):
		return name
	var clip := animation.get_animation(legs_clip).duplicate() as Animation
	clip.loop_mode = Animation.LOOP_LINEAR
	for track in range(clip.get_track_count() - 1, -1, -1):
		if not LEG_BONES.has(StringName(clip.track_get_path(track).get_concatenated_subnames())):
			clip.remove_track(track)
	var upper := animation.get_animation(upper_clip)
	for track in upper.get_track_count():
		if not LEG_BONES.has(StringName(upper.track_get_path(track).get_concatenated_subnames())):
			upper.copy_track(track, clip)
	library.add_animation(name, clip)
	return name


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


## Hit stop: stops the clip where it is; the next play_timed or loop sets its speed again.
func freeze() -> void:
	animation.speed_scale = 0.0


## A short scale punch (amount: how much bigger, seconds: there and back).
func punch(amount: float, seconds: float) -> void:
	if _headless():
		return
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3.ONE * (1.0 + amount), seconds * 0.4)
	tween.tween_property(self, "scale", Vector3.ONE, seconds * 0.6)


## Burns the body away, 0 whole to 1 gone: the body's surfaces get one burn material while it runs
## (held props vanish halfway); 0 puts the plain material back. Skipped headless, like the paint.
func dissolve(amount: float) -> void:
	if _headless():
		return
	if amount <= 0.0:
		if _burn_material != null:
			for mesh in _meshes:
				for i in mesh.mesh.get_surface_count():
					mesh.set_surface_override_material(i, null)
			_burn_material = null
			for prop: Node3D in props.values():
				prop.visible = true
		return
	if _burn_material == null:
		_burn_material = MeshKit.burn_material()
		for mesh in _meshes:
			for i in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(i, _burn_material)
	_burn_material.set_shader_parameter("burn_amount", amount)
	for prop: Node3D in props.values():
		prop.visible = amount < 0.5


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


## Path of a generated body by id (&"male_a").
static func body_path(id: StringName) -> String:
	return BODIES + String(id) + ".glb"


## Swaps every body mesh for one whose vertex colors are palette colors (the role indices
## resolved), with the flat shader; cached per body, look and mesh.
func _paint(scene_path: String, look: Dictionary) -> void:
	var palette := Palette.of(Gear.REALM)
	var key := "%s|%s" % [scene_path, look]
	for mesh in _meshes:
		var at := "%s|%s" % [key, mesh.name]
		if not _painted.has(at):
			_painted[at] = _resolve(mesh.mesh, look, palette)
		mesh.mesh = _painted[at]


## A copy of a body mesh with role indices replaced by palette colors (alpha: roughness).
static func _resolve(source: ArrayMesh, look: Dictionary, palette: Palette) -> ArrayMesh:
	var colors: Array[Color] = []
	var overrides: Dictionary = look.get("roles", {})
	for role in ROLES:
		var choice: Variant = overrides.get(role, null)
		if choice == null:
			choice = look.get(
				role, ROLE_COLORS.get(role, &"skin_b" if role == &"skin" else &"hair_b")
			)
		if choice is Color:
			var color := choice as Color
			colors.append(Color(color.r, color.g, color.b, 0.8))
		else:
			colors.append(palette.color(choice as StringName))
	var painted := ArrayMesh.new()
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for i in vertex_colors.size():
			vertex_colors[i] = colors[clampi(
				roundi(vertex_colors[i].r * 255.0), 0, colors.size() - 1
			)]
		arrays[Mesh.ARRAY_COLOR] = vertex_colors
		var flags: int = source.surface_get_format(surface) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		painted.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		painted.surface_set_name(surface, source.surface_get_name(surface))
		painted.surface_set_material(surface, MeshKit.material())
	return painted
