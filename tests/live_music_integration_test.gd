extends SceneTree
## Real Game/Audio rebuilds and actual compressed snapshot envelopes. Transport
## is captured locally: this isolates music replication from socket connectivity.
const Runtime := preload("res://scripts/live_music.gd")
const World := preload("res://scripts/network_world.gd")
const Protocol := preload("res://scripts/network_protocol.gd")
const Messages := preload("res://scripts/network_messages.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
var checks := 0
var failures := 0

class CaptureTransport:
	extends Node
	var connected_peer := 2
	var last_packet_channel := 0
	var packets: Array[PackedByteArray] = []
	func send(packet: PackedByteArray,_reliable: bool=true,_channel: int=-1,_target: int=0) -> Error:
		packets.append(packet.duplicate())
		return OK
	func close() -> void: pass
	func flush_departure() -> void: pass

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)

func prepare_network(game: Node, host: bool) -> Node:
	var session: Node=game.network
	session.set_process(false)
	session.set_physics_process(false)
	session.active=true
	session.is_host=host
	session.local_player_id=1 if host else 2
	session.peer_connected=true
	session._authenticated=true
	session._generation=11
	session.state="playing"
	var capture:=CaptureTransport.new()
	capture.name="CapturedMusicTransport"
	capture.connected_peer=2 if host else 1
	session.add_child(capture)
	session.transport=capture
	return capture

func freeze_gameplay(node: Node, audio: Node, network: Node) -> void:
	if node==audio or node==network: return
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children():
		freeze_gameplay(child,audio,network)

