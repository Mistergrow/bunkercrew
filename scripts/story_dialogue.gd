class_name StoryDialogue
extends CanvasLayer
## Presentation only. The host's story director decides which authored event occurs.

const Catalog := preload("res://scripts/story_dialogue_catalog.gd")
const MAX_QUEUE := 8
const MAX_SERIALS := 128

var game: Node
var canvas: Control
var voice: AudioStreamPlayer
var active: Dictionary = {}
var pending: Array[Dictionary] = []
var elapsed := 0.0
var active_age := 0.0
var active_duration := 0.0
var spoken_count := 0
var panel_bounds := Rect2()
var _seen: Dictionary = {}
var _highest_serial := 0
var _cooldowns: Dictionary = {}
var _streams: Dictionary = {}
var _ducked := false
var _retired_playbacks: Array[WeakRef] = []


func _ready() -> void:
	layer = 65
	process_mode = Node.PROCESS_MODE_ALWAYS
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.draw.connect(_draw)
	add_child(canvas)
	voice = AudioStreamPlayer.new()
	voice.name = "RecordedDialogue"
	# Isolated previews may not construct the production AudioController.
	if AudioServer.get_bus_index("Voice") < 0:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, "Voice")
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	voice.bus = "Voice"
	add_child(voice)
	for id: String in Catalog.LINES:
		for speaker_id: String in Catalog.SPEAKERS:
			for locale: String in LocaleText.SUPPORTED:
				var path := Catalog.recording_path(id, speaker_id, locale)
				if not path.is_empty() and ResourceLoader.exists(path): _streams[path] = load(path)
	var localization := get_tree().root.get_node_or_null("Localization")
	if localization != null: localization.locale_changed.connect(_locale_changed)
	canvas.hide()


func enqueue(id: String, speaker_id: String = "san", anchor_player_id: int = 0, event_serial: int = 0) -> bool:
	if event_serial < 0 or event_serial > 2147483647 or anchor_player_id < 0 or anchor_player_id > PartyConfig.MAX_PLAYERS:
		return false
	if event_serial > 0 and (_seen.has(event_serial) or event_serial <= _highest_serial - MAX_SERIALS): return false
	var detail := Catalog.line(id, speaker_id)
	if detail.is_empty(): return false
	var anchor := _resolve_anchor(speaker_id, anchor_player_id)
	# Never invent a teammate's voice in a solo run or after character selection.
	if speaker_id != "san" and anchor == null: return false
	var key := id + ":" + speaker_id
	if elapsed < float(_cooldowns.get(key, -INF)): return false
	if not active.is_empty() and active.id == id and active.speaker_id == speaker_id: return false
	for item in pending:
		if item.id == id and item.speaker_id == speaker_id: return false
	detail.anchor_player_id = int(anchor.get("player_id")) if anchor != null else anchor_player_id
	detail.queued_at = elapsed
	detail.serial = event_serial
	if pending.size() >= MAX_QUEUE:
		var lowest := 0
		for index in pending.size():
			if int(pending[index].priority) < int(pending[lowest].priority): lowest = index
		if int(detail.priority) <= int(pending[lowest].priority): return false
		pending.remove_at(lowest)
	if event_serial > 0:
		_seen[event_serial] = true
		_highest_serial = maxi(_highest_serial, event_serial)
		while _seen.size() > MAX_SERIALS: _seen.erase(_seen.keys()[0])
	_cooldowns[key] = elapsed + float(detail.cooldown)
	if bool(detail.ending):
		# Match conclusions supersede stale combat/build instructions.
		pending = pending.filter(func(item: Dictionary): return bool(item.ending))
	if not active.is_empty() and int(detail.priority) >= 4 and int(detail.priority) > int(active.priority):
		_finish()
	pending.append(detail)
	return true


