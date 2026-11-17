class_name Budgets
extends Resource
## The numbers of docs/STYLE.md as data (M36): triangle budgets per kind and level of detail
## (full, half, far; -1 = not drawn), the level of detail distances and the color variation
## `MeshKit.paint` applies. Loaded from data/style/budgets.tres by `Budgets.data()`.

const PATH := "res://data/style/budgets.tres"
const FULL := 0
const HALF := 1
const FAR := 2

static var _data: Budgets
static var _lock := Mutex.new()

## kind id -> Vector3i(full, half, far) triangles.
@export var kinds: Dictionary = {}
## Full detail up to this distance in meters, half up to `half_distance`, far beyond.
@export var full_distance := 40.0
@export var half_distance := 120.0
## Per instance: value +-fraction and hue +-degrees. Per face: value +-fraction. Darkening
## toward the ground or into creases: up to this fraction.
@export var instance_value := 0.06
@export var instance_hue := 3.0
@export var face_value := 0.04
@export var down_darken := 0.25


static func data() -> Budgets:
	_lock.lock()
	if _data == null:
		_data = load(PATH) as Budgets
	_lock.unlock()
	return _data


## Triangle limit of a kind at a level (FULL, HALF, FAR); -1 when it is not drawn there.
func limit(kind: String, lod: int) -> int:
	assert(kinds.has(kind), "unknown kind " + kind)
	return (kinds[kind] as Vector3i)[lod]
