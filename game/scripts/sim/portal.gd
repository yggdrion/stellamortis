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


func reaches(feet: Vector3) -> bool:
	var flat := feet - position
	return absf(flat.y) < 1.5 and Vector2(flat.x, flat.z).length() <= radius
