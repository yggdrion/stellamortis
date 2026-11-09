class_name RollbackProfile
extends RefCounted
## Splits the server's netfox rollback loop into its stages (restore, simulate, record and
## send), for the load test (STELLAMORTIS_SERVER_STATS). Microseconds summed until take().

var restore_us := 0
var simulate_us := 0
var record_us := 0
var ticks := 0
var _mark := 0


func attach() -> void:
	NetworkRollback.on_prepare_tick.connect(_on_prepare)
	NetworkRollback.after_prepare_tick.connect(func(_t: int) -> void: restore_us += _lap())
	NetworkRollback.after_process_tick.connect(func(_t: int) -> void: simulate_us += _lap())
	NetworkRollback.after_loop.connect(func() -> void: record_us += _lap() if _mark > 0 else 0)


func _on_prepare(_tick: int) -> void:
	# The previous tick's record and send stage ends here.
	if _mark > 0 and ticks > 0:
		record_us += _lap()
	_mark = Time.get_ticks_usec()
	ticks += 1


func _lap() -> int:
	var now := Time.get_ticks_usec()
	var took := now - _mark
	_mark = now
	return took


## "restore=a simulate=b record_send=c" in ms per resimulated tick, then starts over.
func take() -> String:
	var n := maxi(ticks, 1)
	var text := (
		"restore_ms=%.2f simulate_ms=%.2f record_send_ms=%.2f"
		% [restore_us / 1000.0 / n, simulate_us / 1000.0 / n, record_us / 1000.0 / n]
	)
	restore_us = 0
	simulate_us = 0
	record_us = 0
	ticks = 0
	_mark = 0
	return text
