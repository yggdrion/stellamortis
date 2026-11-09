class_name PlayerView
extends Node3D
## A player's look (PLAN §4.5): the KayKit knight with sword and shield or crossbow, posed from
## the player's rolled back state every frame, with its bolts, a hit flash and, for others, a
## name.

const KNIGHT := "res://assets/kaykit/Knight.glb"
const SWORD := "res://assets/kaykit/sword_1handed.gltf"
const SHIELD := "res://assets/kaykit/shield_round_color.gltf"
const CROSSBOW := "res://assets/kaykit/crossbow_1handed.gltf"

var player: SimPlayer
var _model: CharacterModel
var _last_health := -1.0


func _init(of: SimPlayer, show_name: bool) -> void:
	player = of
	name = "View"
	_model = (
		CharacterModel
		. new(
			KNIGHT,
			{
				"sword": ["handslot.r", SWORD],
				"shield": ["handslot.l", SHIELD],
				"crossbow": ["handslot.r", CROSSBOW],
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


func _process(_delta: float) -> void:
	if _last_health >= 0.0 and player.health < _last_health:
		_model.flash(Color(1, 0.15, 0.1, 0.55), 0.15)
	_last_health = player.health
	var crossbow := player.weapon == SimPlayer.Weapon.CROSSBOW
	_model.show_prop("sword", not crossbow)
	_model.show_prop("shield", not crossbow)
	_model.show_prop("crossbow", crossbow)
	_pose()


func _pose() -> void:
	var t := Tuning.data()
	var time := player.action_time + NetworkTime.tick_factor
	match player.action:
		SimPlayer.Action.ATTACK:
			var def := Combat.player_attack(player.attack)
			_model.play_timed(def.animation, time / def.total_ticks(), def.total_ticks() / 30.0)
		SimPlayer.Action.ROLL:
			var ticks := Combat.ticks(t.roll_time)
			_model.play_timed(&"Dodge_Forward", time / ticks, t.roll_time)
		SimPlayer.Action.BLOCK:
			_model.loop(&"Blocking")
		SimPlayer.Action.DRAW:
			_model.loop(&"1H_Ranged_Aiming")
		SimPlayer.Action.SHOOT:
			var ticks := Combat.ticks(t.shoot_recover)
			_model.play_timed(&"1H_Ranged_Shoot", time / ticks * 0.6, t.shoot_recover / 0.6)
		SimPlayer.Action.STAGGER:
			var length := maxi(player.action_length, 1)
			_model.play_timed(&"Hit_A", time / length, length / 30.0)
		SimPlayer.Action.DEAD:
			_model.play_timed(&"Death_A", time / 24.0, 0.8)
		_:
			_locomotion(t)


func _locomotion(t: Tuning) -> void:
	if not player.grounded:
		_model.loop(&"Jump_Idle")
		return
	var flat := player.velocity - player.up * player.velocity.dot(player.up)
	var speed := flat.length()
	if speed < 0.4:
		_model.loop(&"Idle")
	elif speed < (t.walk_speed + t.sprint_speed) / 2.0:
		_model.loop(&"Running_A", speed / t.walk_speed * 0.8)
	else:
		_model.loop(&"Running_B", speed / t.sprint_speed * 1.1)
