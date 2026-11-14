class_name RealmDef
extends Resource
## A generated round realm (M20): where it floats, how big, how it pulls, and the numbers that
## shape its ground (Terrain). Data in res://data/realms/*.tres, listed by Layout.realms().

## Gravity reaches this far above the surface.
const GRAVITY_REACH := 300.0

@export var id := ""
@export var center := Vector3.ZERO
## Radius of the sea-level sphere, meters.
@export var radius := 1000.0
## m/s² toward the center.
@export var gravity := 9.8
## Mixed into the world seed so realms differ under one seed.
@export var seed_salt := 0
@export var biome := ""
## Where players arrive: a direction from the center.
@export var arrival := Vector3.UP
## Ground shape, meters: low rolling moor, broad hills, a few ridges where the mask is high.
@export var moor_height := 3.0
@export var moor_wavelength := 120.0
@export var hill_height := 22.0
@export var hill_wavelength := 350.0
@export var ridge_height := 45.0
@export var ridge_wavelength := 260.0
## Wavelength of the noise that decides where ridges stand.
@export var ridge_mask_wavelength := 900.0


func reach() -> float:
	return radius + GRAVITY_REACH