func reset() -> void:
	pending.clear()
	_seen.clear()
	_highest_serial = 0
	_cooldowns.clear()
	elapsed = 0.0
	spoken_count = 0
	_finish()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_instance_valid(voice): return
	_prune_retired_playbacks()
	var paused := _presentation_paused()
	voice.stream_paused = paused
	canvas.visible = _caption_visible()
	_set_ducked(voice.playing and not paused)
	if paused: return
	elapsed += delta
	if not active.is_empty():
		active_age += delta
		if active_age >= active_duration:
			_finish()
	if active.is_empty(): _start_next()
	canvas.visible = _caption_visible()
	if canvas.visible: canvas.queue_redraw()


func _start_next() -> void:
	for index in range(pending.size() - 1, -1, -1):
		var item := pending[index]
		if elapsed - float(item.queued_at) > float(item.expires): pending.remove_at(index)
	if pending.is_empty(): return
	var best := 0
	for index in pending.size():
		if int(pending[index].priority) > int(pending[best].priority): best = index
	var candidate: Dictionary = pending.pop_at(best)
	if candidate.speaker_id != "san" and _resolve_anchor(candidate.speaker_id, candidate.anchor_player_id) == null:
		_start_next()
		return
	_begin_line(candidate)


func _begin_line(candidate: Dictionary) -> void:
	active = candidate
	active_age = 0.0
	# Muting speech retains the complete subtitle for a comfortable reading time.
	active_duration = clampf(str(active.text).length() / 16.0 + 0.8, 2.8, 13.0)
	voice.stream = _streams.get(active.voice_path)
	if voice.stream != null:
		active_duration = maxf(active_duration, voice.stream.get_length() + 0.45)
		# A locale change can happen inside a paused settings screen. Starting at
		# zero volume prevents even one old/mismatched syllable during handover.
		voice.volume_db = -80.0
		voice.play()
		voice.stream_paused = _presentation_paused()
		voice.volume_db = 0.0
	spoken_count += 1
	_set_ducked(voice.playing and not voice.stream_paused)


func _locale_changed(_locale: String) -> void:
	if not is_instance_valid(voice): return
	var previous := active.duplicate(true)
	_finish()
	for index in pending.size(): pending[index] = _localized_event(pending[index])
	if not previous.is_empty():
		# Restart the currently audible sentence. Identity, event dedupe, pending
		# order and the game clock survive; text and recording switch together.
		var previous_count := spoken_count
		_begin_line(_localized_event(previous))
		spoken_count = previous_count
	var paused := _presentation_paused()
	voice.stream_paused = paused
	canvas.visible = _caption_visible()
	_set_ducked(voice.playing and not paused)
	canvas.queue_redraw()


func _localized_event(event: Dictionary) -> Dictionary:
	var result := Catalog.line(str(event.id), str(event.speaker_id))
	for field in ["anchor_player_id", "queued_at", "serial"]: result[field] = event[field]
	return result


func _finish() -> void:
	if is_instance_valid(voice):
		if voice.has_stream_playback():
			_retired_playbacks.append(weakref(voice.get_stream_playback()))
		voice.stop()
		voice.stream = null
	_prune_retired_playbacks()
	active.clear()
	active_age = 0.0
	active_duration = 0.0
	panel_bounds = Rect2()
	if is_instance_valid(canvas): canvas.hide()
	_set_ducked(false)


func _prune_retired_playbacks() -> void:
	for index in range(_retired_playbacks.size()-1,-1,-1):
		if _retired_playbacks[index].get_ref() == null:
			_retired_playbacks.remove_at(index)


func get_retired_audio_playbacks() -> Array[WeakRef]:
	_prune_retired_playbacks()
	return _retired_playbacks.duplicate()


func _set_ducked(value: bool) -> void:
	if value == _ducked: return
	_ducked = value
	if is_instance_valid(game) and "audio" in game and is_instance_valid(game.audio) and game.audio.has_method("set_dialogue_active"):
		game.audio.set_dialogue_active(value)


func _exit_tree() -> void:
	_finish()


