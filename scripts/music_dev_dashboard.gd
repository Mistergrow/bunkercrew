extends CanvasLayer
## An isolated, interactive music/dance lab. Real crew rigs share a preview
## mixer/clock; changing a theme or tempo never rewrites the running match.
signal closed
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Themes := preload("res://scripts/music_theme_catalog.gd")
const Genres := preload("res://scripts/music_genre_catalog.gd")
const L := preload("res://scripts/locale_text.gd")
const SAVE_PATH := "user://music-lab-feedback.json"
const MAX_JSON_BYTES := 16384
const GENRE_IDS := Genres.SELECTIONS

class PreviewClock extends Node:
	var session: Node
	var elapsed := 0.0
	var playing := true
	var config: Dictionary
	var state: Dictionary = {}
	func rhythm_frame() -> Dictionary:
		return state
	func advance(delta: float) -> void:
		if playing:
			elapsed += delta
		if is_instance_valid(session) and session.native_active:
			state = session.rhythm_frame()
			return
		var beats := elapsed * float(config.bpm) / 60.0
		var phase := fposmod(beats, 1.0)
		# Only the explicitly labelled silent developer preview supplies this
		# controlled kick fixture. Production reads audible native events above.
		state = {"active":playing,"phase":phase,"beat":floori(beats)%4,"bar":floori(beats/4.0),"audible_seconds":elapsed,"last_kick_seconds":floorf(beats)*60.0/float(config.bpm),"last_kick_strength":1.0 if playing else 0.0,"kick_count":floori(beats)+1,"beat_pulse":exp(-phase*6.0) if playing else 0.0,"accent_pulse":exp(-phase*6.0) if playing else 0.0,"motion_gain":0.22 if config.reduced_motion else 1.0,"dance_intensity":config.dance_intensity,"dance_profiles":config.dance_profiles,"genre":str(config.get("genre","minimal_techno"))}

class PreviewAudio extends Node:
	var live_music: PreviewClock

class PreviewWorld extends Node2D:
	var audio: PreviewAudio
	var actors: Array[Worker] = []
	var beat_state: Dictionary = {}
	func _draw() -> void:
		var columns := 4 if Dance.IDS.size()>6 else 6
		var rows := ceili(float(Dance.IDS.size())/columns)
		var stride := 1440.0/columns
		draw_rect(Rect2(0,0,1440,rows*310),Color("101b1e"))
		for index in Dance.IDS.size():
			var x := 12.0 + (index%columns)*stride
			var y := floori(float(index)/columns)*310.0
			var width := stride-24.0
			var spec := CharacterCatalog.data(Dance.IDS[index])
			var tint := Color(spec.accent)
			draw_rect(Rect2(x,y+16,width,275),Color("1b2829"))
			draw_rect(Rect2(x,y+16,width,3),tint)
			Art.text(self,Vector2(x+14,y+49),L.text(str(spec.title)),18,tint)
			draw_line(Vector2(x+12,y+254),Vector2(x+width-12,y+254),Color("63736b"),1)
			Art.text(self,Vector2(x+14,y+278),L.text("Schritte · sicherer Bodenkontakt"),11,Art.MUTED)
		for index in 4:
			var strength := float(beat_state.get("beat_pulse",0.0)) if int(beat_state.get("beat",-1)) == index else 0.0
			draw_rect(Rect2(676+index*24,rows*310-11,18,4),Color("586753").lerp(Art.AMBER,strength))

