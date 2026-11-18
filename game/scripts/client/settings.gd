class_name Settings
extends RefCounted
## The player's settings besides the graphics preset (Graphics keeps that one), saved in the
## same user://settings.cfg: name, mouse sensitivity, fullscreen, vsync, frame cap, volume,
## camera shake.

const SENSITIVITY_MIN := 0.2
const SENSITIVITY_MAX := 3.0
const NAME_LENGTH := 16
## Frame caps the panel offers (0 is unlimited). The lowest stays above the 30 Hz tick.
const FPS_CAPS: Array[int] = [0, 60, 120, 144, 165, 240]

static var player_name := "player"
## The player body picked in the menu (index into Gear.PLAYER_BODIES).
static var body := 0
## Multiplier on Controls.MOUSE_SENSITIVITY.
static var sensitivity := 1.0
static var fullscreen := true
static var vsync := true
## The round minimap in the HUD corner (M43).
static var minimap := true
## Frame rate cap, 0 is unlimited.
static var max_fps := 0
## --vsync / --max-fps for this run (-1: none); applied but never saved.
static var vsync_flag := -1
static var max_fps_flag := -1
## Master volume, 0..1.
static var volume := 0.8
## Camera shake on hits, 0 (off) to 1.
static var shake := 1.0
## Items the player starred as junk (InventoryPanel): they sort last. Kept in the character file
## (CharacterSave), loaded when a game starts; not in settings.cfg.
static var junk: Array[StringName] = []
## 16 random hex characters made on the first run ([player] id): the ID the server and graves
## know this installation by, until a character file brings its own.
static var player_id := ""


static func load_saved() -> void:
	var config := ConfigFile.new()
	if config.load(Graphics.SETTINGS) != OK:
		return
	player_name = clean_name(str(config.get_value("player", "name", player_name)))
	sensitivity = clampf(
		float(config.get_value("input", "sensitivity", sensitivity)),
		SENSITIVITY_MIN,
		SENSITIVITY_MAX
	)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	vsync = bool(config.get_value("display", "vsync", vsync))
	minimap = bool(config.get_value("display", "minimap", minimap))
	# Only the caps the panel offers: a hand-edited cap below the 30 Hz tick would starve it.
	max_fps = int(config.get_value("display", "max_fps", max_fps))
	if max_fps not in FPS_CAPS:
		max_fps = 0
	volume = clampf(float(config.get_value("audio", "volume", volume)), 0.0, 1.0)
	shake = clampf(float(config.get_value("input", "shake", shake)), 0.0, 1.0)
	player_id = CharacterSave.clean_id(str(config.get_value("player", "id", player_id)))
	body = clampi(int(config.get_value("player", "body", body)), 0, 3)


## Makes the player ID on the first run (and saves it); the same one after.
static func ensure_player_id() -> void:
	if player_id != "":
		return
	var crypto := Crypto.new()
	player_id = crypto.generate_random_bytes(8).hex_encode()
	save()


static func save() -> void:
	var config := ConfigFile.new()
	config.load(Graphics.SETTINGS)
	config.set_value("player", "name", player_name)
	config.set_value("input", "sensitivity", sensitivity)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync)
	config.set_value("display", "minimap", minimap)
	config.set_value("display", "max_fps", max_fps)
	config.set_value("audio", "volume", volume)
	config.set_value("input", "shake", shake)
	config.set_value("player", "id", player_id)
	config.set_value("player", "body", body)
	config.save(Graphics.SETTINGS)


## The junk list as the bit mask Inventory.sort takes (bit n: Items.IDS[n]).
static func junk_mask() -> int:
	var mask := 0
	for id in junk:
		var bit := Items.index(id)
		if bit > 0 and bit < 63:
			mask |= 1 << bit
	return mask


## A name as shown to others: trimmed, at most NAME_LENGTH characters, "player" when empty.
static func clean_name(text: String) -> String:
	var cleaned := text.strip_edges().left(NAME_LENGTH)
	return cleaned if cleaned != "" else "player"


static func apply_window(window: Window) -> void:
	window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
	apply_pacing()


## Vsync and the frame cap (the run's flags win); clients with a window only, never servers.
static func apply_pacing() -> void:
	var on := vsync if vsync_flag < 0 else vsync_flag == 1
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if on else DisplayServer.VSYNC_DISABLED
	)
	Engine.max_fps = max_fps if max_fps_flag < 0 else max_fps_flag
