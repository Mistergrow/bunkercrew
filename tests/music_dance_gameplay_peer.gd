extends "res://tests/network_gameplay_peer.gd"
## Two actual ENet processes, actual game worlds and native audio playbacks.
## Barriers carry expected scalar values only; music, crew XP, input and chat
## arrive through the game's authenticated network session.
const DANCE := preload("res://scripts/worker_dance_catalog.gd")
const IDENTITY := preload("res://scripts/worker_identity_art.gd")
const MUSIC_OPTIONS := {"environment":"ash_foundry","build_type":"workshop","position":"left"}
var starting_generation := 0
var music_session_id := 0
var native_stream_id := 0
var max_audible_clock_difference := 0.0
var original_colliders: Array[Vector2] = []
var last_reload_diagnostic := 0
var relay_url := ""

func _run() -> void:
	overall_timeout_ms = 105000
	role = OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	prefix = OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	relay_url = OS.get_environment("BUNKERCREW_MUSIC_DANCE_RELAY_URL")
	if role not in ["host","guest"] or prefix.is_empty() or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		await finish(false,"Use an isolated role/path and --no-profile-save --no-upnp")
		return
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.hud.scenario_options = MUSIC_OPTIONS.duplicate()
	game.hud.story_selected = false
	game.network.listen_port = 24981
	game.network.lan_discovery_port = 24982
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	game.audio.set_music_style("minimal_techno" if role=="host" else "schranz")
	game.audio.set_music_calibration(0.0)
	game.audio.set_rhythm_motion_reduced(false)
	var profiles := DANCE.defaults()
	profiles.levin.style = "levin_air_freeze"
	profiles.mara.style = "mara_precision_step"
	game.audio.set_dance_configuration(1.0,profiles)
	game.network.changed.connect(_reload_diagnostic)
	if role=="host": await host_run()
	else: await guest_run()

func _reload_diagnostic() -> void:
	if not is_instance_valid(game) or game.network._generation<2 or Time.get_ticks_msec()-last_reload_diagnostic<250: return
	last_reload_diagnostic = Time.get_ticks_msec()
	print("MUSIC_RELOAD_STATE ",role," current_scene=",current_scene.get_instance_id() if is_instance_valid(current_scene) else -1," game=",game.get_instance_id()," started=",game.started," loading=",game.network._loading," generation=",game.network._generation," world=",game.network.world!=null," ready=",game.network._ready_for_snapshots," slots=",game.network._slots.values().map(func(link): return [link.slot,link._ready_for_snapshots,link.connected,link._authenticated])," paused=",paused)

func rig(index: int) -> Node:
	return game.players[index].get_node("PixelVisual")

func music() -> Node:
	return game.audio.live_music

func mature(index: int) -> bool:
	return rig(index)._safe_idle and rig(index).rhythm._dance_blend>0.95 and rig(index).pose_skeleton.has("dance_style")

func sample_count() -> int:
	return int(music().native_stream.call("mixed_samples"))

func beat_time() -> float:
	return float(music().rhythm_frame().get("audible_seconds",-1.0))

func has_chat(text: String) -> bool:
	return game.network.chat_history.any(func(entry): return entry.text==text)

func prepare_waiting_crew() -> void:
	# Only automatic wave spawning is held. Normal actor physics, visuals,
	# collision, audio, the HUD and all networking continue every frame.
	game.rounds.set_process(false)
	game.rounds.running = true
	game.rounds.phase = "attack"
	game.rounds.wave = 10
	for index in game.players.size():
		var worker: Node = game.players[index]
		worker.global_position = Vector2(900+index*145,430)
		worker.velocity = Vector2.ZERO
		worker.inventory.clear()
		worker.progression.award_damage(13500.0)
	game.set_camera_zoom(2.0)

func check_identity_and_collision(index: int) -> void:
	var worker: Node = game.players[index]
	check(IDENTITY.head(worker.character_id).resource_path.ends_with("%s_head.png"%worker.character_id) and IDENTITY.torso(worker.character_id).resource_path.ends_with("%s_torso.png"%worker.character_id),"Actual dance retains original side-view parts for "+worker.character_id)
	check(worker.get_node("CollisionShape2D").shape.size==original_colliders[index],"Actual full-body pose leaves the worker's existing collision shape unchanged")

