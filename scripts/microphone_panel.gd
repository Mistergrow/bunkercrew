extends Control
## Local input diagnostics. Opening this panel never activates the microphone.
const L := preload("res://scripts/locale_text.gd")
var game
var hud
var microphone
var device_select: OptionButton
var activate_button: Button
var record_button: Button
var record_stop_button: Button
var playback_button: Button
var gain_slider: HSlider
var partner_slider: HSlider
var voice_toggle: CheckButton
var mute_toggle: CheckButton
var _device_names := PackedStringArray()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1440,900)
	microphone = game.microphone
	device_select = OptionButton.new()
	device_select.position = Vector2(270,191)
	device_select.size = Vector2(602,42)
	device_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	UiArt.button(device_select,13)
	device_select.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	device_select.item_selected.connect(_choose_device)
	add_child(device_select)
	activate_button = _button("Mikrofon aktivieren",Rect2(892,191,280,42),_toggle_capture)
	gain_slider = _slider(Rect2(270,280,766,30),0.25,4.0,0.05,microphone.input_gain,microphone.set_input_gain)
	record_button = _button("5-Sekunden-Probe aufnehmen",Rect2(270,466,340,44),_record)
	record_stop_button = _button("Aufnahme stoppen",Rect2(622,466,250,44),microphone.stop_recording)
	playback_button = _button("Probe anhören",Rect2(884,466,288,44),_play)
	voice_toggle = CheckButton.new()
	voice_toggle.position = Vector2(270,563)
	voice_toggle.size = Vector2(460,42)
	UiArt.button(voice_toggle,14)
	voice_toggle.toggled.connect(func(value: bool):
		if _voice_available(): game.voice.set_enabled(value))
	add_child(voice_toggle)
	mute_toggle = CheckButton.new()
	mute_toggle.position = Vector2(802,563)
	mute_toggle.size = Vector2(370,42)
	UiArt.button(mute_toggle,13)
	mute_toggle.toggled.connect(func(value: bool):
		if _voice_available(): game.voice.set_remote_muted(value))
	add_child(mute_toggle)
	partner_slider = _slider(Rect2(492,673,680,30),0.0,1.0,0.01,1.0,func(value: float):
		if _voice_available(): game.voice.set_output_volume(value))
	_button("ZURÜCK  [ESC / F4]",Rect2(270,763,902,42),hud._close_microphone)
	microphone.devices_changed.connect(_refresh_devices)
	_refresh_devices()
	refresh_locale()
	device_select.grab_focus.call_deferred()

func _voice_available() -> bool:
	return "voice" in game and is_instance_valid(game.voice)

func close() -> void:
	if is_instance_valid(microphone): microphone.release("check")

func _exit_tree() -> void:
	close()

func _process(_delta: float) -> void:
	activate_button.text = L.text("Mikrofon ausschalten" if microphone.capturing else "Mikrofon aktivieren")
	activate_button.disabled = microphone.playing or (not microphone.active_owner.is_empty() and microphone.active_owner != "check") or _device_names.is_empty()
	record_button.disabled = not microphone.capturing or microphone.active_owner != "check" or microphone.recording
	record_stop_button.disabled = not microphone.recording
	playback_button.disabled = microphone.recorded_seconds <= 0.0 or microphone.recording
	playback_button.text = L.text("Wiedergabe stoppen" if microphone.playing else "Probe anhören")
	device_select.disabled = microphone.playing
	voice_toggle.disabled = not _voice_available()
	mute_toggle.disabled = not _voice_available()
	partner_slider.editable = _voice_available()
	if _voice_available():
		voice_toggle.set_pressed_no_signal(game.voice.enabled)
		mute_toggle.set_pressed_no_signal(game.voice.remote_muted)
		if not partner_slider.has_focus(): partner_slider.set_value_no_signal(game.voice.output_volume)
	queue_redraw()

func _toggle_capture() -> void:
	if microphone.capturing: microphone.release("check")
	else: microphone.acquire("check")

func _record() -> void:
	microphone.start_recording()

func _play() -> void:
	if microphone.playing: microphone.stop_playback()
	else: microphone.play_recording()

func _choose_device(index: int) -> void:
	if index >= 0 and index < _device_names.size(): microphone.set_device(_device_names[index])

func _refresh_devices() -> void:
	_device_names = microphone.devices()
	device_select.clear()
	for index in _device_names.size():
		var title: String = L.text("Systemstandard") if _device_names[index] == "Default" else _device_names[index]
		device_select.add_item(title)
		if _device_names[index] == microphone.selected_device: device_select.select(index)
	if _device_names.is_empty(): device_select.add_item(L.text("Kein Eingabegerät"))

