class_name Palette
extends Resource
## One realm's colors by role (docs/STYLE.md section 3), client only. A generator never holds a
## color literal: it asks `Palette.of(realm).color(&"bark")`. The sim never loads a palette.

const PATH := "res://data/palettes/%s.tres"
const ROLES: Array[String] = [
	"bark",
	"bark_pale",
	"leaf",
	"leaf_dry",
	"needle",
	"grass",
	"heather",
	"moss",
	"earth",
	"stone",
	"stone_dark",
	"wood",
	"thatch",
	"iron",
	"steel",
	"leather",
	"cloth",
	"cloth_dark",
	"skin_a",
	"skin_b",
	"skin_c",
	"skin_d",
	"hair_a",
	"hair_b",
	"hair_c",
	"hair_d",
	"bone",
	"rot",
	"ember",
	"gate",
	"gold",
]
## The only roles allowed to be saturated.
const MEANING: Array[String] = ["ember", "gate", "gold"]

static var _cache: Dictionary = {}
static var _lock := Mutex.new()

## role -> Color (sRGB, alpha 1) and role -> roughness.
@export var colors: Dictionary = {}
@export var roughness: Dictionary = {}


static func of(realm_id: String) -> Palette:
	_lock.lock()
	if not _cache.has(realm_id):
		_cache[realm_id] = load(PATH % realm_id) as Palette
	var found: Palette = _cache[realm_id]
	_lock.unlock()
	return found


## The role's color with its roughness in the alpha, ready to be a vertex color.
func color(role: StringName) -> Color:
	var key := String(role)
	assert(colors.has(key), "palette has no role " + key)
	var c: Color = colors[key]
	return Color(c.r, c.g, c.b, roughness[key])
