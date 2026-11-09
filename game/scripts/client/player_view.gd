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
		_model.flash(Color(1, 0.15, 0.1, 0.55), 0.15)
	_last_health = player.health
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