func host_run() -> void:
	game.network.host_room(relay_url)
	if not await wait_for(func(): return game.network.state=="lobby","real authenticated host lobby"):
		await finish(false,"host"); return
	game.network.send_command("character",{"id":"levin"})
	publish("room",{"code":game.network.room_code})
	if not await wait_for(func(): return game.network.connected_player_count()==2 and game.selected_characters.slice(0,2)==["levin","mara"],"real guest character selection"):
		await finish(false,"lobby"); return
	game.network.start_match(MUSIC_OPTIONS,game.selected_characters)
	if not await wait_for(playing,"host begins actual selected scenario",12) or not await barrier("started"):
		await finish(false,"start"); return
	check(music().session_active and music().native_active and music().get_parent()==game.audio,"Normal match start selects the installed native score without opening the developer lab")
	for worker: Node in game.players: original_colliders.append(worker.get_node("CollisionShape2D").shape.size)
	check(game.audio.music_players.all(func(deck): return not deck.playing),"Recorded score decks stop when the normal match begins native playback")
	starting_generation = game.network._generation
	music_session_id = music().get_instance_id()
	native_stream_id = music().native_stream.get_instance_id()
	prepare_waiting_crew()
	if not await wait_for(func(): return music().pending_intensity==3,"actual round phase schedules full combat arrangement"):
		await finish(false,"arrangement"); return
	check(music().pending_bar==8 and int(music().native_stream.call("current_intensity"))==0,"Actual game preserves its quiet opening and schedules BUM at the next complete musical phrase")
	check(game.players.all(func(worker): return worker.is_physics_processing()),"The waiting crew retain their normal running physics")
	publish("crew_ready",{"seed":music().theme_seed,"generation":starting_generation,"target_bar":music().pending_bar})
	if not await barrier("replicated_crew"):
		await finish(false,"crew replication"); return
	if not await wait_for(func(): return mature(0) and mature(1) and int(music().rhythm_frame().get("kick_count",0))>=5,"actual audible combat kicks cause both waiting crew to dance",30):
		await finish(false,"native dance"); return
	check(str(rig(0).pose_skeleton.dance_style)=="levin_air_freeze" and str(rig(1).pose_skeleton.dance_style)=="mara_precision_step","Actual character level unlocks each selected personal full-body move")
	check(game.players.all(func(worker): return worker.progression.level>=10) and game.combat_events.dance_level("levin")>=10,"Actual XP and its combat dispatcher unlock cosmetic moves in the live match")
	var foot_poses := {}
	var freeze_seen := false
	var until := Time.get_ticks_msec()+9000
	var x_before: float = game.players[0].global_position.x
	while Time.get_ticks_msec()<until:
		if mature(0):
			foot_poses[str(rig(0).pose_skeleton.feet)] = true
			freeze_seen = freeze_seen or str(rig(0).pose_skeleton.get("dance_stage",""))=="freeze"
		if freeze_seen and foot_poses.size()>=20: break
		await process_frame
	check(freeze_seen and foot_poses.size()>=20,"Real heard kicks drive varied footwork and a personal breakdance freeze")
	check(absf(game.players[0].global_position.x-x_before)<0.01 and game.players[0].velocity==Vector2.ZERO,"Actual idle dance never drifts the authoritative worker or injects movement")
	check_identity_and_collision(0)
	publish("mature",{"audible_seconds":beat_time(),"seed":music().theme_seed,"bpm":music().clock.bpm,"target_bar":music().pending_bar,"style":str(rig(0).pose_skeleton.dance_style)})
	if not await barrier("guest_dancing"):
		await finish(false,"guest dance"); return
	check(game.network.send_chat("Der Beat läuft im echten Spiel."),"Host can use the real crew chat while both players dance")
	publish("move")
	if not await barrier("move_sent"):
		await finish(false,"movement"); return
	check(absf(game.players[1].velocity.x)>15.0 and rig(1).rhythm.weight==0.0 and not rig(1).pose_skeleton.has("dance_style"),"Real guest movement immediately interrupts the host's displayed idle dance")
	publish("movement_seen")
	if not await barrier("move_released") or not await wait_for(func(): return mature(1),"fresh audible kicks resume dancing after real movement",8):
		await finish(false,"dance resume"); return
	publish("pause_ready")
	if not await wait_for(func(): return paused and game.network.match_paused,"guest shared pause"):
		await finish(false,"pause"); return
	await delay(.12)
	var paused_samples := sample_count()
	var paused_seconds := beat_time()
	await delay(.25)
	check(not music().rhythm_frame().active and absf(beat_time()-paused_seconds)<0.000001 and sample_count()==paused_samples,"Actual shared pause freezes the native audio samples and audible dance clock")
	publish("paused")
	if not await wait_for(playing,"guest shared resume"):
		await finish(false,"resume"); return
	check(music().get_instance_id()==music_session_id and music().native_stream.get_instance_id()==native_stream_id,"Shared resume retains the musical theme and playback instance")
	publish("mute_ready")
	if not await barrier("muted"):
		await finish(false,"local mute"); return
	check(music().rhythm_frame().active and game.audio.music_volume>0.0,"Guest's local mute leaves the host music and its audible beat active")
	publish("mute_seen")
	if not await barrier("unmuted") or not await barrier("restart_ready"):
		await finish(false,"mute/restart"); return
	var scene_id: int = game.get_instance_id()
	var session_id: int = game.network.get_instance_id()
	var old_seed: int = music().theme_seed
	check(game.restart(),"Host restarts the actual game from its normal session action")
	if not await wait_for(func(): return playing() and game.get_instance_id()!=scene_id,"complete host scene restart",15) or not await barrier("restarted",15):
		await finish(false,"restart"); return
	game.rounds.running = false
	check(game.network.get_instance_id()==session_id and game.network._generation==starting_generation+1,"Restart keeps the authenticated network room and advances the match generation")
	check(music().native_active and music().match_seed==game.network._generation and music().theme_seed!=old_seed,"Restart starts one native score with the new authoritative match seed")
	check(game.audio.music_style=="minimal_techno" and game.audio.dance_profiles.levin.style=="levin_air_freeze" and game.combat_events.dance_level("levin")>=10,"Restart retains the music preference, chosen personal move and earned cosmetic unlocks")
	check(has_chat("Der Beat läuft im echten Spiel.") and game.network.send_chat("Musik und Chat nach Neustart."),"Real crew conversation survives the complete music/game rebuild")
	publish("host_restarted",{"seed":music().theme_seed,"generation":game.network._generation})
	if not await barrier("verified_restart"):
		await finish(false,"guest restart state"); return
	publish("host_passed",{"checks":checks,"failures":failures})
	if not await barrier("guest_passed"):
		await finish(false,"guest finish"); return
	publish("finish")
	await delay(.15)
	await finish(failures==0,"Native music, audible personal choreography, input interruption, pause, local mute, shared restart and retained chat")

