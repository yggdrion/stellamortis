class_name Portal
extends RefCounted
## A gate between planets (PLAN §6 M12): stepping into its radius moves the player to the ring
## around `to`, facing `facing`. Part of the rolled back player tick (SimPlayer._use_portal), so
## travel predicts and rolls back like any other move. A gate with a `needs_flag` only opens once
## that world flag is set (a realm's boss has fallen, World.flags).

var position := Vector3.ZERO
var radius := 1.3
## Center of the arrival ring.
var to := Vector3.ZERO
## Where arriving players look.
var facing := Vector3.FORWARD
## The world flag that opens the gate, empty for a gate that is always open.
var needs_flag: StringName = &""
var label := ""
## The gate's own up (a gate on a realm's ground stands along the local gravity).
var up := Vector3.UP
## A gate that leads into a generated realm (RealmDef.id) arrives at that realm's arrival point,
## which depends on the world seed (Layout.arrival_point); `to` is unused then.
var realm := ""


static func at(
	where: Vector3, destination: Vector3, look: Vector3, name_shown: String, flag: StringName = &""
) -> Portal:
	var portal := Portal.new()
	portal.position = where
	portal.to = destination
	portal.facing = look
	portal.label = name_shown
	portal.needs_flag = flag
	return portal


## Whether the gate is open: always, or once its flag is set (read from the encounters under
## `from_node`).
func is_open(from_node: Node) -> bool:
	return needs_flag == &"" or Encounter.flag_set(from_node, needs_flag)


## Measured along `walker_up`, the up of whoever steps in (a tilted one on a round realm).
func reaches(feet: Vector3, walker_up := Vector3.UP) -> bool:
	var offset := feet - position
	var height := offset.dot(walker_up)
	return absf(height) < 1.5 and (offset - walker_up * height).length() <= radius
