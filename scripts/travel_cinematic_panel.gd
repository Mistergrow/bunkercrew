extends Control
## A full scene at a safe road boundary, with its own bounded voice/effect pool.
const Catalog := preload("res://scripts/travel_cinematic_catalog.gd")
const CinematicArt := preload("res://scripts/travel_cinematic_art.gd")
const CinematicSound := preload("res://scripts/travel_cinematic_sound.gd")
const REFERENCE := Vector2(1440,900)
var game: Node
var hud: Node
var scene_root: Node2D
var art_canvas: Node2D
var shade_canvas: Node2D
var title_label: Label
var speaker_label: Label
var caption_label: Label
var guest_hint: Label
var skip_button: Button
var voice: AudioStreamPlayer
# First bounded cue voice remains available to existing diagnostics.
var effect: AudioStreamPlayer
var cinematic_sound: Node
var _context: Dictionary = {}
var _vehicle_id := 0
var _clock := 0.0
var _voice_started := false
var _ducked := false
var _reduced := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	z_index=100
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_STOP
	mouse_force_pass_scroll_events=false
	hide()
	scene_root=Node2D.new()
	add_child(scene_root)
	art_canvas=Node2D.new()
	art_canvas.draw.connect(func(): CinematicArt.draw(art_canvas,_context,_clock,_reduced))
	scene_root.add_child(art_canvas)
	shade_canvas=Node2D.new()
	shade_canvas.draw.connect(_draw_shade)
	scene_root.add_child(shade_canvas)
	title_label=_label(29,UiArt.IVORY,Vector2(62,47),Vector2(1316,55))
	speaker_label=_label(20,UiArt.AMBER,Vector2(92,719),Vector2(1256,32))
	caption_label=_label(24,UiArt.IVORY,Vector2(92,759),Vector2(1256,78))
	caption_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	guest_hint=_label(16,UiArt.MUTED,Vector2(790,852),Vector2(580,35))
	guest_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	skip_button=Button.new()
	skip_button.position=Vector2(1100,842)
	skip_button.size=Vector2(285,42)
	skip_button.flat=true
	skip_button.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	skip_button.add_theme_font_override("font",UiArt.MENU_FONT)
	skip_button.add_theme_font_size_override("font_size",18)
	for state: String in ["normal","hover","pressed","disabled"]: skip_button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	skip_button.add_theme_color_override("font_color",UiArt.MUTED)
	skip_button.add_theme_color_override("font_hover_color",UiArt.IVORY)
	skip_button.pressed.connect(func(): game.travel_cinematic.request_skip())
	scene_root.add_child(skip_button)
	voice=AudioStreamPlayer.new()
	voice.bus=&"Voice"
	add_child(voice)
	cinematic_sound=CinematicSound.new()
	add_child(cinematic_sound)
	effect=cinematic_sound.cue_voices[0]
	tree_exiting.connect(_stop)

func _label(font_size: int,tint: Color,at: Vector2,extent: Vector2) -> Label:
	var label:=Label.new()
	label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	label.position=at
	label.size=extent
	label.add_theme_font_override("font",UiArt.MENU_FONT)
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",tint)
	label.add_theme_color_override("font_shadow_color",Color("0b1415"))
	label.add_theme_constant_override("shadow_offset_x",1)
	label.add_theme_constant_override("shadow_offset_y",2)
	scene_root.add_child(label)
	return label

func _process(delta: float) -> void:
	refresh(delta)

func refresh(_delta: float) -> void:
	var controller=game.get("travel_cinematic") if is_instance_valid(game) else null
	var truck=controller.source_vehicle() if is_instance_valid(controller) else null
	if not is_instance_valid(truck) or controller.context().is_empty():
		if _vehicle_id!=0: _stop()
		hide()
		return
	_clock=controller.elapsed()
	if _vehicle_id!=truck.get_instance_id():
		_stop()
		_vehicle_id=truck.get_instance_id()
		_context=controller.context().duplicate(true)
		# Late snapshots display their real point, without restarting old sounds.
		_voice_started=_clock>Catalog.VOICE_AT+.12
		cinematic_sound.begin_sequence(str(_context.id),_clock)
	visible=controller.is_presented()
	voice.stream_paused=not visible
	_set_ducked(visible and voice.playing)
	if not visible:
		# A local menu/loading overlay may hide a cue while the host clock runs.
		# Consume that cue; only an already playing paused voice may resume.
		if _clock>=Catalog.VOICE_AT: _voice_started=true
		cinematic_sound.update_sequence(str(_context.id),_clock,false)
		return
	var bounds: Rect2=hud.screen_rect()
	position=bounds.position
	size=bounds.size
	var fit:=minf(size.x/REFERENCE.x,size.y/REFERENCE.y)
	scene_root.scale=Vector2.ONE*fit
	scene_root.position=(size-REFERENCE*fit)*.5
	_reduced=is_instance_valid(game.weather) and game.weather.reduced_effects
	# Spoken subtitles remain in the recording's language for this short scene;
	# title and controls may translate without ever mismatching audible speech.
	title_label.text=str(controller.context().title)
	speaker_label.text=str(_context.dialogue.speaker_name)
	speaker_label.add_theme_color_override("font_color",_context.dialogue.accent)
	caption_label.text=str(_context.dialogue.text) if _clock>=Catalog.VOICE_AT else ""
	speaker_label.visible=not caption_label.text.is_empty()
	skip_button.visible=controller.can_skip()
	skip_button.text=LocaleText.text("Überspringen · Enter / Esc")
	var room=game.get("network")
	guest_hint.visible=is_instance_valid(room) and room.active and not room.is_host
	guest_hint.text=LocaleText.text("Der Gastgeber kann die Szene überspringen.")
	if not _voice_started and _clock>=Catalog.VOICE_AT:
		_voice_started=true
		if not str(_context.dialogue.voice_path).is_empty():
			voice.stream=load(str(_context.dialogue.voice_path)) as AudioStream
			voice.play()
			_set_ducked(true)
	cinematic_sound.update_sequence(str(_context.id),_clock,true)
	art_canvas.queue_redraw()
	shade_canvas.queue_redraw()
	queue_redraw()

func _set_ducked(enabled: bool) -> void:
	if enabled==_ducked: return
	_ducked=enabled
	if is_instance_valid(cinematic_sound): cinematic_sound.set_dialogue_active(enabled)
	if is_instance_valid(game) and is_instance_valid(game.audio): game.audio.set_dialogue_active(enabled,"travel_intro")

func _stop() -> void:
	if is_instance_valid(voice): voice.stop(); voice.stream=null
	if is_instance_valid(cinematic_sound): cinematic_sound.stop_with_fade()
	_set_ducked(false)
	_vehicle_id=0
	_context={}
	if is_instance_valid(skip_button) and skip_button.is_inside_tree(): skip_button.release_focus()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("0b1112"))

func _draw_shade() -> void:
	shade_canvas.draw_polygon(PackedVector2Array([Vector2(0,682),Vector2(1440,682),Vector2(1440,900),Vector2(0,900)]),PackedColorArray([Color(0,0,0,0),Color(0,0,0,0),Color(.025,.045,.045,.88),Color(.025,.045,.045,.88)]))