var configuration: Dictionary = {
	"version":2,"theme_id":"ash_foundry","seed":1207,"bpm":Themes.theme("ash_foundry").bpm,"music_intensity":2,"genre":"level_default",
	"dance_intensity":preload("res://scripts/audio_defaults.gd").DANCE_INTENSITY,"dance_profiles":Dance.defaults(),"reduced_motion":false,
}
var source_game: Node
var preview_world: PreviewWorld
var preview_clock: PreviewClock
var preview_session: Node
var styles: Dictionary = {}
var gains: Dictionary = {}
var gain_labels: Dictionary = {}
var theme_choice: OptionButton
var genre_choice: OptionButton
var tempo: SpinBox
var seed_value: SpinBox
var music_level: OptionButton
var dance_gain: HSlider
var reduced: CheckButton
var status: Label
var playing_button: Button
var apply_button: Button
var json_editor: TextEdit
var feedback: LineEdit
var feedback_dialog: Window
var interface_scroll: ScrollContainer
var profile_grid: GridContainer
var preview_container: SubViewportContainer
var preview_view: SubViewport
var _syncing := false
var _playing := true
var _previous_calibration_active := false
var _owns_calibration := false
var audition_enabled := true
var _closing := false

func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	_build_preview()
	_sync_controls()
	apply_button.visible = is_instance_valid(source_game) and is_instance_valid(source_game.get("audio"))
	_start_music()
	get_viewport().gui_focus_changed.connect(_focus_changed)
	theme_choice.grab_focus.call_deferred()

func show_for_game(game: Node) -> void:
	if _owns_calibration and source_game!=game:
		if is_instance_valid(source_game) and is_instance_valid(source_game.get("audio")):
			source_game.audio.calibration_active = _previous_calibration_active
		_owns_calibration = false
	source_game = game
	if is_instance_valid(game) and "audio" in game and is_instance_valid(game.audio):
		if not _owns_calibration: _previous_calibration_active = bool(game.audio.get("calibration_active"))
		game.audio.calibration_active = true
		_owns_calibration = true
		var music = game.audio.get("live_music")
		if is_instance_valid(music):
			configuration.dance_intensity = music.get("dance_intensity")
			configuration.dance_profiles = Dance.normalized_profiles(music.get("dance_profiles"))
			configuration.reduced_motion = bool(music.get("reduced_motion"))
			if "music_style" in game.audio:
				configuration.genre = str(game.audio.get("music_style"))
				configuration.bpm = Genres.apply(Themes.theme(configuration.theme_id),Genres.resolve(configuration.theme_id,configuration.genre)).bpm
	if is_node_ready():
		apply_button.visible = is_instance_valid(game) and is_instance_valid(game.get("audio"))
		_sync_controls()
		_start_music()

static func valid_configuration(value: Variant) -> bool:
	if not value is Dictionary or value.size() not in [9,10]:
		return false
	for key: String in ["version","theme_id","seed","bpm","music_intensity","dance_intensity","dance_profiles","reduced_motion"]:
		if not value.has(key):
			return false
	# JSON numbers are floats after parsing; require integral values explicitly.
	if (value.version != 1 and value.version != 2) or value.theme_id not in Themes.THEMES or value.get("genre","level_default") not in GENRE_IDS:
		return false
	for key: Variant in value:
		if key not in ["version","theme_id","seed","bpm","music_intensity","dance_intensity","dance_profiles","reduced_motion","feedback","genre"]:
			return false
	if not (value.seed is int or value.seed is float) or not is_finite(float(value.seed)) or float(value.seed) != floorf(float(value.seed)) or float(value.seed) < 0 or float(value.seed) > 2147483647:
		return false
	if not (value.bpm is int or value.bpm is float) or not is_finite(float(value.bpm)) or float(value.bpm) < 60.0 or float(value.bpm) > 160.0:
		return false
	if not (value.music_intensity is int or value.music_intensity is float) or float(value.music_intensity) != floorf(float(value.music_intensity)) or float(value.music_intensity) < 0 or float(value.music_intensity) > 3:
		return false
	return Dance.valid_intensity(value.dance_intensity) and Dance.valid_profiles(value.dance_profiles) and value.reduced_motion is bool and value.get("feedback") is String and value.feedback.length() <= 2000

func export_json() -> String:
	var payload := configuration.duplicate(true)
	payload.feedback = str(payload.get("feedback",""))
	return JSON.stringify(payload,"\t",true)

