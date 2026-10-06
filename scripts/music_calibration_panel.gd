extends Control
## Audible metronome and robust tapping; no microphone or gameplay timing writes.
signal closed
const Calibration := preload("res://scripts/music_calibration.gd")
const L := preload("res://scripts/locale_text.gd")
const BPM := 100.0
const RATE := 48000
const BEATS := 48
var audio: Node
var calibration := Calibration.new()
var player: AudioStreamPlayer
var start_button: Button
var close_button: Button
var apply_button: Button
var tap_button: Button
var started := false
var last_position := 0.0
var loops := 0
var time_seconds := 0.0
var _audible_transport := -INF
var _previous_calibration_active := false
var _owns_calibration := false
var _closing := false

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	mouse_filter=Control.MOUSE_FILTER_STOP
	size=Vector2(1440,900)
	_previous_calibration_active=audio.calibration_active
	audio.calibration_active=true
	_owns_calibration=true
	player=AudioStreamPlayer.new()
	player.bus="Music"
	player.stream=_metronome()
	add_child(player)
	start_button=_button("START",Rect2(339,349,350,44),_start)
	tap_button=_button("TIPPEN  [LEERTASTE]",Rect2(735,349,350,44),_tap)
	tap_button.disabled=true
	apply_button=_button("AUSGLEICH ÜBERNEHMEN",Rect2(339,636,470,44),_apply)
	apply_button.disabled=true
	close_button=_button("ZURÜCK",Rect2(839,636,246,44),close)
	start_button.grab_focus.call_deferred()

func _button(title: String,rect: Rect2,callback: Callable) -> Button:
	var button:=Button.new()
	button.text=L.text(title);button.position=rect.position;button.size=rect.size
	UiArt.button(button,13);button.pressed.connect(callback);add_child(button)
	return button

func _metronome() -> AudioStreamWAV:
	var period := 60.0/BPM
	var samples := roundi(period*BEATS*RATE)
	var data:=PackedByteArray()
	data.resize(samples*2)
	for beat in BEATS:
		var offset:=roundi(beat*period*RATE)
		for index in roundi(.055*RATE):
			var t:=float(index)/RATE
			var value:=sin(TAU*(880.0 if beat%4==0 else 660.0)*t)*exp(-t/0.010)*.45
			data.encode_s16((offset+index)*2,roundi(value*32767.0))
	var stream:=AudioStreamWAV.new()
	stream.format=AudioStreamWAV.FORMAT_16_BITS;stream.mix_rate=RATE
	stream.data=data;stream.loop_mode=AudioStreamWAV.LOOP_FORWARD;stream.loop_end=samples
	return stream

func _start() -> void:
	if audio.music_volume<=0.0: return
	calibration.begin(BPM)
	loops=0;last_position=0.0;time_seconds=0.0
	_audible_transport=-INF
	player.play();started=true;tap_button.disabled=false;apply_button.disabled=true
	tap_button.grab_focus()

func _tap() -> void:
	if started: calibration.tap(time_seconds)

func _apply() -> void:
	var result:=calibration.result()
	if not result.ready or result.count<15: return
	audio.set_music_calibration(float(result.seconds))
	close()

func close() -> void:
	if _closing or is_queued_for_deletion(): return
	_closing=true
	set_process(false)
	set_process_input(false)
	_release_audio()
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("audio_settings"):
		if not event.is_echo(): close()
		get_viewport().set_input_as_handled()
	elif started and event is InputEventKey and event.keycode==KEY_SPACE:
		# Tap on key-down before a focused Button can consume Space or wait
		# for key-up. Key repeat must not produce extra calibration samples.
		if event.pressed and not event.echo: _tap()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if started and player.has_stream_playback():
		var playback := player.get_stream_playback()
		var playback_position := 0.0
		var decoder_loops := 0
		var since_mix := 0.0
		for attempt in 3:
			var mix_before := AudioServer.get_time_since_last_mix()
			var loops_before := playback.get_loop_count()
			playback_position = player.get_playback_position()
			decoder_loops = playback.get_loop_count()
			since_mix = maxf(AudioServer.get_time_since_last_mix(),0.0)
			if loops_before==decoder_loops and since_mix>=mix_before: break
		var length := (60.0/BPM)*BEATS
		if decoder_loops>0:
			loops=decoder_loops
		elif playback_position<last_position-length*.5:
			# Some WAV backends expose position wrapping but no loop counter.
			loops+=1
		last_position=playback_position
		var output_seconds := playback_position+loops*length+since_mix-maxf(AudioServer.get_output_latency(),0.0)
		_audible_transport=maxf(_audible_transport,output_seconds)
		time_seconds=_audible_transport
		var result:=calibration.result()
		apply_button.disabled=not result.ready or result.count<15
	queue_redraw()

func _draw() -> void:
	UiArt.panel(self,Rect2(270,125,900,650))
	UiArt.text(self,Vector2(305,179),"TAKT ABSTIMMEN",26)
	UiArt.text(self,Vector2(339,242),"Höre den Klick und tippe mindestens 15-mal im Takt.",16)
	UiArt.text(self,Vector2(339,273),"Nutze dabei die Kopfhörer oder Lautsprecher, mit denen du spielst.",13,UiArt.MUTED)
	UiArt.text(self,Vector2(339,304),"Richte dich nach dem Ton. Der Kreis zeigt die bisherige Bildzeit.",13,UiArt.MUTED)
	var pulse:=exp(-fposmod(maxf(time_seconds,0.0),60.0/BPM)/.09) if started else 0.0
	draw_circle(Vector2(712,469),29+5*pulse,UiArt.AMBER.lerp(UiArt.STEEL,.65-.25*pulse))
	var result:=calibration.result()
	UiArt.text(self,Vector2(339,548),L.format("Takteingaben: %d / 15",result.count),16)
	if result.count>0:
		UiArt.text(self,Vector2(339,582),L.format("Ausgleich: %d ms · Streuung: %d ms",[roundi(result.seconds*1000),roundi(result.jitter*1000)]),13,UiArt.MUTED)
	if audio.music_volume<=0.0: UiArt.text(self,Vector2(339,613),"Erhöhe zuerst die Musiklautstärke.",13,UiArt.AMBER)
	elif result.count>=15 and not result.ready: UiArt.text(self,Vector2(339,613),"Tippe weiter gleichmäßig oder starte erneut.",13,UiArt.AMBER)

func _release_audio() -> void:
	if is_instance_valid(player): player.stop();player.stream=null
	if _owns_calibration and is_instance_valid(audio): audio.calibration_active=_previous_calibration_active
	_owns_calibration=false
	started=false

func _exit_tree() -> void:
	_release_audio()
