extends SceneTree
## Native prepared gallery only: real game, authored rigs and real speech layer.
## Voice status is seeded on the real voice receiver; no microphone is acquired.
const Roster := preload("res://scripts/crew_roster.gd")
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const CORE_IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
var checks := 0
var failures := 0
var extension_id := "beta.fixture:ninth"
var folder := "res://artifacts/content-extension-20261005/native"
var records: Array[Dictionary] = []

class RosterBoard extends Control:
	var highlighted := ""
	func _draw() -> void:
		draw_rect(Rect2(26,640,1388,230),Color("101b1df0"))
		UiArt.text(self,Vector2(46,670),"Installed character profiles · actual runtime sprites",17,UiArt.IVORY)
		for index in CORE_IDS.size():
			var at := Vector2(111+index*171,820)
			var entry := CharacterCatalog.data(CORE_IDS[index])
			UiArt.centered(self,at+Vector2(0,27),str(entry.title),13,Color(entry.accent))
			UiArt.centered(self,at+Vector2(0,44),CORE_IDS[index],10,UiArt.MUTED)
		if not highlighted.is_empty():
			UiArt.text(self,Vector2(46,696),"True identity: "+highlighted+" · declared visual: "+CharacterCatalog.presentation_id(highlighted,"visual")+" · declared voice: "+CharacterCatalog.presentation_id(highlighted,"voice"),12,UiArt.AMBER)

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CONTENT NATIVE: "+label)

func freeze_actor(actor: Worker,position_value: Vector2) -> void:
	actor.position = position_value
	actor.velocity = Vector2.ZERO
	actor.set_physics_process(false)
	actor.get_node("WorkerWeapon").set_physics_process(false)
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	visual.set_process(false)
	visual.set_physics_process(false)
	visual.locomotion_pose = Personality.stance(PoseArt.neutral(),actor.character_id)
	visual.queue_redraw()

func board() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 67
	var roster_board := RosterBoard.new()
	roster_board.highlighted = ""
	layer.add_child(roster_board)
	root.add_child(layer)
	for index in CORE_IDS.size():
		var actor: Worker = load("res://scenes/player.tscn").instantiate()
		actor.character_id = CORE_IDS[index]
		actor.player_id = 1
		roster_board.add_child(actor)
		freeze_actor(actor,Vector2(111+index*171,834))
		actor.scale = Vector2.ONE*1.4
	return layer

func prepare(selected: Array[String]) -> Node:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.selected_characters.assign(selected)
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"center"})
	game.rounds.running = false
	game.rounds.set_process(false)
	game.set_process(false)
	game.set_physics_process(false)
	game.player_camera.set_process(false)
	game.camera.position = Vector2(720,400)
	game.camera.zoom = Vector2.ONE*1.25
	game.camera.force_update_scroll()
	game.network.set_process(false)
	game.voice.set_process(false)
	game.story.set_process(false)
	game.solo_story.set_process(false)
	game.dialogue.set_process(false)
	for index in game.players.size(): freeze_actor(game.players[index],Vector2(500+index*170,430))
	check(game.get_node_or_null("WorkerSpeechBubbles")!=null,"real selected world preserves comic speech layer")
	return game

func seed_voice(game: Node) -> void:
	# Prepared authenticated receive status; this does not call acquire/record.
	game.network.active = true
	game.network.is_host = true
	game.network.peer_connected = true
	game.network.local_player_id = 1
	game.network.state = "playing"
	game.voice.enabled = true
	game.voice._primary_sender = 3
	game.voice._clock = 1.0
	game.voice._last_received = 0.95
	game.voice._receive_peak = 0.1
	check(game.voice.speaking_players()==[3],"real receiver exposes prepared remote voice status")

func capture(game: Node,name: String,expected: Array[int]) -> void:
	var bubbles: Node = game.get_node_or_null("WorkerSpeechBubbles")
	if bubbles==null: return
	bubbles._bind_network()
	bubbles.canvas.queue_redraw()
	for unused in 4: await process_frame
	var layout: Array[Dictionary] = bubbles.bubble_layout()
	var seats: Array[int] = []
	for row: Dictionary in layout: seats.append(int(row.seat))
	check(seats==expected,name+" bubbles stay on the prepared actor seats")
	check(not game.microphone.capturing,name+" uses no microphone capture")
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder+"/"+name+".png")==OK,name+" native screenshot saved")
	var actor_ids: Array[String] = []
	for actor: Worker in game.players: actor_ids.append(actor.character_id)
	records.append({"capture":name,"ids":actor_ids,"zoom":game.camera.zoom.x,"bubbles":layout,"microphone_acquired":false})

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		push_error("Native content gallery requires display and --no-profile-save")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--extension-id="): extension_id = argument.trim_prefix("--extension-id=")
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=")
	InputSetup.install()
	LocaleText.set_locale("de",false)
	Roster.persistence_enabled = false
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var roster_layer := board()
	var game := prepare(["mara","branko","ivo","nora"])
	var bubbles: Node = game.get_node_or_null("WorkerSpeechBubbles")
	if bubbles!=null:
		seed_voice(game)
		bubbles._bind_network()
		game.dialogue.reset()
		check(game.dialogue.enqueue("crew_wall","mara",1,710),"real authored speech starts on Mara")
		game.dialogue.advance(.1)
		game.network.chat_received.emit({"id":1,"player_id":2,"name":"Branko","text":"Ich decke den Reifenwechsel!","preset":"","time":0.0})
		game.network.chat_received.emit({"id":2,"player_id":4,"name":"Nora","text":"Munition liegt im Lager.","preset":"","time":0.1})
		await capture(game,"core-crew-speech",[1,2,3,4])
	game.network.active = false
	check(await Cleanup.free_scene(game,self),"prepared core game releases all audio")
	if CharacterCatalog.contains(extension_id):
		roster_layer.get_child(0).highlighted = extension_id
		roster_layer.get_child(0).queue_redraw()
		Roster.unlocked[extension_id] = true
		game = prepare([extension_id,"branko","ivo","nora"])
		bubbles = game.get_node_or_null("WorkerSpeechBubbles")
		if bubbles!=null:
			seed_voice(game)
			bubbles._bind_network()
			game.dialogue.reset()
			check(game.dialogue.enqueue("crew_reply",extension_id,1,720),"actual ninth identity starts declared recording")
			game.dialogue.advance(.1)
			check(game.dialogue.active.speaker_id==extension_id and game.dialogue.voice.stream.resource_path==Dialogue.recording_path("crew_reply",extension_id,"de"),"ninth bubble belongs to ninth actor and declared voice bank")
			game.camera.zoom = Vector2.ONE*1.65
			game.camera.force_update_scroll()
			game.network.chat_received.emit({"id":1,"player_id":2,"name":"Branko","text":"Bereit.","preset":"","time":0.0})
			await capture(game,"ninth-crew-speech-zoom",[1,2,3])
		game.network.active = false
		check(await Cleanup.free_scene(game,self),"prepared ninth game releases all audio")
	else:
		print("CONTENT NATIVE: core-only capture; no extension pack installed")
	check(await Cleanup.free_scene(roster_layer,self),"comparison rigs release cleanly")
	var output := FileAccess.open(folder+"/prepared-states.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"prepared_states":records,"checks":checks,"failures":failures,"voice_status":"Seeded authenticated receive peak; no microphone or external networking"},"\t"))
	output.close()
	print("CONTENT NATIVE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
