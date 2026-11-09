class_name Sounds
extends RefCounted
## Sound (PLAN §6 M14): named sounds with variants, played as positional one-shots on the node
## they come from, loops for torches, portals and the Warden's well, a 2D ambience per planet and
## UI clicks. Kenney's CC0 packs give footsteps, impacts, cloth and UI; tools/make_sounds.py
## synthesizes the rest (swooshes, the twang, telegraphs, embers, hums, wind, fire). Views call
## these when the state they show changes; headless processes play nothing.

const KENNEY := "res://assets/sounds/kenney/"
const SYNTH := "res://assets/sounds/synth/"
const BUSES := [&"Effects", &"Ambience", &"UI"]
## Sound name -> its files (one is picked at random each time).
static var library := {
	&"step_grass": _numbered(KENNEY + "footstep_grass_%03d.ogg", 5),
	&"step_stone": _numbered(KENNEY + "footstep_concrete_%03d.ogg", 5),
	&"swing": _numbered(SYNTH + "swing_%d.wav", 3),
	&"swing_heavy": [SYNTH + "swing_heavy.wav"],
	&"swing_giant": [SYNTH + "swing_giant.wav"],
	&"hit": _numbered(KENNEY + "impactPunch_medium_%03d.ogg", 3),
	&"hurt": _numbered(KENNEY + "impactPunch_heavy_%03d.ogg", 3),
	&"block": _numbered(KENNEY + "impactPlank_medium_%03d.ogg", 3),
	&"parry": [KENNEY + "impactBell_heavy_000.ogg"],
	&"clang": _numbered(KENNEY + "impactMetal_heavy_%03d.ogg", 2),
	&"fall": _numbered(KENNEY + "impactSoft_heavy_%03d.ogg", 2),
	&"bolt_hit": _numbered(KENNEY + "impactWood_light_%03d.ogg", 3),
	&"stomp": [KENNEY + "impactMining_000.ogg"],
	&"cloth": _numbered(KENNEY + "cloth%d.ogg", 4, 1),
	&"draw_sword": [KENNEY + "drawKnife1.ogg", KENNEY + "drawKnife2.ogg"],
	&"draw_bow": [KENNEY + "creak1.ogg"],
	&"load": [KENNEY + "metalClick.ogg"],
	&"twang": [SYNTH + "twang.wav"],
	&"telegraph": [SYNTH + "telegraph.wav"],
	&"telegraph_giant": [SYNTH + "telegraph_giant.wav"],
	&"ember": [SYNTH + "ember.wav"],
	&"travel": [SYNTH + "travel.wav"],
	&"whoom": [SYNTH + "whoom.wav"],
	&"ui_click": [KENNEY + "click_002.ogg"],
	&"ui_hover": [KENNEY + "select_001.ogg"],
	&"ui_start": [KENNEY + "confirmation_001.ogg"],
	&"ui_back": [KENNEY + "back_001.ogg"],
	&"portal": [SYNTH + "portal_hum.wav"],
	&"well": [SYNTH + "well.wav"],
	&"torch": [SYNTH + "torch.wav"],
	&"wind_keep": [SYNTH + "wind_keep.wav"],
	&"wind_barrows": [SYNTH + "wind_barrows.wav"],
}
static var _streams := {}


## Makes the buses (once) and sets the master volume from Settings.
static func setup() -> void:
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(&"Ambience"), linear_to_db(0.6))
	apply_volume()


static func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(Settings.volume, 0.0001)))


## A one-shot from a node, in 3D: it follows the node and frees itself when done.
static func play(at: Node3D, sound: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if _silent() or at == null or not at.is_inside_tree():
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _pick(sound)
	player.bus = &"Effects"
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.93, 1.07)
	player.unit_size = 6.0
	player.max_distance = 60.0
	player.attenuation_filter_cutoff_hz = 6000.0
	player.finished.connect(player.queue_free)
	at.add_child(player)
	player.play()


## A looping 3D sound on a node (torches, portals, the well), playing at once unless start is
## false; returns the player to start or stop.
static func loop(
	at: Node3D, sound: StringName, volume_db := 0.0, reach := 14.0, start := true
) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = _looping(sound)
	player.bus = &"Effects"
	player.volume_db = volume_db
	player.max_distance = reach
	player.unit_size = reach / 3.0
	var playing := start and not _silent()
	player.autoplay = playing
	at.add_child(player)
	if playing and player.is_inside_tree():
		player.play()
	return player


## The planet's ambience on a 2D player (the wind of the keep or of the Barrows).
static func ambience(player: AudioStreamPlayer, on_hub: bool) -> void:
	if _silent():
		return
	var stream := _looping(&"wind_keep" if on_hub else &"wind_barrows")
	if player.stream == stream and player.playing:
		return
	player.bus = &"Ambience"
	player.stream = stream
	player.play()


## A UI sound, not positional.
static func ui(from: Node, sound: StringName) -> void:
	if _silent() or from == null or not from.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = _pick(sound)
	player.bus = &"UI"
	player.volume_db = -6.0
	player.finished.connect(player.queue_free)
	from.get_tree().root.add_child(player)
	player.play()


static func _pick(sound: StringName) -> AudioStream:
	var files: Array = library[sound]
	var path: String = files[randi() % files.size()]
	if not _streams.has(path):
		_streams[path] = load(path)
	return _streams[path]


## The sound's first file set to loop over its whole length.
static func _looping(sound: StringName) -> AudioStream:
	var path: String = library[sound][0]
	var key := path + "#loop"
	if _streams.has(key):
		return _streams[key]
	var stream := (load(path) as AudioStreamWAV).duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	_streams[key] = stream
	return stream


static func _numbered(pattern: String, count: int, first := 0) -> Array:
	var files := []
	for i in count:
		files.append(pattern % (first + i))
	return files


static func _silent() -> bool:
	return DisplayServer.get_name() == "headless"