func check_actual_crew_dance(game: Node) -> void:
	if not game.audio.live_music.native_active:
		return
	# Prepared real gameplay state: physics is frozen, crew is healthy and still,
	# no nearby enemies, and the actual native combat bank is audible. The rig
	# receives only events produced by AudioStreamPlayback, without a clock stub.
	var worker: Node=game.players[0]
	var visual: Node=worker.get_node("PixelVisual")
	worker.velocity=Vector2.ZERO
	worker._airborne=false
	worker.inventory.clear()
	var position_before: Vector2=worker.global_position
	var collision_before: Vector2=worker.get_node("CollisionShape2D").shape.size
	game.audio.set_music_calibration(0.0)
	game.audio.set_rhythm_motion_reduced(false)
	game.audio.set_dance_configuration(1.0,Dance.defaults())
	game.audio.live_music.begin_session("ash_foundry",11,{"genre":"hip_hop","intensity":2,"current_intensity":2,"target_bar":0})
	visual.idle_clock.wait_remaining=1000
	var until:=Time.get_ticks_msec()+6000
	var motions: Dictionary={}
	var full_body:=false
	while Time.get_ticks_msec()<until:
		game.audio._process(0.02)
		visual._process(0.02)
		if visual.pose_skeleton.has("dance_style"):
			full_body=full_body or visual.pose_skeleton.dance_style in Dance.FULL_BODY_STYLES
			motions[str([visual.pose_skeleton.hip,visual.pose_skeleton.hands,visual.pose_skeleton.feet])]=true
		if full_body and visual.rhythm._dance_blend>0.9 and motions.size()>=8:
			break
		await create_timer(0.02).timeout
	check(game.audio.live_music.rhythm_frame().kick_count>=4 and game.audio.live_music.rhythm_frame().last_kick_strength>=0.35,"The actual game mixer emits several genuinely audible combat kicks to the idle crew")
	check(visual._safe_idle and full_body and visual.rhythm._dance_blend>0.9 and motions.size()>=8,"A real idle crew rig enters varied full-body choreography from the game's native combat score")
	check(worker.global_position==position_before and worker.velocity==Vector2.ZERO and worker.get_node("CollisionShape2D").shape.size==collision_before,"Full-body dance leaves actual crew position, velocity and collision geometry unchanged")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save --no-upnp for the isolated music integration run")
		quit(1)
		return
	var host: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(host)
	current_scene=host
	host.combat_events.persistence_enabled=false
	host.audio.set_music_style("hip_hop")
	var transport: Node=prepare_network(host,true)
	var options:={"environment":"ash_foundry","build_type":"bastion","position":"left"}
	host.start_scenario(2,options)
	freeze_gameplay(host,host.audio,host.network)
	host.audio.set_process(false) # Explicit frames below are deterministic fixtures.
	check(host.started and host.audio.live_music.session_active,"Starting the actual foundry game begins a retained music session")
	check(host.audio.live_music.match_seed==11,"The actual network match generation becomes the common music seed")
	check(host.audio.live_music.get_parent()==host.audio,"Live music belongs to the retained Audio session node")
	check(host.audio.process_mode==Node.PROCESS_MODE_ALWAYS,"Audio remains responsive through loading and pause")
	if ClassDB.class_exists("TesselStream"):
		check(host.audio.live_music.native_active,"The actual game's Audio owner selects the installed native synthesis backend")
		check(host.audio.music_players.all(func(deck):return not deck.playing),"Recorded decks stop when native live music becomes active")
	else:
		check(host.audio.music_player.playing,"Missing native synthesis restores the selected recorded score")
	var runtime_id: int=host.audio.live_music.get_instance_id()
	var stream_before: AudioStream=host.audio.live_music.native_stream
	host.started=false
	host.start_scenario(2,options)
	freeze_gameplay(host,host.audio,host.network)
	check(host.audio.live_music.get_instance_id()==runtime_id,"Replacing the complete scenario preserves the music session node")
	check(host.audio.live_music.native_stream==stream_before,"Rebuilding the same match and theme preserves its musical stream and timeline")
	await process_frame
	await physics_frame
	host.network.world=World.new()
	host.network.world.bind(host)
	host.rounds.phase="attack"
	host.rounds.wave=15
	host.audio._process(0.1)
	check(host.audio.live_music.pending_intensity==3,"The actual round controller feeds the four-level music arrangement")
	var started_at:=Time.get_ticks_msec()
	while Time.get_ticks_msec()-started_at<300:
		host.audio._process(0.02)
		await create_timer(0.02).timeout
	host.network._send_snapshot(true)
	check(not transport.packets.is_empty(),"The actual host snapshot sender writes a compressed packet")
	var message:=Protocol.decode(transport.packets.back())
	check(message.kind=="snapshot" and message.has("music") and Runtime.valid_music_state(message.music),"Host snapshots contain the validated optional music envelope")
	check(Messages.valid(message,false),"The complete compressed music snapshot passes the guest envelope validator")
	check(message.music.seed==host.audio.live_music.theme_seed and message.music.target_bar==host.audio.live_music.pending_bar,"The host snapshot carries the exact shared theme and future phrase command")
	check(message.music.genre=="hip_hop" and host.audio.live_music.genre=="hip_hop","The actual game's saved music style selects and replicates its concrete genre")
	var guest: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(guest)
	guest.combat_events.persistence_enabled=false
	guest.audio.set_music_style("schranz")
	prepare_network(guest,false)
	guest.start_scenario(2,options)
	freeze_gameplay(guest,guest.audio,guest.network)
	guest.audio.set_process(true)
	guest.network.world=World.new()
	guest.network.world.bind(guest)
	guest.network.world.freeze_client()
	check(guest.audio.is_processing() and guest.audio.live_music.get_parent()==guest.audio,"Freezing replicated client gameplay preserves Audio ticks and its clock node")
	guest.audio.set_process(false)
	guest.network._receive_packet_message(message,0)
	check(guest.network.received_snapshots==1 and guest.audio.live_music._remote_session,"The real guest snapshot handler applies the first authoritative music state after local game start")
	check(guest.audio.live_music.theme_seed==host.audio.live_music.theme_seed and guest.audio.live_music.pending_bar==host.audio.live_music.pending_bar,"Actual host and guest keep identical motifs and arrangement boundaries")
	check(guest.audio.live_music.genre==host.audio.live_music.genre and guest.audio.live_music.clock.bpm==host.audio.live_music.clock.bpm,"The guest's provisional local genre is replaced by the actual host snapshot and its tempo")
	var commands: int=guest.audio.live_music.command_serial
	guest.rounds.phase="salvage"
	guest.audio._process(0.1)
	check(guest.audio.live_music.command_serial==commands and guest.audio.live_music.pending_intensity==3,"Guest presentation frames cannot replace the host arrangement using local replicated actor state")
	var stale: Dictionary=message.music.duplicate(true)
	stale.command_serial=maxi(commands-1,0)
	stale.intensity=0
	guest.audio.live_music.apply_music_state(stale)
	check(guest.audio.live_music.command_serial==commands and guest.audio.live_music.pending_intensity==3,"Outdated music commands cannot rewind an already-applied arrangement")
	await check_actual_crew_dance(host)
	host.audio.set_music_volume(0)
	host.audio._process(0.1)
	check(not host.audio.live_music.rhythm_frame().active and host.audio.live_music.rhythm_frame().beat_pulse==0.0,"The real music volume control disables all beat motion immediately")
	check(host.audio.live_music.get_music_state().active,"Muting locally leaves the authoritative musical session intact for other players")
	if host.audio.live_music.native_active:
		var muted_samples: int=host.audio.live_music.native_stream.call("mixed_samples")
		var mute_started:=Time.get_ticks_msec()
		while Time.get_ticks_msec()-mute_started<2300:
			host.audio._process(0.02)
			await create_timer(0.02).timeout
		check(int(host.audio.live_music.native_stream.call("mixed_samples"))>muted_samples+44100,"Muted native synthesis keeps the shared timeline advancing beyond audio-bus silence optimization")
	host.audio.set_music_volume(1)
	paused=true
	host.audio._process(0.1)
	check(host.audio.live_music._paused and not host.audio.live_music.rhythm_frame().active,"An actual game pause freezes native music presentation")
	host.audio.set_live_music_enabled(false)
	check(host.audio._deck_active(host.audio.music_player) and host.audio.music_player.stream_paused,"Switching to a recording inside a paused game keeps its newly restored decoder paused immediately")
	var paused_switch_samples: int=host.audio.live_music.get_music_state().mixed_samples
	host.audio.set_live_music_enabled(true)
	check(host.audio.live_music.native_active and host.audio.live_music.clock.paused,"Switching back to native output inside the paused game preserves the paused musical transport")
	check(host.audio.live_music.get_music_state().mixed_samples>=paused_switch_samples,"A freshly queued paused native stream never advertises a zero-time snapshot while its mixer start is pending")
	paused=false
	host.audio._process(1.0)
	check(not host.audio.live_music._paused,"Unpausing the game resumes the same music clock")
	host.audio.set_voice_volume(1)
	host.voice.remote_speaking=false
	host.audio.set_dialogue_active(false,"story")
	host.audio._process(2.0)
	var baseline: float=host.audio._score_level
	host.voice.remote_speaking=true
	host.audio._process(0.5)
	check(host.audio._score_level<=baseline-5.9,"Remote voice chat ducks the live musical mix by six decibels")
	host.voice.remote_speaking=false
	host.audio.set_dialogue_active(true,"story")
	host.audio._process(0.5)
	check(host.audio._score_level<=baseline-5.9,"Recorded dialogue shares the same live music ducking path")
	host.audio.set_dialogue_active(false,"story")
	host.audio._process(2.0)
	check(absf(host.audio._score_level-baseline)<0.01,"The mix recovers smoothly after dialogue and voice chat end")
	host.audio.set_rhythm_motion_reduced(true)
	host.audio.set_music_calibration(0.2)
	check(host.audio.live_music.rhythm_frame().reduced_motion and host.audio.live_music.clock.calibration_seconds==0.2,"Audio options reach the retained presentation session")
	check(not host.audio.live_music.get_music_state().has("calibration") and not host.audio.live_music.get_music_state().has("reduced_motion"),"Personal comfort and output latency choices remain local in host snapshots")
	host.audio.set_live_music_enabled(false)
	host.audio._process(0.1)
	check(not host.audio.live_music.native_active and host.audio.music_player.playing,"Disabling native live music automatically resumes the world-specific recorded score")
	check(not host.audio.live_music.rhythm_frame().active,"Recorded fallback cannot drive a fabricated native beat clock")
	var fallback_start: Dictionary=host.audio.live_music.get_music_state()
	host.audio._process(0.25)
	var fallback_now: Dictionary=host.audio.live_music.get_music_state()
	check(fallback_now.mixed_samples>=fallback_start.mixed_samples+int(0.24*fallback_now.mix_rate),"A host selecting recorded music keeps its authoritative arrangement position advancing")
	guest.audio.live_music.end_session()
	guest.audio.live_music.apply_music_state(fallback_now)
	check(guest.audio.live_music.native_active and guest.audio.live_music.pending_bar==fallback_now.target_bar,"A native guest follows a recorded-music host's future phrase and current arrangement")
	paused=true
	host.audio._process(0.1)
	guest.audio._process(0.1)
	check(host.audio._deck_active(host.audio.music_player) and host.audio.music_player.stream_paused and guest.audio.live_music._paused,"The actual shared pause freezes recorded host decks and native guest playback together")
	await create_timer(0.1,true,false,true).timeout
	var recording_pause_position: float=host.audio.music_player.get_playback_position()
	var fallback_pause_samples: int=host.audio.live_music.get_music_state().mixed_samples
	var paused_decoder: int=host.audio.music_player.get_stream_playback().get_instance_id()
	host.audio.set_live_music_enabled(false)
	check(host.audio.music_player.get_stream_playback().get_instance_id()==paused_decoder,"Repeated fallback settings preserve the paused recording decoder instead of restarting its opening")
	host.audio._process(0.3)
	await create_timer(0.12,true,false,true).timeout
	check(host.audio.live_music.get_music_state().mixed_samples==fallback_pause_samples and absf(host.audio.music_player.get_playback_position()-recording_pause_position)<0.02,"Paused fallback snapshots and actual OGG playback both remain at the same position")
	paused=false
	host.audio._process(0.1)
	guest.audio._process(0.1)
	check(host.audio.music_players.all(func(deck):return not deck.stream_paused) and not guest.audio.live_music._paused,"Resuming the shared match releases both recorded and native audio transports")
	var resume_state: Dictionary=host.audio.live_music.get_music_state()
	host.audio.set_live_music_enabled(true)
	var resume_deadline:=Time.get_ticks_msec()+1000
	while host.audio.live_music.native_stream.call("mixed_samples")==0 and Time.get_ticks_msec()<resume_deadline:
		await create_timer(0.02).timeout
	check(host.audio.live_music.native_active and absf(float(host.audio.live_music.native_stream.call("mixed_samples"))-float(resume_state.mixed_samples))<48000.0,"The actual Audio preference resumes native output near its ongoing shared sample position")
	check(host.audio.music_players.all(func(deck):return not deck.playing),"Returning to live music retires both recording decks without a second audible score")
	stream_before=null
	check(await Cleanup.free_scene(guest,self),"Guest game and all retained native playback handles release cleanly")
	current_scene=host
	check(await Cleanup.free_scene(host,self),"Host game and retired preview/rebuild playback handles release cleanly")
	paused=false
	print("LIVE MUSIC INTEGRATION: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