func guest_run() -> void:
	game.network.join_room(relay_url,str(read_stage("room").get("code","")))
	if not await wait_for(func(): return game.network.state=="lobby" and game.network._authenticated,"real authenticated guest lobby"):
		await finish(false,"join"); return
	game.network.send_command("character",{"id":"mara"})
	if not await wait_for(func(): return playing() and game.network.received_snapshots>=3,"guest receives normal live match",15):
		await finish(false,"start"); return
	check(game.players.size()==2 and game.players[0].character_id=="levin" and game.players[1].character_id=="mara","Guest spawns the actual authoritative selected characters")
	for worker: Node in game.players: original_colliders.append(worker.get_node("CollisionShape2D").shape.size)
	check(music().native_active and music()._remote_session and music().genre=="minimal_techno","Actual host snapshots replace the guest's different local music preference")
	publish("started")
	if not await barrier("crew_ready") or not await wait_for(func(): return game.players.all(func(worker): return worker.progression.level>=10) and absf(game.players[1].global_position.x-1045.0)<2.0,"live crew XP and waiting positions",12):
		await finish(false,"replicated crew"); return
	var expected := read_stage("crew_ready")
	check(music().theme_seed==int(expected.seed) and music().pending_bar==int(expected.target_bar) and music().pending_intensity==3,"Real compressed snapshots deliver the identical motif, seed and future arrangement boundary")
	check(game.players.all(func(worker): return not worker.is_physics_processing()),"Guest dance never starts a second authoritative actor simulation")
	publish("replicated_crew")
	if not await barrier("mature",38) or not await wait_for(func(): return mature(0) and mature(1),"guest's actual heard kicks trigger replicated idle crew",8):
		await finish(false,"guest native dance"); return
	var mature_state := read_stage("mature")
	max_audible_clock_difference = absf(beat_time()-float(mature_state.audible_seconds))
	check(music().theme_seed==int(mature_state.seed) and music().clock.bpm==float(mature_state.bpm) and str(rig(0).pose_skeleton.dance_style)==str(mature_state.style),"Separate native mixers render the same host theme, tempo and level-unlocked personal move")
	check(max_audible_clock_difference<0.40,"Host/guest audible native timelines agree within 0.40 seconds on the real local network")
	check_identity_and_collision(0)
	publish("guest_dancing",{"clock_difference_seconds":max_audible_clock_difference})
	if not await barrier("move") or not await wait_for(func(): return has_chat("Der Beat läuft im echten Spiel."),"actual chat arrives during dance"):
		await finish(false,"chat/move"); return
	Input.action_press("p1_right")
	if not await wait_for(func(): return absf(game.players[1].velocity.x)>15.0 and rig(1).rhythm.weight==0.0,"real movement interrupts guest's visible dance"):
		await finish(false,"local dance interruption"); return
	check(not rig(1).pose_skeleton.has("dance_style"),"Movement presents normal walking instead of an idle dance pose")
	publish("move_sent")
	if not await barrier("movement_seen"):
		await finish(false,"host movement"); return
	Input.action_release("p1_right")
	publish("move_released")
	if not await barrier("pause_ready"):
		await finish(false,"pause ready"); return
	game.network.pause_match(true)
	if not await wait_for(func(): return paused and game.network.match_paused,"guest actual shared pause") or not await barrier("paused"):
		await finish(false,"pause"); return
	check(not music().rhythm_frame().active and music()._paused,"Guest shared pause disables its native audible beat presentation")
	game.network.pause_match(false)
	if not await wait_for(playing,"guest actual shared resume") or not await barrier("mute_ready"):
		await finish(false,"resume"); return
	game.audio.set_music_volume(0.0)
	await delay(.12)
	var before := sample_count()
	await delay(.20)
	check(not music().rhythm_frame().active and rig(1).rhythm.weight==0.0 and sample_count()>before,"Real local music mute cancels dance while the synchronized native timeline keeps advancing")
	publish("muted")
	if not await barrier("mute_seen"):
		await finish(false,"other peer mute isolation"); return
	game.audio.set_music_volume(1.0)
	if not await wait_for(func(): return music().rhythm_frame().active,"local unmute resumes audible events"):
		await finish(false,"unmute"); return
	publish("unmuted")
	var scene_id: int = game.get_instance_id()
	var session_id: int = game.network.get_instance_id()
	publish("restart_ready")
	if not await wait_for(func(): return playing() and game.get_instance_id()!=scene_id,"complete guest scene restart",18):
		await finish(false,"restart"); return
	check(game.network.get_instance_id()==session_id and music().native_active and music()._remote_session,"Guest keeps its actual network session and rebinds native music after complete scene replacement")
	publish("restarted")
	if not await barrier("host_restarted") or not await wait_for(func(): return has_chat("Musik und Chat nach Neustart."),"post-restart real crew chat"):
		await finish(false,"post restart"); return
	var restarted := read_stage("host_restarted")
	check(music().match_seed==int(restarted.generation) and music().theme_seed==int(restarted.seed) and music().genre=="minimal_techno","Post-restart actual snapshots re-establish the shared score and new match seed")
	check(has_chat("Der Beat läuft im echten Spiel.") and has_chat("Musik und Chat nach Neustart."),"Guest retains the earlier crew conversation and can receive new chat after restart")
	check(game.audio.dance_profiles.mara.style=="mara_precision_step","Guest personal dance choice survives its actual full scene reload")
	publish("verified_restart")
	if not await barrier("host_passed"):
		await finish(false,"host finish"); return
	publish("guest_passed",{"checks":checks,"failures":failures,"max_audible_clock_difference_seconds":max_audible_clock_difference})
	if not await barrier("finish"):
		await finish(false,"finish"); return
	await finish(failures==0,"Real authoritative music snapshots, native kicks, safe dance, movement, pause, local mute and restart")
