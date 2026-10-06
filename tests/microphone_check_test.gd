extends SceneTree
const Backend := preload("res://scripts/microphone_check.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class FakeInput:
	extends Backend
	var hardware := PackedStringArray(["Default","Test microphone"])
	var opened := 0
	var closed := 0
	var available := true
	func _input_devices() -> PackedStringArray: return hardware.duplicate()
	func _open_input() -> bool:
		opened += 1
		sample_rate = 8000
		return available
	func _close_input() -> void: closed += 1
	func _read_input() -> PackedVector2Array: return PackedVector2Array()
var checks := 0
var failures := 0
var sent := 0
var packet := PackedFloat32Array()
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	print("MIC %s: %s" % ["PASS" if value else "FAIL",label])
	if not value: failures += 1
func frames(value: float,count: int=400) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(count)
	result.fill(Vector2(value,value))
	return result
func run() -> void:
	var mic := FakeInput.new()
	root.add_child(mic)
	mic.set_process(false)
	mic.samples_ready.connect(func(_owner: String,samples: PackedFloat32Array,_rate: int):
		sent += 1
		packet = samples)
	check(not mic.capturing and mic.opened==0 and mic.active_owner.is_empty(),"Ready never opens input")
	check(not mic.acquire("unknown") and not mic.start_recording(),"Only known explicit owners may activate; inactive recording rejected")
	check(mic.acquire("check") and mic.capturing and mic.opened==1,"Explicit check activation opens input once")
	check(mic.acquire("check") and mic.opened==1,"Repeated acquisition is idempotent")
	check(not mic.acquire("voice"),"Check excludes voice owner")
	mic.release("voice")
	check(mic.capturing and mic.active_owner=="check","Other owner cannot close check input")
	mic._consume_frames(frames(.25))
	check(is_equal_approx(mic.rms,.25) and is_equal_approx(mic.peak,.25) and not mic.clipping,"Deterministic mono RMS and peak are correct")
	check(sent==0,"Local meter samples never emit voice data")
	mic.set_input_gain(2.0)
	mic._consume_frames(frames(.6))
	check(mic.clipping and is_equal_approx(mic.rms,1.0) and is_equal_approx(mic.peak,1.0),"Gain detects clipping before output clamp")
	mic._process(.9)
	check(not mic.clipping,"Clipping indication expires after held warning")
	mic.set_input_gain(NAN)
	check(mic.input_gain==2.0,"Nonfinite gain is rejected")
	mic.set_input_gain(100)
	check(mic.input_gain==4.0,"Gain is bounded")
	mic.set_input_gain(1)
	check(mic.start_recording(),"Explicit record starts only during local check")
	for chunk in 12: mic._consume_frames(frames(.2,4096))
	check(not mic.recording and mic._samples.size()==40000 and mic.recorded_seconds==5.0,"Recording stops at exactly five seconds and fixed memory bound")
	check(sent==0,"Entire recorded sample remains outside voice callbacks")
	check(mic.play_recording() and mic.playing and not mic.capturing,"Playback closes the input before output starts")
	check(not mic.acquire("voice") and not mic.acquire("check"),"Playback excludes all microphone acquisition")
	check(mic._playback.stream is AudioStreamWAV and mic._playback.stream.data.size()==80000,"Playback uses bounded mono PCM in RAM")
	var retired_playback: WeakRef = weakref(mic._playback.get_stream_playback())
	mic.stop_playback()
	check(not mic.playing and mic.active_owner.is_empty() and mic._samples.size()==40000,"Stopping playback keeps only the local sample")
	mic.release("check")
	check(mic._samples.is_empty() and mic.recorded_seconds==0,"Leaving a finished probe erases its RAM buffer")
	check(mic.acquire("voice"),"Voice acquires only after explicit check releases")
	mic._consume_frames(frames(.3))
	check(sent==1 and packet.size()==400 and is_equal_approx(packet[0],.3),"Voice receives gain-adjusted bounded mono frames")
	check(not mic.start_recording(),"Voice cannot populate the local probe")
	mic._consume_frames(frames(NAN))
	check(sent==2 and packet[0]==0.0,"Nonfinite input is replaced with silence")
	mic.release("check")
	check(mic.capturing,"Closing local panel cannot interrupt another owner")
	mic.release("voice")
	check(not mic.capturing and mic.active_owner.is_empty(),"Voice release closes input")
	mic.acquire("check")
	mic.start_recording()
	mic._consume_frames(frames(.25))
	check(mic.set_device("Test microphone") and not mic.capturing and mic._samples.is_empty(),"Device change stops capture and erases the old sample")
	check(not mic.set_device("missing"),"Unknown device rejected")
	mic.acquire("check")
	mic.hardware=PackedStringArray(["Default"])
	mic._refresh_devices()
	check(not mic.capturing and mic.selected_device=="Default" and mic.status.contains("erneut"),"Hotplug stops ownership and requires explicit reactivation")
	mic.acquire("check")
	mic._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not mic.capturing and mic.active_owner.is_empty(),"Application focus loss immediately closes microphone")
	mic.acquire("check")
	mic.start_recording()
	mic._process(5.1)
	check(not mic.recording and mic._samples.is_empty(),"Stalled input also stops recording after five seconds")
	mic.release("check")
	mic.available=false
	check(not mic.acquire("check") and not mic.capturing,"Unavailable input reports failure without claiming ownership")
	await Cleanup.free_scene(mic,self)
	var deadline := Time.get_ticks_msec()+3000
	while retired_playback.get_ref()!=null and Time.get_ticks_msec()<deadline: await process_frame
	check(retired_playback.get_ref()==null,"Mixer releases stopped in-memory playback")
	print("Microphone backend: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
