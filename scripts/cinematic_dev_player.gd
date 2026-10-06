extends CanvasLayer
## Isolated director's player for existing production cinematics. No save,
## campaign, matchmaking, vehicle or gameplay input is created by this tool.
signal closed
const L := preload("res://scripts/locale_text.gd")
const TravelCatalog := preload("res://scripts/travel_cinematic_catalog.gd")
const TravelSound := preload("res://scripts/travel_cinematic_sound.gd")
const AirCatalog := preload("res://scripts/air_raid_intro_catalog.gd")
const PreviewWorld := preload("res://scripts/cinematic_preview_world.gd")
const Focus := preload("res://scripts/ui_focus_navigation.gd")
const SCENES: Array[String] = ["signal","storm","supply","air_raid"]
const DESTINATIONS := {"signal":"harbor","storm":"mountain_pass","supply":"quarry"}
const SPEEDS: Array[float] = [.25,.5,1.0,2.0]

var source_game: Node
var scene_id := "signal"
var character_id := "mara"
var environment_id := "abandoned_harbor"
var elapsed := 0.0
var duration := 7.5
var speed := 1.0
var playing := false
var muted := false
var subtitles := true
var reduced := false
var context: Dictionary = {}
var shell: Control
var scene_choice: OptionButton
var character_choice: OptionButton
var environment_choice: OptionButton
var speed_choice: OptionButton
var timeline: HSlider
var time_label: Label
var play_button: Button
var restart_button: Button
var close_button: Button
var mute_button: CheckButton
var subtitle_button: CheckButton
var reduced_button: CheckButton
var preview_container: SubViewportContainer
var preview_view: SubViewport
var preview_world: Control
var voice: AudioStreamPlayer
var air_flyover: AudioStreamPlayer
var travel_sound: Node
var _labels: Array[Label] = []
var _environment_ids: Array[String] = []
var _character_ids: Array[String] = []
var _syncing := false
var _closed := false
var _voice_consumed := false
var _source_audio: WeakRef
var _source_was_processing := false
var _music_states: Array[Dictionary] = []
var _source_live_music: WeakRef
var _source_live_paused := false
var _opener: WeakRef
var _focus_signature := ""
var voice_starts := 0

func show_for_game(game: Node) -> void:
	if source_game==game and _source_audio!=null: return
	_release_source_music()
	source_game=game
	if not is_instance_valid(game): return
	if game.get("started") == true: return
	var chosen: Variant=game.get("selected_characters")
	if chosen is Array and not chosen.is_empty() and CharacterCatalog.contains(str(chosen[0])):
		character_id=str(chosen[0])
	var weather: Node=game.get("weather")
	if is_instance_valid(weather): reduced=bool(weather.get("reduced_effects"))
	var audio: Node=game.get("audio")
	if not is_instance_valid(audio): return
	_source_audio=weakref(audio)
	_source_was_processing=audio.is_processing()
	audio.set_process(false)
	var players: Array=[]
	var decks: Variant=audio.get("music_players")
	if decks is Array: players.append_array(decks)
	var menu: Node=audio.get("menu_music")
	if is_instance_valid(menu): players.append(menu.get("player"))
	var live: Node=audio.get("live_music")
	if is_instance_valid(live):
		_source_live_music=weakref(live)
		_source_live_paused=bool(live.get("_paused"))
		players.append(live.get("player"))
	for player: Variant in players:
		if player is AudioStreamPlayer:
			_music_states.append({"player":weakref(player),"paused":player.stream_paused})
			player.stream_paused=true
	if is_instance_valid(live): live.call("set_paused",true)
	if is_inside_tree(): _refresh_context()

func _ready() -> void:
	name="CinematicDevPlayer"
	layer=80
	process_mode=Node.PROCESS_MODE_ALWAYS
	var opener_control:=get_viewport().gui_get_focus_owner()
	if is_instance_valid(opener_control): _opener=weakref(opener_control)
	_build_interface()
	_build_audio()
	_refresh_context()
	_refresh_locale()
	var localization:=get_node_or_null("/root/Localization")
	if localization!=null: localization.locale_changed.connect(_locale_changed)
	get_viewport().size_changed.connect(_layout_preview)
	play_button.grab_focus.call_deferred()

