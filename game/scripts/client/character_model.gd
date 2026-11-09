class_name CharacterModel
extends Node3D
## A KayKit character (CC0, docs/RESOURCES.md) scaled to our 1.8 m bodies and turned to face -Z,
## with props in its hand slots. play_timed() shows an action at a given progress, so the pose
## always follows the rolled back state instead of running its own clock.

const SCALE := 0.85

var animation: AnimationPlayer
var skeleton: Skeleton3D
var _meshes: Array[MeshInstance3D] = []
var _flash: StandardMaterial3D
var _flash_left := 0.0
var _looping: StringName = &""


func _init(scene_path: String, props: Dictionary) -> void:
	var model := (load(scene_path) as PackedScene).instantiate() as Node3D
	model.scale = Vector3.ONE * SCALE
	model.rotation.y = PI
	add_child(model)
	animation = model.find_children("*", "AnimationPlayer", true, false)[0]
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	for node in model.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(node)
	for bone: String in props:
		var slot := BoneAttachment3D.new()
		slot.bone_name = bone
		skeleton.add_child(slot)
		slot.add_child((load(props[bone]) as PackedScene).instantiate())
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	for mesh in _meshes:
		mesh.material_overlay = _flash


## A looping animation (idle, walk, run), blended in when it changes.
func loop(clip: StringName, speed := 1.0) -> void:
	if _looping != clip:
		animation.play(clip, 0.15)
		_looping = clip
	animation.speed_scale = speed


## A one-shot clip shown at progress 0..1 of its length (stretched to the action's length).
func play_timed(clip: StringName, progress: float, length_seconds: float) -> void:
	var clip_length := animation.get_animation(clip).length
	if animation.current_animation != clip or _looping != &"":
		animation.play(clip, 0.08)
		_looping = &""
	animation.speed_scale = clip_length / maxf(length_seconds, 0.01)
	var expected := clampf(progress, 0.0, 0.999) * clip_length
	if absf(animation.current_animation_position - expected) > 0.08:
		animation.seek(expected, true)


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
