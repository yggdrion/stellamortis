class_name PlayerView
extends Node3D
## A player's look (PLAN §4.5, §3.2): a ranger (Gear.ranger) with sword and round shield or the
## crossbow, posed from the player's rolled back state every frame,
## with its bolts, a hit flash and, for others, a name.

## Per second, how fast the model turns to the body's facing (exponential). The sim snaps the
## facing when an attack or roll starts; turning the model over a few frames keeps that from
## looking like a jump.
const TURN_FOLLOW := 25.0

var player: SimPlayer
var _model: CharacterModel
var _last_health := -1.0
var _turned := Quaternion.IDENTITY
var _respawns := -1
## Sounds: the state last frame, and distance walked since the last footstep.
var _heard_action := -1
var _heard_time := 0
var _heard_attack := -1
var _heard_weapon := -1
var _heard_respawns := -1
var _heard_rise := 0.0
var _stride := 0.0
var _last_feet := Vector3.ZERO


func _init(of: SimPlayer, show_name: bool) -> void:
	player = of
	name = "View"
	_model = (
		Gear
		. ranger(
			player.peer_id,
			{
				"sword": ["RightHand", Gear.sword()],
				"shield": ["LeftLowerArm", Gear.shield()],
				"crossbow": ["RightHand", Gear.crossbow()],
			}
		)
	)
	add_child(_model)
	add_child(BoltsView.new(player))
	if show_name:
		var label := Label3D.new()
		label.text = player.player_name
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = SimPlayer.HEIGHT + 0.45
		label.font_size = 48
		label.pixel_size = 0.005
		label.outline_size = 12
		add_child(label)


func _process(delta: float) -> void:
	visible = Arena.shows(player.global_position)
	_turn(delta)
	if _last_health >= 0.0 and player.health < _last_health:
		_model.flash(Color(1, 0.15, 0.1, 0.35), 0.15)
		var blocked := player.action == SimPlayer.Action.BLOCK
		Sounds.play(self, &"block" if blocked else &"hurt")
	_last_health = player.health
	_sounds(delta)
	var crossbow := player.weapon == SimPlayer.Weapon.CROSSBOW
	_model.show_prop("sword", not crossbow)
	_model.show_prop("shield", not crossbow)
	_model.show_prop("crossbow", crossbow)
	_pose()


## The model's rotation follows the body's with a short lag (global, so the body's own turn
## is what gets smoothed); a respawn snaps it.
func _turn(delta: float) -> void:
	var body := player.global_basis.get_rotation_quaternion()
	if _respawns != player.respawns:
		_respawns = player.respawns
		_turned = body
	_turned = _turned.slerp(body, 1.0 - exp(-TURN_FOLLOW * delta)).normalized()
	_model.quaternion = body.inverse() * _turned


## Sounds for what changed since last frame: swings when the blade moves, rolls, shield up, the
## crossbow, weapon switches, death, portals and respawns, pad launches, footsteps.
func _sounds(delta: float) -> void:
	var action := player.action
	var time := player.action_time
	var fresh := (
		action != _heard_action
		or time < _heard_time
		or (action == SimPlayer.Action.ATTACK and player.attack != _heard_attack)
	)
	var a := SimPlayer.Action
	if action == a.ATTACK:
		var windup := Combat.player_attack(player.attack).windup_ticks()
		if (fresh and time >= windup) or (not fresh and _heard_time < windup and time >= windup):
			var heavy := player.attack == SimPlayer.HEAVY_ATTACK
			Sounds.play(self, &"swing_heavy" if heavy else &"swing")
	elif fresh:
		match action:
			a.ROLL:
				Sounds.play(self, &"cloth", 2.0)
			a.BLOCK:
				Sounds.play(self, &"cloth", -6.0)
			a.DRAW:
				Sounds.play(self, &"draw_bow")
			a.SHOOT:
				Sounds.play(self, &"twang")
			a.DEAD:
				Sounds.play(self, &"fall")
	if _heard_weapon >= 0 and player.weapon != _heard_weapon:
		var sword := player.weapon == SimPlayer.Weapon.SWORD
		Sounds.play(self, &"draw_sword" if sword else &"load", -4.0)
	if _heard_respawns >= 0 and player.respawns != _heard_respawns:
		Sounds.play(self, &"travel")
	var rise := player.velocity.dot(player.up)
	if rise > 9.0 and _heard_rise < 4.0:
		Sounds.play(self, &"whoom")
	_footsteps(delta)
	_heard_action = action
	_heard_time = time
	_heard_attack = player.attack
	_heard_weapon = player.weapon
	_heard_respawns = player.respawns
	_heard_rise = rise


## A step every stride walked on the ground: stone in the keep and on the asteroid, grass in
## the Barrows.
func _footsteps(_delta: float) -> void:
	var feet := player.global_position
	var moved := feet.distance_to(_last_feet)
	_last_feet = feet
	var walking := player.action == SimPlayer.Action.NONE or player.action == SimPlayer.Action.BLOCK
	if not player.grounded or not walking or moved > 2.0:
		return
	_stride += moved
	if _stride < 1.7:
		return
	_stride = 0.0
	var stone := Layout.on_hub(feet) or Gravity.zone_at(feet) != null and feet.y > 20.0
	Sounds.play(self, &"step_stone" if stone else &"step_grass", -8.0)


func _pose() -> void:
	var t := Tuning.data()
	var time := player.action_time + NetworkTime.tick_factor
	match player.action:
		SimPlayer.Action.ATTACK:
			var def := Combat.player_attack(player.attack)
			_model.play_timed(def.animation, time / def.total_ticks(), def.total_ticks() / 30.0)
		SimPlayer.Action.ROLL:
			var ticks := Combat.ticks(t.roll_time)
			_model.play_timed(&"Roll", time / ticks, t.roll_time)
		SimPlayer.Action.BLOCK:
			_model.loop(&"Idle_Shield")
		SimPlayer.Action.DRAW:
			_model.loop(&"Pistol_Aim_Neutral")
		SimPlayer.Action.SHOOT:
			var ticks := Combat.ticks(t.shoot_recover)
			_model.play_timed(&"Pistol_Shoot", time / ticks * 0.6, t.shoot_recover / 0.6)
		SimPlayer.Action.STAGGER:
			var length := maxi(player.action_length, 1)
			_model.play_timed(&"Hit_Chest", time / length, length / 30.0)
		SimPlayer.Action.DEAD:
			_model.play_timed(&"Death01", time / 36.0, 1.2)
		_:
			_locomotion(t)


func _locomotion(t: Tuning) -> void:
	if not player.grounded:
		_model.loop(&"Jump")
		return
	var flat := player.velocity - player.up * player.velocity.dot(player.up)
	var speed := flat.length()
	if speed < 0.4:
		_model.loop(&"Sword_Idle" if player.weapon == SimPlayer.Weapon.SWORD else &"Pistol_Idle")
	elif speed < (t.walk_speed + t.sprint_speed) / 2.0:
		_model.loop(&"Jog_Fwd", speed / t.walk_speed * 0.8)
	else:
		_model.loop(&"Sprint", speed / t.sprint_speed * 1.1)
