class_name Portal
extends RefCounted
## A gate between planets (PLAN §6 M12): stepping into its radius moves the player to the ring
## around `to`, facing `facing`. Part of the rolled back player tick (SimPlayer._use_portal), so
## travel predicts and rolls back like any other move. A victory portal only opens once the
## realm's Warden has fallen.

var position := Vector3.ZERO
var radius := 1.3
## Center of the arrival ring.
var to := Vector3.ZERO
## Where arriving players look.
var facing := Vector3.FORWARD
var needs_victory := false
var label := ""
## The gate's own up (a gate on a realm's ground stands along the local gravity).
var up := Vector3.UP
## A gate that leads into a generated realm (RealmDef.id) arrives at that realm's arrival point,
## which depends on the world seed (Layout.arrival_point); `to` is unused then.
var realm := ""
## A gate that stands on a generated realm's ground: its position depends on the world seed
## (Layout.portals() rebuilds when the seed is set).
var seeded := false


static func at(
	where: Vector3, destination: Vector3, look: Vector3, name_shown: String, victory := false
) -> Portal:
	var portal := Portal.new()
	portal.position = where
	portal.to = destination
	portal.facing = look
	portal.label = name_shown
	portal.needs_victory = victory
	return portal


## Measured along `walker_up`, the up of whoever steps in (a tilted one on a round realm).
func reaches(feet: Vector3, walker_up := Vector3.UP) -> bool:
	var offset := feet - position
	var height := offset.dot(walker_up)
	return absf(height) < 1.5 and (offset - walker_up * height).length() <= radius