func import_json(text: String) -> bool:
	if text.to_utf8_buffer().size() > MAX_JSON_BYTES:
		return false
	var parsed: Variant = JSON.parse_string(text)
	if not valid_configuration(parsed):
		return false
	configuration = parsed.duplicate(true)
	configuration.version = 2
	configuration.genre = str(parsed.get("genre","level_default"))
	configuration.dance_profiles = Dance.normalized_profiles(configuration.dance_profiles)
	_sync_controls()
	_start_music()
	return true

func _label(text: String, parent: Node, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = L.text(text)
	label.add_theme_font_override("font",UiArt.FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",UiArt.IVORY)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = L.text(text)
	UiArt.button(button,14)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _choice(parent: Node, labels: Array) -> OptionButton:
	var choice := OptionButton.new()
	UiArt.button(choice,13)
	for text: String in labels:
		choice.add_item(L.text(text))
	parent.add_child(choice)
	return choice

func _slider(parent: Node, callback: Callable) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.5
	slider.step = 0.01
	slider.custom_minimum_size = Vector2(140,28)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.add_theme_stylebox_override("slider",UiArt.slider_track())
	slider.add_theme_stylebox_override("grabber_area",UiArt.slider_track(true))
	slider.add_theme_icon_override("grabber",UiArt.slider_handle())
	slider.add_theme_icon_override("grabber_highlight",UiArt.slider_handle())
	slider.value_changed.connect(callback)
	parent.add_child(slider)
	return slider

func _build_interface() -> void:
	var shell := Control.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shell)
	var background := ColorRect.new()
	background.color = Color("10191b")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_child(background)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","top","right","bottom"]:
		margins.add_theme_constant_override("margin_"+side,24)
	shell.add_child(margins)
	interface_scroll = ScrollContainer.new()
	interface_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margins.add_child(interface_scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",12)
	interface_scroll.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title := _label("Musik-Labor",header,28)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Zurück",header,close)
	_label("Eigene Hörprobe · echte Crew-Animationen · Einstellungen als Feedback teilen",body)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",18)
	body.add_child(controls)
	var theme_column := VBoxContainer.new()
	theme_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(theme_column)
	_label("Leitthema",theme_column)
	theme_choice = _choice(theme_column,Themes.THEMES.keys().map(func(id: String): return str(ScenarioCatalog.environment(id).get("title",id))))
	theme_choice.item_selected.connect(func(index: int):
		if _syncing: return
		configuration.theme_id = Themes.THEMES.keys()[index]
		configuration.bpm = Genres.apply(Themes.theme(configuration.theme_id),Genres.resolve(configuration.theme_id,configuration.genre)).bpm
		_sync_controls()
		_start_music())
	var tempo_column := VBoxContainer.new()
	controls.add_child(tempo_column)
	_label("Tempo · BPM",tempo_column)
	tempo = SpinBox.new()
	tempo.min_value = 60
	tempo.max_value = 160
	tempo.step = 1
	tempo.custom_minimum_size.x = 110
	tempo_column.add_child(tempo)
	tempo.value_changed.connect(func(value: float):
		if _syncing: return
		configuration.bpm = value
		_start_music())
	var seed_column := VBoxContainer.new()
	controls.add_child(seed_column)
	_label("Musik-Seed",seed_column)
	seed_value = SpinBox.new()
	seed_value.min_value = 0
	seed_value.max_value = 2147483647
	seed_value.step = 1
	seed_value.custom_minimum_size.x = 140
	seed_column.add_child(seed_value)
	seed_value.value_changed.connect(func(value: float):
		if _syncing: return
		configuration.seed = int(value)
		_start_music())
	var intensity_column := VBoxContainer.new()
	controls.add_child(intensity_column)
	_label("Musikspannung",intensity_column)
	music_level = _choice(intensity_column,["Ruhe","Aufbau","Angriff","Höhepunkt"])
	music_level.item_selected.connect(func(index: int):
		configuration.music_intensity = index
		if is_instance_valid(preview_session): preview_session.set_preview_intensity(index))
	var genre_column := VBoxContainer.new()
	controls.add_child(genre_column)
	_label("Musikstil",genre_column)
	genre_choice = _choice(genre_column,GENRE_IDS.map(func(id: String): return Genres.selection_label(id)))
	genre_choice.custom_minimum_size.x = 180
	genre_choice.item_selected.connect(func(index: int):
		if _syncing: return
		configuration.genre = GENRE_IDS[index]
		configuration.bpm = Genres.apply(Themes.theme(configuration.theme_id),Genres.resolve(configuration.theme_id,configuration.genre)).bpm
		_sync_controls()
		_start_music())
	var preview_columns := 4 if Dance.IDS.size()>6 else 6
	var preview_height := ceili(float(Dance.IDS.size())/preview_columns)*310
	preview_container = SubViewportContainer.new()
	preview_container.custom_minimum_size = Vector2(0,preview_height)
	preview_container.stretch = true
	preview_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(preview_container)
	preview_view = SubViewport.new()
	preview_view.name = "CrewPreview"
	preview_view.size = Vector2i(1440,preview_height)
	preview_view.world_2d = World2D.new()
	preview_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	preview_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	preview_container.add_child(preview_view)
	preview_world = PreviewWorld.new()
	preview_world.set_meta("dance_preview",true)
	preview_view.add_child(preview_world)
	profile_grid = GridContainer.new()
	profile_grid.columns = preview_columns
	profile_grid.add_theme_constant_override("h_separation",16)
	profile_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(profile_grid)
	for id: String in Dance.IDS:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		profile_grid.add_child(column)
		_label(str(CharacterCatalog.data(id).title),column,17)
		var offered: Array[String] = Dance.styles_for(id)
		var move_labels: Array[String] = []
		for style: String in offered:
			var move_title := L.text(Dance.label(style))
			if not Dance.owner(style).is_empty(): move_title = L.format("%s · Stufe %d",[move_title,Dance.required_level(style)])
			move_labels.append(move_title)
		var choice := _choice(column,move_labels)
		for index in offered.size(): choice.set_item_metadata(index,offered[index])
		choice.item_selected.connect(func(index: int):
			if _syncing: return
			configuration.dance_profiles[id].style = str(choice.get_item_metadata(index))
			_update_dance())
		styles[id] = choice
		gains[id] = _slider(column,func(value: float):
			if _syncing: return
			configuration.dance_profiles[id].intensity = value
			gain_labels[id].text = "%d %%" % roundi(value*100)
			_update_dance())
		gain_labels[id] = _label("100 %",column)
	var global_controls := HBoxContainer.new()
	global_controls.add_theme_constant_override("separation",18)
	body.add_child(global_controls)
	_label("Gesamte Tanzintensität",global_controls)
	dance_gain = _slider(global_controls,func(value: float):
		if _syncing: return
		configuration.dance_intensity = value
		_update_dance())
	reduced = CheckButton.new()
	reduced.text = L.text("Taktbewegung reduzieren")
	UiArt.button(reduced,13)
	global_controls.add_child(reduced)
	reduced.toggled.connect(func(value: bool):
		if _syncing: return
		configuration.reduced_motion = value
		_update_dance())
	var actions := HBoxContainer.new()
	feedback = LineEdit.new()
	feedback.placeholder_text = L.text("Feedback zur Musik und zu den Bewegungen")
	feedback.max_length = 2000
	feedback.text_changed.connect(func(value: String): configuration.feedback = value)
	body.add_child(feedback)
	actions.add_theme_constant_override("separation",16)
	body.add_child(actions)
	playing_button = _button("Hörprobe stoppen",actions,_toggle_playing)
	apply_button = _button("Tanz im Spiel übernehmen",actions,_apply_to_game)
	apply_button.visible = false
	_button("JSON kopieren",actions,_copy_feedback)
	_button("Feedback speichern",actions,_save_feedback)
	_button("JSON importieren",actions,_show_import)
	status = _label("",body)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview_container.resized.connect(func():
		var preview_size := preview_container.size
		var preview_scale := preview_size.x/1440.0
		preview_container.custom_minimum_size.y = roundf(preview_height*preview_scale)
		preview_view.canvas_transform = Transform2D(0.0,Vector2.ONE*preview_scale,0.0,Vector2.ZERO)
		profile_grid.columns = (2 if Dance.IDS.size()>6 else 3) if preview_size.x<1120 else preview_columns)

func _focus_changed(control: Control) -> void:
	if is_instance_valid(interface_scroll) and is_instance_valid(control) and interface_scroll.is_ancestor_of(control):
		interface_scroll.ensure_control_visible(control)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		_freeze(child)

func _build_preview() -> void:
	preview_clock = PreviewClock.new()
	preview_clock.config = configuration
	add_child(preview_clock)
	preview_world.audio = PreviewAudio.new()
	preview_world.audio.live_music = preview_clock
	preview_world.add_child(preview_world.audio)
	for index in Dance.IDS.size():
		var actor := Worker.new()
		actor.character_id = Dance.IDS[index]
		actor.game = preview_world
		var columns := 4 if Dance.IDS.size()>6 else 6
		actor.position = Vector2((index%columns+.5)*1440.0/columns,254+floori(float(index)/columns)*310)
		actor.scale = Vector2.ONE*2.5
		preview_world.add_child(actor)
		actor.remove_from_group("players")
		var visual := WorkerVisual.new()
		visual.name = "PixelVisual"
		actor.add_child(visual)
		_freeze(actor)
		visual.idle_clock.wait_remaining = 10000
		visual._identity.hide()
		preview_world.actors.append(actor)
	var runtime = load("res://scripts/live_music.gd")
	preview_session = runtime.new()
	preview_session.name = "IsolatedMusicPreview"
	preview_session.automatic_processing = true
	preview_session.publish_shader_pulse = false
	preview_session.process_priority = -100
	add_child(preview_session)
	preview_session.set_mix_level_db(0.0)
	preview_clock.session = preview_session

func _start_music() -> void:
	if not is_instance_valid(preview_session): return
	preview_session.end_session()
	preview_clock.elapsed = 0.0
	preview_clock.config = configuration
	if not audition_enabled:
		_playing = false
		preview_clock.playing = false
		_update_dance()
		playing_button.text = L.text("Hörprobe starten")
		status.text = ""
		return
	preview_clock.playing = _playing
	var native: bool = preview_session.start_preview(str(configuration.theme_id),int(configuration.seed),float(configuration.bpm),int(configuration.music_intensity),str(configuration.get("genre","level_default")))
	preview_session.set_paused(not _playing)
	_update_dance()
	status.text = L.text("Native Hörprobe · Takt aus dem Audio-Mixer") if native else L.text("Native Musik nicht verfügbar · kontrollierte, stumme Animationsvorschau")

func _update_dance() -> void:
	preview_clock.config = configuration
	if is_instance_valid(preview_session):
		preview_session.set_dance_configuration(float(configuration.dance_intensity),configuration.dance_profiles)
		preview_session.set_rhythm_motion_reduced(bool(configuration.reduced_motion))

func _sync_controls() -> void:
	if not is_instance_valid(theme_choice): return
	_syncing = true
	theme_choice.select(Themes.THEMES.keys().find(configuration.theme_id))
	genre_choice.select(GENRE_IDS.find(str(configuration.get("genre","level_default"))))
	tempo.value = configuration.bpm
	seed_value.value = configuration.seed
	music_level.select(int(configuration.music_intensity))
	dance_gain.value = configuration.dance_intensity
	feedback.text = str(configuration.get("feedback",""))
	reduced.button_pressed = configuration.reduced_motion
	for id: String in Dance.IDS:
		var selected_style := str(configuration.dance_profiles[id].style)
		var selected_index := -1
		var choice: OptionButton = styles[id]
		for index in choice.item_count:
			if str(choice.get_item_metadata(index))==selected_style: selected_index = index
		# Older feedback may name one of the original thirteen styles. Keep
		# that selection available without exposing other characters' moves.
		if selected_index<0 and Dance.allowed(id,selected_style,10,true):
			selected_index = choice.item_count
			choice.add_item(L.text(Dance.label(selected_style)))
			choice.set_item_metadata(selected_index,selected_style)
		choice.select(maxi(0,selected_index))
		gains[id].value = configuration.dance_profiles[id].intensity
		gain_labels[id].text = "%d %%" % roundi(float(configuration.dance_profiles[id].intensity)*100)
	_syncing = false

func _toggle_playing() -> void:
	if not audition_enabled:
		audition_enabled = true
		_playing = true
		_start_music()
		playing_button.text = L.text("Hörprobe stoppen")
		return
	_playing = not _playing
	preview_clock.playing = _playing
	preview_session.set_paused(not _playing)
	playing_button.text = L.text("Hörprobe stoppen" if _playing else "Hörprobe starten")

func _copy_feedback() -> void:
	DisplayServer.clipboard_set(export_json())
	status.text = L.text("Einstellungen kopiert · diesen JSON-Text im Chat teilen")

func _apply_to_game() -> void:
	if not is_instance_valid(source_game) or not is_instance_valid(source_game.get("audio")):
		return
	source_game.audio.set_dance_configuration(float(configuration.dance_intensity),configuration.dance_profiles)
	source_game.audio.set_rhythm_motion_reduced(bool(configuration.reduced_motion))
	if source_game.audio.has_method("set_music_style"):
		source_game.audio.set_music_style(str(configuration.get("genre","level_default")))
	status.text = L.text("Tanzstile und Intensität übernommen")

func _save_feedback() -> void:
	var file := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if file == null:
		status.text = L.text("Feedback konnte nicht gespeichert werden")
		return
	file.store_string(export_json())
	status.text = L.format("Feedback gespeichert: %s",[ProjectSettings.globalize_path(SAVE_PATH)])

func _show_import() -> void:
	if is_instance_valid(feedback_dialog):
		feedback_dialog.popup_centered(Vector2i(720,470))
		return
	feedback_dialog = Window.new()
	feedback_dialog.title = L.text("Musik-Labor · JSON importieren")
	feedback_dialog.size = Vector2i(720,470)
	feedback_dialog.unresizable = false
	feedback_dialog.close_requested.connect(feedback_dialog.hide)
	add_child(feedback_dialog)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left","top","right","bottom"]:
		margin.add_theme_constant_override("margin_"+side,18)
	feedback_dialog.add_child(margin)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_label("Gespeicherte Einstellungen hier einfügen",box)
	json_editor = TextEdit.new()
	json_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	json_editor.text = export_json()
	box.add_child(json_editor)
	_button("Importieren",box,func():
		if import_json(json_editor.text):
			feedback_dialog.hide()
			status.text = L.text("Einstellungen importiert")
		else:
			status.text = L.text("Ungültiges Feedback · Einstellungen unverändert"))
	feedback_dialog.popup_centered(Vector2i(720,470))

func _process(delta: float) -> void:
	if not is_instance_valid(preview_world) or not is_instance_valid(preview_clock): return
	preview_clock.advance(delta)
	preview_world.beat_state = preview_clock.state
	for actor in preview_world.actors:
		actor.get_node("PixelVisual")._process(delta)
	preview_world.queue_redraw()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func close() -> void:
	if _closing or is_queued_for_deletion(): return
	_closing = true
	set_process(false)
	set_process_unhandled_key_input(false)
	_release_audio()
	closed.emit()
	queue_free()

func _release_audio() -> void:
	if is_instance_valid(preview_session):
		preview_session.end_session()
	if _owns_calibration and is_instance_valid(source_game) and is_instance_valid(source_game.get("audio")):
		source_game.audio.calibration_active = _previous_calibration_active
	_owns_calibration = false

func _exit_tree() -> void:
	_release_audio()