func _ending_allowed() -> bool:
	var ending := not active.is_empty() and bool(active.ending)
	if active.is_empty():
		for item in pending:
			ending = ending or bool(item.ending)
	if not ending or not is_instance_valid(game): return false
	# Paused end cards are distinct from the actual Pause/Audio menus.
	return "hud" in game and is_instance_valid(game.hud) and str(game.hud.overlay) in ["victory", "campaign_victory", "defeat"]


func _presentation_paused() -> bool:
	var cinematic=game.get("travel_cinematic") if is_instance_valid(game) else null
	return (get_tree().paused and not _ending_allowed()) or (is_instance_valid(cinematic) and cinematic.blocks_gameplay())


func _caption_visible() -> bool:
	if active.is_empty() or _presentation_paused(): return false
	# Online settings leave the shared match running. Keep live dialogue audio,
	# but never paint a subtitle across local settings or their buttons.
	if is_instance_valid(game) and "hud" in game and is_instance_valid(game.hud):
		return str(game.hud.overlay) in ["", "victory", "campaign_victory", "defeat"]
	return true


func _resolve_anchor(speaker_id: String, player_id: int) -> Node2D:
	if not is_instance_valid(game) or not "players" in game: return null
	var fallback: Node2D = null
	for player in game.players:
		if not is_instance_valid(player) or not player is Node2D: continue
		if speaker_id != "san" and str(player.get("character_id")) != speaker_id: continue
		if int(player.get("player_id")) == player_id: return player
		if fallback == null: fallback = player
	return fallback if player_id == 0 or speaker_id == "san" else null


func _radio_mode() -> bool:
	# Retained presentation diagnostic used by the dialogue previews and tests.
	return is_instance_valid(game) and "players" in game and game.players.size() > 1


func caption_layout() -> Dictionary:
	# Captions have a stable screen-edge home in solo and co-op. Long sentences
	# no longer grow a panel over the worker, furnace or nearest interaction.
	var viewport_size := get_viewport().get_visible_rect().size
	var scale_factor := minf(1.0,minf(viewport_size.x / 1440.0,viewport_size.y / 900.0))
	if is_instance_valid(game) and "hud" in game and is_instance_valid(game.hud) and "canvas" in game.hud and is_instance_valid(game.hud.canvas):
		scale_factor = game.hud.canvas.scale.x
	canvas.scale = Vector2.ONE * scale_factor
	var screen_size := viewport_size / scale_factor
	var ending := bool(active.get("ending",false))
	var width := minf(670.0 if ending else 430.0,screen_size.x - 36.0)
	var rows := UiArt.wrap_text(str(active.get("text","")),width - 32.0,15)
	var height := 37.0 + rows.size() * 21.0
	var at := Vector2((screen_size.x - width) * 0.5,screen_size.y - height - 24.0) if ending else Vector2(screen_size.x - width - 18.0,74.0)
	return {"rect":Rect2(at.round(),Vector2(width,height)),"rows":rows,"scale":scale_factor}


func _draw() -> void:
	if active.is_empty(): return
	var layout := caption_layout()
	var rect: Rect2 = layout.rect
	var rows: Array[String] = layout.rows
	var at := rect.position
	# Public bounds remain in physical canvas coordinates for collision checks.
	panel_bounds = Rect2(rect.position * float(layout.scale),rect.size * float(layout.scale))
	var alpha := minf(clampf(active_age / 0.13, 0.0, 1.0), clampf((active_duration - active_age) / 0.22, 0.0, 1.0))
	var accent := Catalog.speaker_color(str(active.speaker_id))
	accent.a = alpha
	canvas.draw_rect(rect,Color(0.065,0.083,0.074,0.92 * alpha))
	canvas.draw_rect(Rect2(at,Vector2(2,rect.size.y)),accent)
	UiArt.text(canvas,at + Vector2(16,20),Catalog.speaker_name(str(active.speaker_id)),12,accent)
	var color := UiArt.IVORY
	color.a = alpha
	for index in rows.size():
		UiArt.text(canvas,at + Vector2(16,43 + 21 * index),rows[index],15,color)
	# WorkerSpeechBubbles owns the comic cue for solo and cooperative actors.
