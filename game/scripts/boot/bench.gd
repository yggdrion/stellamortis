class_name Bench
extends Node
## --bench=N: simulates N players (walking, attacking, rolling, locking on, as the bots do) and
## every enemy for a few hundred ticks in one process, without the network, and prints what a
## tick costs (PLAN M7). The server's tick loop resimulates whole ticks like these whenever
## late input arrives, so this is the cost netfox multiplies.

const TICKS := 300
const DELTA := 1.0 / 30.0

var players := 10


func _ready() -> void:
	var world := World.new(false)
	add_child(world)
	var bodies: Array[SimPlayer] = []
	for i in players:
		var body := SimPlayer.new()
		body.peer_id = i + 2
		world.players.add_child(body)
		body.place(Layout.spawn_point(body.peer_id))
		bodies.append(body)
	var enemies := get_tree().get_nodes_in_group(Enemy.GROUP)
	await get_tree().physics_frame
	var player_us := 0
	var enemy_us := 0
	var encounter_us := 0
	for tick in TICKS:
		var started := Time.get_ticks_usec()
		for body in bodies:
			var b := PlayerControls.Buttons
			var buttons: int = [b.JUMP, b.ATTACK, b.LOCK, b.HEAVY, b.ROLL, b.BLOCK, 0][
				(tick / 15 + body.peer_id) % 7
			]
			body.step(Vector2(0, 1), fposmod(tick * 0.03 + body.peer_id, TAU), buttons, DELTA)
		var after_players := Time.get_ticks_usec()
		for enemy in enemies:
			enemy.call("_rollback_tick", DELTA, tick, true)
		var after_enemies := Time.get_ticks_usec()
		world.encounter._rollback_tick(DELTA, tick, true)
		encounter_us += Time.get_ticks_usec() - after_enemies
		player_us += after_players - started
		enemy_us += after_enemies - after_players
		await get_tree().physics_frame
	var per_tick := (player_us + enemy_us + encounter_us) / 1000.0 / TICKS
	print(
		(
			"bench players=%d enemies=%d tick_ms=%.3f player_us=%.1f enemy_us=%.1f"
			% [
				players,
				enemies.size(),
				per_tick,
				float(player_us) / TICKS / players,
				float(enemy_us) / TICKS / enemies.size(),
			]
		)
	)
	get_tree().quit()
