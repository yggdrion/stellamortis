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
	&"toggle_debug": [KEY_F3],
	&"toggle_fullscreen": [KEY_F11],
	&"release_mouse": [KEY_ESCAPE],
}
const MOUSE_SENSITIVITY := 0.0025


static func setup() -> void:
	for action: StringName in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: Key in KEYS[action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			InputMap.action_add_event(action, event)
