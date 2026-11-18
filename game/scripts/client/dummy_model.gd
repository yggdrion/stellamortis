class_name DummyModel
extends Node3D
## A training dummy as a static generated mesh: what EnemyView poses in place of a CharacterModel
## for a dummy. Hit feedback is a tint (`flash`, `glow`) and a sway around the foot; a fall tips
## it over away from its front.

const SWAY_TIME := 0.35
const FALL_ANGLE := PI / 2.0 - 0.1

## Whether `fall` has tipped it over (so the caller stands it up again).
var fallen := false
var _flash: StandardMaterial3D
var _flash_left := 0.0
var _mesh: MeshInstance3D


func _init(variant_seed: int) -> void:
	_mesh = Gear.make(&"training_dummy", {}, variant_seed) as MeshInstance3D
	_flash = StandardMaterial3D.new()
	_flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.albedo_color = Color(1, 1, 1, 0)
	_mesh.material_overlay = _flash
	# The kind faces +Z; an enemy faces -Z (like CharacterModel).
	_mesh.rotation.y = PI
	add_child(_mesh)


## Tints the whole dummy for a moment (hit, parry).
func flash(color: Color, seconds: float) -> void:
	_flash.albedo_color = color
	_flash_left = seconds


## A steady tint (telegraph); a running flash() wins.
func glow(color: Color) -> void:
	if _flash_left > 0.0:
		return
	_flash.albedo_color = color


## A hit: the dummy rocks back and forth around its foot, by `amount` radians, away along `away`
## (a direction in the model's own frame, so it rocks along the blow).
func sway(amount: float, away: Vector3) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var axis := Vector3.UP.cross(away).normalized()
	var tween := create_tween()
	tween.tween_property(self, "basis", Basis(axis, amount), SWAY_TIME * 0.3)
	tween.tween_property(self, "basis", Basis(axis, -amount * 0.4), SWAY_TIME * 0.4)
	tween.tween_property(self, "basis", Basis.IDENTITY, SWAY_TIME * 0.3)


## The fall, 0 standing to 1 on its back (no tween: derived from the enemy's state each frame).
func fall(progress: float) -> void:
	fallen = progress > 0.0
	var eased := 1.0 - pow(1.0 - clampf(progress, 0.0, 1.0), 2.0)
	basis = Basis(Vector3.RIGHT, FALL_ANGLE * eased)


func _process(delta: float) -> void:
	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.albedo_color.a = 0.0


## Upright again after a fall.
func stand() -> void:
	fallen = false
	basis = Basis.IDENTITY
