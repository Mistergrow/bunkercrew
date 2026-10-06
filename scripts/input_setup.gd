class_name InputSetup
extends RefCounted
## Kept in one place so remapping never changes production or combat logic.
static var _primary_pad_device := 0

static func install() -> void:
	var keyboard := {
		"p1_left": KEY_A, "p1_right": KEY_D,
		"p1_up": KEY_W, "p1_down": KEY_S,
		"p1_jump": KEY_SPACE, "p1_interact": KEY_E,
		"p1_drop": KEY_Q, "p1_reload": KEY_R, "p1_cycle_material": KEY_TAB,
		"p1_cycle_target": KEY_F,
		"p1_cycle_weapon": KEY_C,
		"p1_craft_next": KEY_G, "p1_deploy": KEY_B,
		"p2_left": KEY_LEFT, "p2_right": KEY_RIGHT,
		"p2_up": KEY_UP, "p2_down": KEY_DOWN,
		"p2_jump": KEY_SHIFT, "p2_interact": KEY_ENTER,
		"p2_drop": KEY_BACKSPACE, "p2_reload": KEY_DELETE, "p2_cycle_material": KEY_INSERT,
		"p2_cycle_target": KEY_PAGEDOWN,
		"p2_cycle_weapon": KEY_KP_0,
		"p2_craft_next": KEY_KP_MULTIPLY, "p2_deploy": KEY_KP_PERIOD,
		"p2_fire": KEY_CTRL, "p2_aim_up": KEY_HOME,
		"p2_aim_down": KEY_END,
		"pause": KEY_ESCAPE, "help": KEY_F1, "weather_toggle": KEY_F3, "audio_settings": KEY_F4,
		"restart": KEY_F5, "join": KEY_F2,
		"upgrades": KEY_T,
		"personnel": KEY_P, "achievements": KEY_F6, "parallax_preview": KEY_F8,
		"friends": KEY_F7, "chat": KEY_ENTER,
		"story_journal": KEY_J,
		"skip_build": KEY_N, "start": KEY_SPACE,
	}
	for action_name in keyboard:
		_ensure_action(action_name)
		var event := InputEventKey.new()
		event.physical_keycode = keyboard[action_name]
		if action_name in ["p2_jump", "p2_fire"]:
			event.location = KEY_LOCATION_RIGHT
		InputMap.action_add_event(action_name, event)
	_ensure_action("p1_fire")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("p1_fire", mouse)
	# Player one uses the mouse to aim; actions remain available for remapping.
	_ensure_action("p1_aim_up")
	_ensure_action("p1_aim_down")
	var buttons := {"jump":JOY_BUTTON_A,"interact":JOY_BUTTON_X,"drop":JOY_BUTTON_B,"reload":JOY_BUTTON_Y,"cycle_material":JOY_BUTTON_LEFT_SHOULDER,"cycle_target":JOY_BUTTON_RIGHT_SHOULDER,"cycle_weapon":JOY_BUTTON_RIGHT_STICK,"craft_next":JOY_BUTTON_LEFT_STICK,"deploy":JOY_BUTTON_DPAD_RIGHT}
	for slot in range(2, PartyConfig.MAX_PLAYERS + 1):
		var prefix := "p%d_" % slot
		for suffix in ["left","right","up","down","aim_up","aim_down","fire"] + buttons.keys():
			if slot > 2: _ensure_action(prefix + suffix)
		for suffix in buttons:
			var event := InputEventJoypadButton.new()
			event.device = slot - 2
			event.button_index = buttons[suffix]
			InputMap.action_add_event(prefix + suffix, event)
		_joy_axis(prefix+"left", JOY_AXIS_LEFT_X, -1.0,slot-2)
		_joy_axis(prefix+"right", JOY_AXIS_LEFT_X, 1.0,slot-2)
		_joy_axis(prefix+"up", JOY_AXIS_LEFT_Y, -1.0,slot-2)
		_joy_axis(prefix+"down", JOY_AXIS_LEFT_Y, 1.0,slot-2)
		_joy_axis(prefix+"aim_up", JOY_AXIS_RIGHT_Y, -1.0,slot-2)
		_joy_axis(prefix+"aim_down", JOY_AXIS_RIGHT_Y, 1.0,slot-2)
		_joy_axis(prefix+"fire", JOY_AXIS_TRIGGER_RIGHT, 1.0,slot-2)
	for action_name in {"personnel":JOY_BUTTON_DPAD_UP,"upgrades":JOY_BUTTON_BACK,"pause":JOY_BUTTON_START}:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = {"personnel":JOY_BUTTON_DPAD_UP,"upgrades":JOY_BUTTON_BACK,"pause":JOY_BUTTON_START}[action_name]
		InputMap.action_add_event(action_name, event)
	# Desktop defaults do not include A/B in ui_accept/ui_cancel. Native menu
	# controls share these actions, including the scenario and character screens.
	for action_name in {"ui_accept":JOY_BUTTON_A,"ui_cancel":JOY_BUTTON_B}:
		var event := InputEventJoypadButton.new()
		event.device = -1
		event.button_index = JOY_BUTTON_A if action_name=="ui_accept" else JOY_BUTTON_B
		if not InputMap.action_has_event(action_name,event):
			InputMap.action_add_event(action_name,event)
	# Keep the first pad independent from P1 keyboard/mouse. Runtime routing
	# gives it to P1 in solo/online and preserves P2 ownership in local co-op.
	for suffix: String in ["left","right","up","down","aim_up","aim_down","fire"] + buttons.keys():
		var action_name := "primary_pad_" + suffix
		_ensure_action(action_name)
		for source: InputEvent in InputMap.action_get_events("p2_" + suffix):
			if source is InputEventJoypadButton or source is InputEventJoypadMotion:
				InputMap.action_add_event(action_name, source.duplicate())
	_sync_primary_pad()
	if not Input.joy_connection_changed.is_connected(_primary_pad_changed):
		Input.joy_connection_changed.connect(_primary_pad_changed)

static func _primary_pad_changed(_device: int, _connected: bool) -> void:
	_sync_primary_pad()

static func _sync_primary_pad() -> void:
	var connected := Input.get_connected_joypads()
	_assign_primary_pad(int(connected[0]) if not connected.is_empty() else 0)
	for slot in range(2, PartyConfig.MAX_PLAYERS + 1):
		var index := slot - 2
		_assign_pad_prefix("p%d_" % slot, int(connected[index]) if index < connected.size() else index)

static func _assign_primary_pad(device: int) -> void:
	_primary_pad_device = device
	_assign_pad_prefix("primary_pad_", _primary_pad_device)

static func _assign_pad_prefix(prefix: String, device: int) -> void:
	for action_name: StringName in InputMap.get_actions():
		if not str(action_name).begins_with(prefix): continue
		for event: InputEvent in InputMap.action_get_events(action_name):
			if event is InputEventJoypadButton or event is InputEventJoypadMotion: event.device = device

static func _ensure_action(action_name: String) -> void:
	if InputMap.has_action(action_name):
		InputMap.action_erase_events(action_name)
	else:
		InputMap.add_action(action_name, 0.23)

static func _joy_axis(action_name: String, axis: JoyAxis, value: float, device: int = 0) -> void:
	var event := InputEventJoypadMotion.new()
	event.device = device
	event.axis = axis
	event.axis_value = value
	InputMap.action_add_event(action_name, event)
