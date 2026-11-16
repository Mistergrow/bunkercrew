extends RefCounted
## Guidance follows the active input route without changing its bindings.
const NetInput := preload("res://scripts/network_input.gd")
const L := preload("res://scripts/locale_text.gd")
const PAD_LABELS := {"interact":"X", "jump":"A", "drop":"B", "reload":"Y", "cycle_material":"LB", "cycle_target":"RB", "cycle_weapon":"R-Stick drücken", "craft_next":"L3", "deploy":"Pad rechts", "fire":"RT"}
const NUMPAD_LABELS := {KEY_KP_0:"Num 0", KEY_KP_MULTIPLY:"Num*", KEY_KP_PERIOD:"Num."}

## True while the most recent deliberate input came from a controller. Menus
## and footers show the glyphs of that device and switch as soon as it changes.
static var pad_active := false
## Last device per local player prefix ("p2", "p3", ...), once they have used one.
static var _player_pad: Dictionary = {}

## Feed every input event; returns true when the active device changed.
## `shared_screen` is true only while several local players exist: the same
## controller belongs to P1 when playing alone and to P2 once a partner joins,
## so per-player devices are learned afresh for each shared session.
static func note_event(event: InputEvent, shared_screen: bool = false) -> bool:
	if not shared_screen and not _player_pad.is_empty(): _player_pad.clear()
	var pad := pad_active
	if event is InputEventJoypadButton and event.pressed: pad = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5: pad = true
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed: pad = false
	# Shared-screen players are told apart by whose bindings the event matches.
	if shared_screen and (event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion):
		var from_pad := not event is InputEventKey
		if event.is_pressed() or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
			for name: StringName in InputMap.get_actions():
				var text := str(name)
				if text.length() > 3 and text[0] == "p" and text[1].is_valid_int() and text[2] == "_" and event.is_action(name):
					_player_pad[text.left(2)] = from_pad
					break
	if pad == pad_active: return false
	pad_active = pad
	return true

static func navigate_glyphs() -> Array[String]:
	var glyphs: Array[String] = ["↑","↓"]
	if pad_active: glyphs.assign(["dpad"])
	return glyphs

static func confirm_glyphs() -> Array[String]:
	var glyphs: Array[String] = ["Enter"]
	if pad_active: glyphs.assign(["A"])
	return glyphs

static func back_glyphs() -> Array[String]:
	var glyphs: Array[String] = ["Esc"]
	if pad_active: glyphs.assign(["B"])
	return glyphs

## Entries for `UiArt.hints`: choose, confirm and optionally leave.
static func navigation_hints(with_back: bool = false) -> Array:
	var entries: Array = [[navigate_glyphs(),"wählen"],[confirm_glyphs(),"bestätigen"]]
	if with_back: entries.append([back_glyphs(),"zurück"])
	return entries

## Entries for reading screens: choose a page, step into the text, leave.
static func reading_hints() -> Array:
	var into: Array[String] = ["→"]
	return [[navigate_glyphs(),"wählen"],[into,"lesen"],[back_glyphs(),"zurück"]]

static func action(worker: Node, suffix: String) -> String:
	if not is_instance_valid(worker): return ""
	var online := NetInput.session(worker) != null
	var primary := online or int(worker.get("player_id")) == 1
	if primary and not NetInput.mouse_aim(worker) and PAD_LABELS.has(suffix): return L.text(str(PAD_LABELS[suffix]))
	var key := "p1_" + suffix if primary else str(worker.action(suffix))
	var label := _keyboard(key)
	if not primary and PAD_LABELS.has(suffix):
		# Once this player has pressed something, show only the device in use.
		var known: Variant = _player_pad.get(key.left(2))
		if known == true: return L.text(str(PAD_LABELS[suffix]))
		if known == false and not label.is_empty(): return label
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
