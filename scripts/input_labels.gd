extends RefCounted
## Guidance follows the active input route without changing its bindings.
const NetInput := preload("res://scripts/network_input.gd")
const L := preload("res://scripts/locale_text.gd")
const PAD_LABELS := {"interact":"X", "jump":"A", "drop":"B", "reload":"Y", "cycle_material":"LB", "cycle_target":"RB", "cycle_weapon":"R-Stick drücken", "craft_next":"L3", "deploy":"Pad rechts", "fire":"RT"}
const NUMPAD_LABELS := {KEY_KP_0:"Num 0", KEY_KP_MULTIPLY:"Num*", KEY_KP_PERIOD:"Num."}

static func action(worker: Node, suffix: String) -> String:
	if not is_instance_valid(worker): return ""
	var online := NetInput.session(worker) != null
	var primary := online or int(worker.get("player_id")) == 1
	if primary and not NetInput.mouse_aim(worker) and PAD_LABELS.has(suffix): return L.text(str(PAD_LABELS[suffix]))
	var key := "p1_" + suffix if primary else str(worker.action(suffix))
	var label := _keyboard(key)
	if not primary and PAD_LABELS.has(suffix):
		return label + " / " + L.text(str(PAD_LABELS[suffix])) if not label.is_empty() else L.text(str(PAD_LABELS[suffix]))
	return label

static func menu(game: Node, action_name: String) -> String:
	if action_name == "story_journal" and NetInput.primary_controller_enabled(game) and not NetInput._primary_mouse_aim(game):
		return L.text("Pause → Logbuch")
	return _keyboard(action_name)

static func _keyboard(action_name: String) -> String:
	if not InputMap.has_action(action_name): return ""
	for event: InputEvent in InputMap.action_get_events(action_name):
		if event is InputEventKey:
			var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
			return L.text(str(NUMPAD_LABELS.get(code, OS.get_keycode_string(code))))
	return ""