func refresh_locale() -> void:
	_refresh_devices()
	voice_toggle.text = L.text("Koop-Sprachchat aktivieren")
	mute_toggle.text = L.text("Partner stummschalten")
	activate_button.tooltip_text = L.text("Nur nach diesem Klick wird dein Mikrofon geöffnet.")
	gain_slider.tooltip_text = L.text("Verstärkung für Mikrofontest und Sprachchat. Bei Übersteuerung reduzieren.")
	record_button.tooltip_text = L.text("Diese Probe bleibt auf deinem Rechner und wird nicht an den Partner gesendet.")
	queue_redraw()

func _draw() -> void:
	UiArt.panel(self,Rect2(230,68,982,774),true)
	UiArt.text(self,Vector2(270,119),"Mikrofon & Sprachchat",27)
	UiArt.text(self,Vector2(270,150),"Gerät wählen, bewusst aktivieren und in normaler Lautstärke sprechen.",12,UiArt.MUTED)
	UiArt.text(self,Vector2(270,180),"Eingabegerät",12,UiArt.MUTED)
	UiArt.text(self,Vector2(270,267),"Eingangsverstärkung",14)
	UiArt.text(self,Vector2(1076,301),L.format("%.2f ×",microphone.input_gain),16,UiArt.AMBER)
	UiArt.text(self,Vector2(270,344),"Eingangspegel",14)
	var meter := Rect2(270,358,902,24)
	draw_rect(meter,Color("111a1d"))
	var level := clampf((linear_to_db(maxf(microphone.rms,0.001))+60.0)/60.0,0.0,1.0)
	var maximum := clampf((linear_to_db(maxf(microphone.peak,0.001))+60.0)/60.0,0.0,1.0)
	for index in 50:
		var color := UiArt.GREEN if index < 37 else (UiArt.AMBER if index < 46 else UiArt.RED)
		color.a = 1.0 if index/50.0 < level else 0.12
		draw_rect(Rect2(meter.position+Vector2(index*18+1,2),Vector2(15,20)),color)
	if microphone.capturing:
		draw_rect(Rect2(meter.position+Vector2(round(maximum*898),0),Vector2(3,24)),UiArt.IVORY)
	UiArt.text(self,Vector2(270,407),L.format("RMS %+.1f dBFS · Spitze %+.1f dBFS",[linear_to_db(maxf(microphone.rms,0.001)),linear_to_db(maxf(microphone.peak,0.001))]),12,UiArt.MUTED)
	var level_hint := "Übersteuert · Verstärkung reduzieren" if microphone.clipping else ("Pegel gut" if microphone.rms >= 0.035 else "Sprich etwas lauter oder näher")
	if not microphone.capturing: level_hint = "Eingang geschlossen"
	UiArt.text(self,Vector2(790,407),level_hint,12,UiArt.RED if microphone.clipping else UiArt.GREEN)
	UiArt.text(self,Vector2(270,440),microphone.status,12,UiArt.AMBER if microphone.capturing else UiArt.MUTED)
	UiArt.text(self,Vector2(270,533),L.format("Probe: %.1f / 5,0 Sekunden",microphone.recorded_seconds),12,UiArt.MUTED)
	UiArt.divider(self,Vector2(270,546),Vector2(1172,546))
	UiArt.text(self,Vector2(270,631),"V halten zum Sprechen · im Online-Raum, im Spiel und in der Pause",12,UiArt.MUTED)
	UiArt.text(self,Vector2(270,658),"Andere Menüs und Texteingaben sperren V · Kopfhörer verhindern Rückkopplungen.",11,UiArt.MUTED)
	UiArt.text(self,Vector2(270,695),"Partnerlautstärke",13)
	UiArt.text(self,Vector2(270,738),"Probe nur im Arbeitsspeicher · beim Verlassen gelöscht · keine automatische Aufnahme",11,UiArt.MUTED)

func _button(title: String,rect: Rect2,callback: Callable) -> Button:
	var control := Button.new()
	control.text = title
	control.position = rect.position
	control.size = rect.size
	UiArt.button(control,13)
	control.pressed.connect(callback)
	add_child(control)
	return control

func _slider(rect: Rect2,minimum: float,maximum: float,step: float,value: float,callback: Callable) -> HSlider:
	var control := HSlider.new()
	control.position = rect.position
	control.size = rect.size
	control.min_value = minimum
	control.max_value = maximum
	control.step = step
	control.value = value
	control.add_theme_stylebox_override("slider",UiArt.slider_track())
	control.add_theme_stylebox_override("grabber_area",UiArt.slider_track(true))
	control.add_theme_stylebox_override("grabber_area_highlight",UiArt.slider_track(true))
	for style in ["grabber","grabber_highlight","grabber_disabled"]: control.add_theme_icon_override(style,UiArt.slider_handle())
	control.value_changed.connect(callback)
	add_child(control)
	return control
