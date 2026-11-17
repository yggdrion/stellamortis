class_name BotPlans
extends RefCounted
## The scripted bot plans of the network test and the screenshots (--bot-plan), moved out of
## GameClient unchanged. A BotBrain (--bot-skill) plays like a person instead.


## Fills the controls for a plan at `seconds` since the start. `yaw` and `pitch` are the camera's
## (--look); `peer_id` spreads the circle walk of several bots.
static func fill(
	plan: String, controls: PlayerControls, seconds: float, yaw: float, pitch: float, peer_id: int
) -> void:
	var b := PlayerControls.Buttons
	if plan == "combo" or plan == "combo_walk":
		# Looks where --look points and chains light combos, every 4th time a heavy; combo_walk
		# also walks forward and sweeps the camera (rubberband checks: STELLAMORTIS_SNAP_LOG=1).
		var walking := plan == "combo_walk"
		controls.move = Vector2(0.0, 1.0) if walking else Vector2.ZERO
		controls.yaw = yaw + (sin(seconds * 1.3) * 0.8 if walking else 0.0)
		controls.pitch = pitch
		controls.weapon = SimPlayer.Weapon.SWORD
		var beat := int(seconds * 5.0)
		var heavy := beat % 40 >= 30
		controls.buttons = (b.HEAVY if heavy else b.ATTACK) if beat % 2 == 0 else 0
		return
	if plan == "shoot":
		controls.move = Vector2.ZERO
		controls.yaw = yaw
		controls.pitch = pitch
		controls.weapon = SimPlayer.Weapon.CROSSBOW
		controls.buttons = b.BLOCK | (b.ATTACK if fmod(seconds, 1.4) < 1.0 else 0)
		return
	# Walks a circle and runs through jump, attack, heavy, roll and block on a rhythm.
	controls.move = Vector2(0.0, 1.0)
	controls.yaw = fposmod(seconds * 0.8 + peer_id % 7, TAU)
	controls.buttons = [b.JUMP, b.ATTACK, b.HEAVY, b.ROLL, b.BLOCK, 0][int(seconds * 2.0) % 6]
	# Every other 4 s with the crossbow: draws on ATTACK, aims on BLOCK.
	controls.weapon = int(seconds / 4.0) % 2
