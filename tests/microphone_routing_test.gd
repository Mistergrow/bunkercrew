extends SceneTree
## Only opens the dedicated synthetic source created by microphone_routing_test.py.
const Backend := preload("res://scripts/microphone_check.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const DEVICE := "lastshift_test_microphone"
var checks := 0
var failures := 0
var master_capture: AudioEffectCapture
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	print("MIC ROUTING %s: %s" % ["PASS" if value else "FAIL",label])
	if not value: failures += 1
func output_rms() -> float:
	var count := master_capture.get_frames_available()
	if count==0: return 0.0
	var frames := master_capture.get_buffer(count)
	var energy := 0.0
	for frame in frames: energy += (frame.x*frame.x+frame.y*frame.y)*0.5
	return sqrt(energy/frames.size())
func run() -> void:
	if "--synthetic-device" not in OS.get_cmdline_user_args() or AudioServer.get_driver_name()!="PulseAudio" or DEVICE not in AudioServer.get_input_device_list():
		push_error("Run the Python driver: it creates a private synthetic source and a silent output sink.")
		quit(2)
		return
	var mic := Backend.new()
	root.add_child(mic)
	var buses_before := AudioServer.bus_count
	check(not mic.capturing and AudioServer.bus_count==buses_before,"No microphone bus or input opens before activation")
	check(mic.set_device(DEVICE),"Exact isolated synthetic source selected; no default microphone fallback")
	master_capture=AudioEffectCapture.new()
	master_capture.buffer_length=2.0
	var master := AudioServer.get_bus_index("Master")
	var effect_index := AudioServer.get_bus_effect_count(master)
	AudioServer.add_bus_effect(master,master_capture)
	check(mic.acquire("check"),"Real PulseAudio microphone stream acquires synthetic source")
	await create_timer(.7).timeout
	var measured := mic.rms
	print("Synthetic input RMS: ",measured," sample_rate=",mic.sample_rate," selected=",AudioServer.input_device)
	check(AudioServer.input_device==DEVICE,"Driver confirms the chosen device rather than the silent default source")
	check(measured>.03 and measured<.6,"Actual microphone/capture pipeline receives the known tone")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index(mic._bus_name)),"Input bus is muted to prevent direct monitoring")
	var monitor_leak := output_rms()
	print("Master while capturing: ",monitor_leak)
	check(monitor_leak<.0001,"Synthetic microphone signal never reaches the speaker mix during capture")
	mic.start_recording()
	await create_timer(1.0).timeout
	mic.stop_recording()
	check(mic.recorded_seconds>.65 and mic.recorded_seconds<=1.2,"Real timed input fills only the bounded local RAM sample")
	master_capture.clear_buffer()
	check(mic.play_recording() and not mic._input.playing and not mic.capturing,"Playback physically stops input player before sound output")
	var playback_ref: WeakRef=weakref(mic._playback.get_stream_playback())
	await create_timer(.35).timeout
	var played := output_rms()
	print("Master during local playback: ",played)
	check(played>.015,"Recorded synthetic probe reaches playback mix at limited volume")
	mic.release("check")
	await create_timer(.2).timeout
	output_rms()
	await create_timer(.2).timeout
	check(output_rms()<.0001 and mic._samples.is_empty(),"Exit silences playback and erases probe memory")
	AudioServer.remove_bus_effect(master,effect_index)
	await Cleanup.free_scene(mic,self)
	var deadline := Time.get_ticks_msec()+3000
	while playback_ref.get_ref()!=null and Time.get_ticks_msec()<deadline: await process_frame
	check(AudioServer.bus_count==buses_before,"Microphone bus is removed during teardown")
	print("Microphone audio routing: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