func _label(message: String,parent: Node,font_size: int=16) -> Label:
	var label:=Label.new()
	label.text=L.text(message)
	label.set_meta("cinematic_message",message)
	label.add_theme_font_override("font",UiArt.MENU_FONT if font_size>=22 else UiArt.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",UiArt.IVORY if font_size>=22 else UiArt.MUTED)
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	_labels.append(label)
	return label

func _button(message: String,parent: Node,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=L.text(message)
	button.set_meta("cinematic_message",message)
	SocialUiArt.button(button,17,"",10)
	button.custom_minimum_size.y=38
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _choice(parent: Node,message: String) -> OptionButton:
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",2)
	parent.add_child(column)
	_label(message,column)
	var choice:=OptionButton.new()
	UiArt.button(choice,16)
	choice.custom_minimum_size.y=38
	choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	choice.fit_to_longest_item=false
	column.add_child(choice)
	return choice

func _check_button(message: String,parent: Node,callback: Callable) -> CheckButton:
	var button:=CheckButton.new()
	button.text=L.text(message)
	button.set_meta("cinematic_message",message)
	UiArt.button(button,15)
	button.toggled.connect(callback)
	parent.add_child(button)
	return button

func _build_interface() -> void:
	shell=Control.new()
	shell.mouse_filter=Control.MOUSE_FILTER_STOP
	shell.mouse_force_pass_scroll_events=false
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	var background:=ColorRect.new()
	background.color=Color("10191b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shell.add_child(background)
	var margin:=MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,18)
	shell.add_child(margin)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	margin.add_child(body)
	var header:=HBoxContainer.new()
	body.add_child(header)
	var title:=_label("Sequenz-Studio",header,28)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	close_button=_button("Zurück · Esc",header,close)
	_label("Zwischensequenzen ansehen · ohne Spielstand oder laufende Runde zu verändern",body,14)
	var selection:=HBoxContainer.new()
	selection.add_theme_constant_override("separation",12)
	body.add_child(selection)
	scene_choice=_choice(selection,"Sequenz")
	scene_choice.item_selected.connect(func(index: int):
		if not _syncing: select_scene(SCENES[index]))
	character_choice=_choice(selection,"Figur")
	character_choice.item_selected.connect(func(index: int):
		if _syncing: return
		character_id=_character_ids[index]
		_refresh_context(true))
	environment_choice=_choice(selection,"Schauplatz")
	environment_choice.item_selected.connect(func(index: int):
		if _syncing: return
		environment_id=_environment_ids[index]
		_refresh_context())
	var aspect:=AspectRatioContainer.new()
	aspect.ratio=1.6
	aspect.stretch_mode=AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical=Control.SIZE_EXPAND_FILL
	aspect.custom_minimum_size.y=220
	body.add_child(aspect)
	preview_container=SubViewportContainer.new()
	preview_container.stretch=true
	preview_container.mouse_filter=Control.MOUSE_FILTER_IGNORE
	aspect.add_child(preview_container)
	preview_view=SubViewport.new()
	preview_view.name="IsolatedCinematicViewport"
	preview_view.size=Vector2i(1440,900)
	preview_view.size_2d_override=Vector2i(1440,900)
	preview_view.size_2d_override_stretch=true
	preview_view.world_2d=World2D.new()
	preview_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	preview_view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	preview_container.add_child(preview_view)
	preview_world=PreviewWorld.new()
	preview_view.add_child(preview_world)
	var clock_row:=HBoxContainer.new()
	clock_row.add_theme_constant_override("separation",14)
	body.add_child(clock_row)
	timeline=HSlider.new()
	timeline.custom_minimum_size=Vector2(0,32)
	timeline.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	timeline.min_value=0.0
	timeline.max_value=duration
	timeline.step=.01
	timeline.add_theme_stylebox_override("slider",UiArt.slider_track())
	timeline.add_theme_stylebox_override("grabber_area",UiArt.slider_track(true))
	timeline.add_theme_icon_override("grabber",UiArt.slider_handle())
	timeline.add_theme_icon_override("grabber_highlight",UiArt.slider_handle())
	timeline.value_changed.connect(func(value: float):
		if not _syncing: seek(value))
	clock_row.add_child(timeline)
	time_label=_label("",clock_row,16)
	time_label.custom_minimum_size.x=144
	time_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",12)
	body.add_child(actions)
	play_button=_button("Abspielen",actions,func(): set_playing(not playing))
	play_button.custom_minimum_size.x=125
	restart_button=_button("Von vorn",actions,restart)
	restart_button.custom_minimum_size.x=110
	var speed_column:=HBoxContainer.new()
	var spacer:=Control.new()
	spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	actions.add_child(speed_column)
	_label("Tempo",speed_column,15)
	speed_choice=OptionButton.new()
	UiArt.button(speed_choice,16)
	speed_choice.custom_minimum_size=Vector2(90,38)
	for value: float in SPEEDS: speed_choice.add_item(str(value)+"×")
	speed_choice.select(2)
	speed_choice.item_selected.connect(func(index: int): set_speed(SPEEDS[index]))
	speed_column.add_child(speed_choice)
	mute_button=_check_button("Stumm",actions,set_muted)
	subtitle_button=_check_button("Untertitel",actions,func(value: bool):
		subtitles=value
		_present())
	subtitle_button.set_pressed_no_signal(true)
	reduced_button=_check_button("Ruhige Effekte",actions,func(value: bool):
		reduced=value
		_present())
	reduced_button.set_pressed_no_signal(reduced)
	var hint:=_label("Die Zeitleiste pausiert und bleibt stumm. Abspielen setzt Bild und Ton ab dieser Stelle fort.",body,14)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	preview_container.resized.connect(_layout_preview)

func _build_audio() -> void:
	voice=AudioStreamPlayer.new()
	voice.name="CinematicPreviewVoice"
	voice.bus=&"Voice"
	add_child(voice)
	air_flyover=AudioStreamPlayer.new()
	air_flyover.name="CinematicPreviewFlyover"
	air_flyover.bus=&"SFX"
	var loop:=load("res://assets/audio/air_raid_flyover_v1.wav") as AudioStreamWAV
	if loop!=null:
		loop=loop.duplicate()
		loop.loop_mode=AudioStreamWAV.LOOP_FORWARD
		loop.loop_begin=0
		loop.loop_end=roundi(loop.get_length()*loop.mix_rate)
		air_flyover.stream=loop
	add_child(air_flyover)
	travel_sound=TravelSound.new()
	add_child(travel_sound)

func select_scene(id: String) -> bool:
	if id not in SCENES or _closed: return false
	scene_id=id
	_stop_audio()
	elapsed=0.0
	playing=false
	_voice_consumed=false
	_refresh_context()
	_refresh_locale()
	return true

func _refresh_context(replace_voice: bool=false) -> void:
	if not is_instance_valid(preview_world): return
	if scene_id=="air_raid":
		context={"id":"air_raid","title":L.text("LUFTKONTAKT"),"duration":8.0,"environment":environment_id,"character_id":character_id,"dialogue":AirCatalog.line(character_id)}
	else:
		context=TravelCatalog.context(str(DESTINATIONS[scene_id]),character_id,[character_id])
		context.environment=environment_id
	duration=float(context.get("duration",8.0))
	elapsed=clampf(elapsed,0,duration)
	if replace_voice:
		voice.stop()
		if playing: _play_voice_at(elapsed)
	if is_instance_valid(travel_sound) and scene_id!="air_raid":
		travel_sound.call("begin_sequence",scene_id,elapsed,muted)
		travel_sound.call("set_speed",speed)
		travel_sound.call("update_sequence",scene_id,elapsed,playing,false)
	_present()
	_sync_controls()

func _refresh_locale() -> void:
	_syncing=true
	for label: Label in _labels:
		var message:=str(label.get_meta("cinematic_message",""))
		if not message.is_empty(): label.text=L.text(message)
	for button: BaseButton in [play_button,restart_button,close_button,mute_button,subtitle_button,reduced_button]:
		button.text=L.text(str(button.get_meta("cinematic_message","")))
	scene_choice.clear()
	for id: String in SCENES:
		scene_choice.add_item(L.text("LUFTKONTAKT") if id=="air_raid" else L.text(str(TravelCatalog.VIGNETTES[id].title)))
	scene_choice.select(SCENES.find(scene_id))
	_character_ids.clear()
	character_choice.clear()
	for definition: Dictionary in CharacterCatalog.CHARACTERS:
		var id:=str(definition.id)
		_character_ids.append(id)
		character_choice.add_item(str(CharacterCatalog.data(id).title))
	character_choice.select(_character_ids.find(character_id))
	_environment_ids.clear()
	environment_choice.clear()
	for definition: Dictionary in ScenarioCatalog.environments(true):
		_environment_ids.append(str(definition.id))
		environment_choice.add_item(str(definition.title))
	environment_choice.select(_environment_ids.find(environment_id))
	_syncing=false
	_sync_controls()

func _locale_changed(_locale: String) -> void:
	_refresh_context(true)
	_refresh_locale()

func seek(seconds: float) -> void:
	if not is_finite(seconds) or _closed: return
	playing=false
	_stop_audio(false)
	elapsed=clampf(seconds,0,duration)
	_voice_consumed=elapsed>=_voice_at()
	if is_instance_valid(travel_sound): travel_sound.call("seek",elapsed)
	_present()
	_sync_controls()

func set_playing(value: bool) -> void:
	if _closed or playing==value: return
	if value and elapsed>=duration:
		restart()
		return
	playing=value
	if value:
		if voice.has_stream_playback(): voice.stream_paused=false
		else: _play_voice_at(elapsed)
		if scene_id=="air_raid" and air_flyover.stream!=null:
			if air_flyover.has_stream_playback(): air_flyover.stream_paused=false
			else: air_flyover.play(fposmod(elapsed,maxf(air_flyover.stream.get_length(),.01)))
	else:
		voice.stream_paused=true
		air_flyover.stream_paused=true
	if is_instance_valid(travel_sound) and scene_id!="air_raid":
		travel_sound.call("update_sequence",scene_id,elapsed,playing,false)
	_sync_controls()

func restart() -> void:
	if _closed: return
	_stop_audio()
	elapsed=0.0
	playing=false
	_voice_consumed=false
	if is_instance_valid(travel_sound) and scene_id!="air_raid":
		travel_sound.call("begin_sequence",scene_id,0.0,muted)
		travel_sound.call("set_speed",speed)
	set_playing(true)
	_present()

func set_speed(value: float) -> bool:
	if value not in SPEEDS or _closed: return false
	speed=value
	if is_instance_valid(voice): voice.pitch_scale=speed
	if is_instance_valid(air_flyover): air_flyover.pitch_scale=speed
	if is_instance_valid(travel_sound): travel_sound.call("set_speed",speed)
	_sync_controls()
	return true

func set_muted(value: bool) -> void:
	muted=value
	if is_instance_valid(voice): voice.volume_db=-80.0 if muted else 0.0
	if is_instance_valid(travel_sound): travel_sound.call("set_muted",muted)
	_update_flyover_level()

func _voice_at() -> float:
	return 1.15 if scene_id=="air_raid" else TravelCatalog.VOICE_AT

func _play_voice_at(seconds: float) -> void:
	if not playing or seconds<_voice_at(): return
	_voice_consumed=true
	var path:=str(context.get("dialogue",{}).get("voice_path",""))
	if path.is_empty(): return
	var stream:=load(path) as AudioStream
	var voice_offset:=seconds-_voice_at()
	if stream==null or voice_offset>=stream.get_length(): return
	voice.stream=stream
	voice.pitch_scale=speed
	voice.volume_db=-80.0 if muted else 0.0
	voice.stream_paused=false
	voice.play(voice_offset)
	voice_starts+=1

func advance(delta: float) -> void:
	if not playing or _closed or not is_finite(delta) or delta<=0.0: return
	elapsed=minf(duration,elapsed+delta*speed)
	if not _voice_consumed and elapsed>=_voice_at(): _play_voice_at(elapsed)
	if is_instance_valid(travel_sound) and scene_id!="air_raid":
		travel_sound.call("set_dialogue_active",voice.playing and not muted)
		travel_sound.call("update_sequence",scene_id,elapsed,true,false)
	_update_flyover_level()
	_present()
	_sync_controls()
	if elapsed>=duration:
		playing=false
		_stop_audio()
		_sync_controls()

func _process(delta: float) -> void:
	_poll_source_bus_layout()
	advance(delta)
	_wire_focus()

func _poll_source_bus_layout() -> void:
	# Keeping the original score decoder paused must not disable authored
	# bus-effect hot reload while the director listens to the preview.
	if _source_audio==null: return
	var audio: Variant=_source_audio.get_ref()
	if not is_instance_valid(audio): return
	var mix: Variant=audio.get("bus_mix")
	if mix!=null and mix.has_method("poll") and bool(mix.call("poll")):
		for bus: String in ["Music","SFX","Voice"]:
			audio.call("_apply_bus_volume",bus,float(audio.get(bus.to_lower()+"_volume")))

func _update_flyover_level() -> void:
	if not is_instance_valid(air_flyover): return
	var fade:=smoothstep(0.0,.6,elapsed)*(1.0-smoothstep(duration-.7,duration,elapsed))
	air_flyover.volume_db=-80.0 if muted else linear_to_db(maxf(.0001,fade))-9.0-(4.0 if voice.playing else 0.0)

func _present() -> void:
	if is_instance_valid(preview_world) and not context.is_empty(): preview_world.present(context,elapsed,subtitles,reduced)

func _sync_controls() -> void:
	if not is_instance_valid(timeline): return
	_syncing=true
	timeline.max_value=duration
	timeline.set_value_no_signal(elapsed)
	time_label.text=L.format("%05.2f / %05.2f s",[elapsed,duration])
	play_button.text=L.text("Pause" if playing else "Abspielen")
	mute_button.set_pressed_no_signal(muted)
	subtitle_button.set_pressed_no_signal(subtitles)
	reduced_button.set_pressed_no_signal(reduced)
	speed_choice.select(SPEEDS.find(speed))
	_syncing=false

func _layout_preview() -> void:
	_focus_signature=""

func _wire_focus() -> void:
	if not is_instance_valid(shell): return
	var candidates: Array[Control]=[close_button,scene_choice,character_choice,environment_choice,timeline,play_button,restart_button,speed_choice,mute_button,subtitle_button,reduced_button]
	var available:=Focus.available(shell,candidates)
	var signature:=Focus.signature(available)
	if signature==_focus_signature: return
	_focus_signature=signature
	Focus.wire(available)

func _input(event: InputEvent) -> void:
	if _closed or event.is_echo(): return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("audio_settings"):
		for choice: OptionButton in [scene_choice,character_choice,environment_choice,speed_choice]:
			if choice.get_popup().visible:
				choice.get_popup().hide()
				get_viewport().set_input_as_handled()
				return
		close()
		get_viewport().set_input_as_handled()
		return
	for action: String in ["friends","restart","upgrades","personnel","achievements","help","join","skip_build","audio_settings","weather_toggle","story_journal"]:
		if InputMap.has_action(action) and event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(_event: InputEvent) -> void:
	# Native controls receive input first; nothing below this modal may react.
	get_viewport().set_input_as_handled()

func _stop_audio(stop_travel: bool=true) -> void:
	if is_instance_valid(voice): voice.stop(); voice.stream=null
	if is_instance_valid(air_flyover): air_flyover.stop()
	if stop_travel and is_instance_valid(travel_sound): travel_sound.call("stop")

func _release_source_music() -> void:
	if _source_live_music!=null:
		var live: Variant=_source_live_music.get_ref()
		if is_instance_valid(live): live.call("set_paused",_source_live_paused)
	_source_live_music=null
	# Preserve raw source flags last: another owner may deliberately pause a
	# stream independently of its native clock's paused state.
	for state: Dictionary in _music_states:
		var player: Variant=state.player.get_ref()
		if is_instance_valid(player): player.stream_paused=bool(state.paused)
	_music_states.clear()
	if _source_audio!=null:
		var audio: Variant=_source_audio.get_ref()
		if is_instance_valid(audio) and not audio.is_queued_for_deletion(): audio.set_process(_source_was_processing)
	_source_audio=null

func close() -> void:
	if _closed or is_queued_for_deletion(): return
	_closed=true
	playing=false
	set_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	_stop_audio()
	_release_source_music()
	if is_instance_valid(shell): shell.hide()
	closed.emit()
	if _opener!=null:
		var opener_control: Variant=_opener.get_ref()
		if is_instance_valid(opener_control) and opener_control.is_visible_in_tree(): opener_control.grab_focus.call_deferred()
	queue_free()

func _exit_tree() -> void:
	_stop_audio()
	_release_source_music()
