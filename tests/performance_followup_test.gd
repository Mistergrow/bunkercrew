extends SceneTree
const Microphone := preload("res://scripts/microphone_check.gd")
var checks := 0
var failures := 0
class FocusProbe extends Node2D:
	var prompts := 0
	func prompt(_worker: Node) -> String:
		prompts+=1
		return "Fixture interaction description"
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
func run() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(3,{"environment":"sector07","build_type":"workshop","position":"left"})
	game.rounds.set_process(false)
	game.medic.set_physics_process(false)
	game.medic.target=null
	game.medic.treating=false
	for worker in game.players: worker.set_physics_process(false)
	game.players[1].set_meta("network_departed",true)
	check(game.players[1].is_downed() and not game.hud.medic_status_visible(),"A departed avatar cannot keep the rescue HUD open")
	game.players[2].medical.state="downed"
	check(game.hud.medic_status_visible(),"A genuinely downed survivor still exposes rescue status")
	game.players[2].medical.state="healthy"
	var focus=FocusProbe.new()
	game.add_child(focus)
	game.players[0].focus=focus
	var measured=game.hud._occupied_context_rect(0,game.players[0],300)
	for query in 20:
		check(game.hud._occupied_context_rect(0,game.players[0],300)==measured,"Repeated camera queries reuse the rendered context geometry")
	check(focus.prompts==1,"Camera placement does not rebuild interaction prose every frame")
	game.hud._occupied_context_rect(0,game.players[0],250)
	check(focus.prompts==2,"Changed layout width invalidates measured geometry")
	# A private generated stream exercises real capture buffering without a microphone.
	var mic=Microphone.new()
	root.add_child(mic)
	mic.set_process(false)
	mic.sample_rate=48000
	mic._device_confirmed=true
	mic._capture=AudioEffectCapture.new()
	mic._capture.buffer_length=.5
	AudioServer.add_bus()
	var bus=AudioServer.bus_count-1
	AudioServer.set_bus_name(bus,"FollowupSyntheticCapture")
	AudioServer.set_bus_mute(bus,true)
	AudioServer.add_bus_effect(bus,mic._capture)
	var wave=AudioStreamWAV.new()
	wave.format=AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate=48000
	wave.loop_mode=AudioStreamWAV.LOOP_FORWARD
	wave.loop_end=24000
	var pcm=PackedByteArray()
	pcm.resize(48000)
	for index in 24000: pcm.encode_s16(index*2,8192)
	wave.data=pcm
	var player=AudioStreamPlayer.new()
	root.add_child(player)
	player.stream=wave
	player.bus="FollowupSyntheticCapture"
	player.play()
	var capture_deadline:=Time.get_ticks_msec()+1000
	while mic._capture.get_frames_available()<=4096 and Time.get_ticks_msec()<capture_deadline: await process_frame
	var frames=mic._read_input()
	check(frames.size()>4096 and frames.size()<=9600,"A normal 150 ms capture retains every sample beyond the old 4096 limit")
	mic.capturing=true
	mic.active_owner="voice"
	var emitted: Array=[]
	mic.samples_ready.connect(func(_owner,mono,_rate):emitted.append(mono.size()))
	mic._consume_frames(frames)
	check(emitted==[frames.size()],"The entire bounded capture reaches voice encoding")
	capture_deadline=Time.get_ticks_msec()+1000
	while mic._capture.get_frames_available()<=9600 and Time.get_ticks_msec()<capture_deadline: await process_frame
	check(mic._read_input().is_empty() and mic._capture.get_frames_available()<4096,"One read clears a stale backlog instead of trimming successive frames")
	player.stop()
	player.stream=null
	await preload("res://tests/scene_cleanup.gd").free_scene(player,self)
	mic.capturing=false
	mic._capture=null
	AudioServer.remove_bus(bus)
	await preload("res://tests/scene_cleanup.gd").free_scene(mic,self)
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("PERFORMANCE FOLLOWUP: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
