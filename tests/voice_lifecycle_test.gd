extends SceneTree
## No physical microphone is opened. The real key state, voice controller and
## generator run against an exclusive synthetic microphone with focused window.
const Voice := preload("res://scripts/voice_chat.gd")
const Mic := preload("res://tests/microphone_check_test.gd").FakeInput
const Codec := preload("res://scripts/voice_codec.gd")
class NetProbe extends Node:
	var active := true
	var is_host := false
	var peer_connected := true
	@warning_ignore("unused_private_class_variable")
	var _authenticated := true # Read by the real Voice controller.
	var state := "playing"
	var _generation := 0
class HudProbe extends Node:
	var overlay := ""
class GameProbe extends Node:
	var network: NetProbe
	var microphone: Node
	var hud: HudProbe
class VoiceProbe extends Voice:
	var focused := true
	func _window_focused() -> bool: return focused
var checks := 0
var failures := 0
var game: GameProbe
var voice: VoiceProbe
var pcm := PackedByteArray()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS ",label)
	else:
		failures += 1
		push_error(label)
func key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode=KEY_V
	event.physical_keycode=KEY_V
	event.pressed=pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func arm_and_press() -> void:
	key(false)
	voice._process(.016)
	key(true)
	voice._process(.016)
func speech(sequence: int) -> Dictionary:
	return {"kind":"voice","generation":game.network._generation,"seq":sequence,"rate":Codec.RATE,"pcm":pcm}
func wall_wait(seconds: float) -> void:
	var until := Time.get_ticks_usec()+roundi(seconds*1000000.0)
	while Time.get_ticks_usec()<until: await process_frame

func run() -> void:
	# The test runner supplies isolated XDG data. Malformed saved values must
	# not stop initialization before the player/capture signals are constructed.
	var config := ConfigFile.new()
	config.set_value("voice","enabled",1)
	config.set_value("voice","muted",[true])
	config.set_value("voice","output",NAN)
	config.save("user://voice.cfg")
	game=GameProbe.new()
	root.add_child(game)
	game.network=NetProbe.new()
	game.hud=HudProbe.new()
	game.microphone=Mic.new()
	game.add_child(game.network)
	game.add_child(game.hud)
	game.add_child(game.microphone)
	game.microphone.set_process(false)
	voice=VoiceProbe.new()
	voice.game=game
	game.add_child(voice)
	voice.set_process(false)
	pcm.resize(Codec.BYTES)
	check(not voice.enabled and not voice.remote_muted and voice.output_volume==Voice.Defaults.PARTNER_VOLUME and is_instance_valid(voice._player), "No-profile diagnostics ignore malformed saved voice values and complete initialization with current defaults")
	voice.set_enabled(true)
	arm_and_press()
	check(Input.is_physical_key_pressed(KEY_V) and voice.speaking and game.microphone.capturing, "Explicit V press acquires synthetic exclusive voice capture")
	var opens: int=game.microphone.opened
	game.microphone.hardware=PackedStringArray(["Default"])
	game.microphone._refresh_devices()
	voice._process(.016)
	voice._process(.016)
	check(not voice.speaking and not game.microphone.capturing and game.microphone.opened==opens and not voice._ptt_armed, "Device loss cannot reopen a fallback microphone while V remains held")
	arm_and_press()
	check(voice.speaking and game.microphone.opened==opens+1, "Releasing and deliberately pressing V permits capture after device loss")
	opens=game.microphone.opened
	game.network.peer_connected=false
	voice._process(.016)
	game.network.peer_connected=true
	voice._process(.016)
	check(not voice.speaking and not game.microphone.capturing and game.microphone.opened==opens, "Reconnect never reuses a held PTT press")
	arm_and_press()
	opens=game.microphone.opened
	game.network._generation+=1
	voice._process(.016)
	check(not voice.speaking and game.microphone.opened==opens, "A new match generation requires a new PTT press")
	arm_and_press()
	opens=game.microphone.opened
	voice.focused=false
	voice._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	voice._process(.016)
	voice.focused=true
	voice._process(.016)
	check(not voice.speaking and not game.microphone.capturing and game.microphone.opened==opens, "Focus return while V is held cannot reactivate capture")
	arm_and_press()
	check(voice.speaking, "PTT works again after a real release following focus loss")
	game.hud.overlay="audio"
	voice._process(.016)
	game.hud.overlay=""
	voice._process(.016)
	check(not voice.speaking and not voice._ptt_armed, "Closing a blocking settings menu with V held does not open input")
	var edit := LineEdit.new()
	root.add_child(edit)
	edit.grab_focus()
	arm_and_press()
	check(not voice.speaking and get_root().gui_get_focus_owner()==edit, "Typing V in a focused text field cannot transmit")
	edit.release_focus()
	edit.queue_free()
	key(false)
	voice._process(.016)
	check(game.microphone.acquire("check"), "Local microphone check acquires exclusive ownership")
	arm_and_press()
	check(not voice.speaking and game.microphone.active_owner=="check", "PTT cannot steal capture from the local check")
	game.microphone.release("check")
	voice._process(.016)
	check(not voice.speaking, "Ending a local check does not activate a still-held PTT key")
	arm_and_press()
	check(voice.speaking, "A fresh press can acquire input after the check has ended")
	key(false)
	voice._process(.016)
	voice.reset()
	for sequence in [1,2,3]: voice.receive(speech(sequence))
	voice._pump()
	voice.receive(speech(5))
	voice._pump()
	check(voice._expected==4 and voice.lost_frames==0 and voice._buffered_samples()>=Codec.FRAMES, "A future packet waits while earlier audio remains buffered")
	check(voice.receive(speech(4)), "A briefly reordered predecessor still enters the running jitter buffer")
	voice._pump()
	check(voice._expected==6 and voice.played_frames==5 and voice.lost_frames==0, "Ongoing reordered speech plays in order without artificial concealment")
	voice.receive(speech(7))
	await wall_wait(.16)
	voice._clock+=.16
	voice._pump()
	check(voice.lost_frames==1 and voice._expected==8, "A genuinely missing frame is concealed when the real generator buffer drains")
	voice._clock+=30.0
	check(voice.receive(speech(2500)) and voice._expected==2500 and voice._queue.size()==1 and voice._buffered_samples()==0, "A gap over one thousand frames resynchronizes without seconds of queued silence")
	voice.reset()
	for sequence in [3000,3001,3002]: voice.receive(speech(sequence))
	voice._pump()
	var bounded := true
	for sequence in range(3003,3020):
		voice.receive(speech(sequence))
		var pending_samples := maxi(0,voice._highest-voice._expected+1)*Codec.FRAMES
		bounded=voice._buffered_samples()+pending_samples<=Codec.FRAMES*voice.MAX_QUEUE and bounded
	check(bounded and voice._queue.size()<=voice.MAX_QUEUE, "Native buffered audio plus pending packet span never exceed 200 ms")
	voice.reset()
	key(false)
	game.queue_free()
	await wall_wait(.2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://voice.cfg"))
	print("Voice lifecycle: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
