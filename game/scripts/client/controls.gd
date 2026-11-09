class_name Controls
extends RefCounted
## The input actions, registered in code so the key list lives in one place.

const KEYS := {
	&"move_forward": [KEY_W],
	&"move_back": [KEY_S],
	&"move_left": [KEY_A],
	&"move_right": [KEY_D],
	&"jump": [KEY_SPACE],
	&"sprint": [KEY_SHIFT],
	&"heavy": [KEY_Q],
	&"roll": [KEY_CTRL, KEY_C],
	&"copy_room": [KEY_F2],
	&"toggle_debug": [KEY_F3],
	&"graphics": [KEY_F4],
	&"weapon_1": [KEY_1],
	&"weapon_2": [KEY_2],
	&"lock": [KEY_TAB],
	&"toggle_fullscreen": [KEY_F11],
	&"release_mouse": [KEY_ESCAPE],
}
const MOUSE := {
	&"attack": [MOUSE_BUTTON_LEFT],
	&"block": [MOUSE_BUTTON_RIGHT],
	&"lock": [MOUSE_BUTTON_MIDDLE],
	&"roll": [MOUSE_BUTTON_XBUTTON1],
	&"weapon_next": [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN],
}
const MOUSE_SENSITIVITY := 0.0025
## Locked: sideways mouse travel (pixels, within FLICK_TIME) that switches the target.
const FLICK_PIXELS := 120.0
const FLICK_TIME := 0.25


static func setup() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
	for action: StringName in MOUSE:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for button: MouseButton in MOUSE[action]:
			var event := InputEventMouseButton.new()
			event.button_index = button
			InputMap.action_add_event(action, event)
