extends SceneTree
## Real game, camera transforms and four delivered public texts. No microphone.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Bubbles := preload("res://scripts/worker_speech_bubbles.gd")
var game: Node
var folder := "res://artifacts/content-architecture-20261005/speech-layout/native"
var checks := 0
var failures := 0
var states: Array[Dictionary] = []

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SPEECH NATIVE: "+label)

func capture(name: String, target: Vector2, ui_scale: float, messages: Array[String], presets: Dictionary = {}, spacing: float = 0.0) -> void:
	var viewport_size := root.get_visible_rect().size
	var screen := viewport_size/ui_scale
	game.hud.canvas.scale = Vector2.ONE*ui_scale
	game.hud.version_badge._layout()
	var actor_position := Vector2(720,430)
	var actor_anchor := actor_position+Vector2(0,-68)
	game.camera.position = actor_anchor-(target*ui_scale-viewport_size*.5)/game.camera.zoom.x
	game.camera.force_update_scroll()
	game.speech_bubbles._bind_network()
	game.speech_bubbles._messages.clear()
	var actor_positions: Array[Vector2] = []
	for index in game.players.size():
		var actor: Worker = game.players[index]
		actor.position = actor_position+Vector2((index-1.5)*spacing/game.camera.zoom.x,0)
		actor_positions.append(actor.position)
		actor.get_node("PixelVisual").queue_redraw()
		game.network.chat_received.emit({"id":index+1,"player_id":index+1,"name":"Crew","text":"" if presets.has(index) else messages[index],"preset":str(presets.get(index,"")),"time":0.0})
	game.speech_bubbles.canvas.queue_redraw()
	for unused in 4: await process_frame
	var layout: Array[Dictionary] = game.speech_bubbles.bubble_layout()
	check(layout.size()==4,name+" keeps all four prepared speakers")
	if name=="literal-public-text-en":
		check(layout[0].rows==["Danke!"] and layout[1].rows==["Bereit!"],"free public text stays literal on the real English canvas")
		check(layout[3].rows==["Thank you!"],"quick chat is deliberately localized on the real English canvas")
	var bounds := Rect2(Vector2(8,72),screen-Vector2(16,144))
	for index in layout.size():
		var entry: Dictionary = layout[index]
		check(bounds.encloses(entry.rect),name+" lettering stays inside the viewport")
		for previous in index: check(not layout[previous].rect.grow(2).intersects(entry.rect.grow(2)),name+" text does not overlap another speaker")
	check(not game.microphone.capturing,name+" does not acquire a microphone")
	await RenderingServer.frame_post_draw
	var screenshot := root.get_texture().get_image()
	# The framebuffer dimensions are independent of the runtime transform API.
	# This catches a missing stretch factor in embedded and small-window modes.
	var pixels_per_unit := float(screenshot.get_width())/viewport_size.x*ui_scale
	var physical_font_sizes: Array[float] = []
	for entry: Dictionary in layout:
		physical_font_sizes.append(entry.font_size*pixels_per_unit)
		check(entry.font_size>=Bubbles.FONT_SIZE and entry.font_size*pixels_per_unit>=Bubbles.MIN_FONT_PIXELS-.01,name+" actual framebuffer lettering retains its minimum output pixel size")
		check(entry.font_size==maxi(Bubbles.FONT_SIZE,ceili(Bubbles.MIN_FONT_PIXELS/pixels_per_unit)),name+" actual framebuffer stretch is compensated exactly once")
	check(screenshot.save_png(folder+"/"+name+".png")==OK,name+" screenshot is saved")
	states.append({"capture":name,"actor_ids":game.selected_characters,"actor_world_positions":actor_positions,"camera":game.camera.position,"zoom":game.camera.zoom.x,"ui_scale":ui_scale,"window_size":root.size,"visible_viewport":viewport_size,"capture_pixels":screenshot.get_size(),"framebuffer_pixels_per_unit":pixels_per_unit,"physical_font_sizes":physical_font_sizes,"lettering_output_scale":(root.get_stretch_transform()*game.speech_bubbles.canvas.get_global_transform_with_canvas()).get_scale(),"target_tip":target,"locale":LocaleText.current_locale(),"public_messages":messages,"presets":presets,"bubbles":layout,"microphone_acquired":false})

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless":
		push_error("Speech gallery requires a display and --no-profile-save")
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): folder = argument.trim_prefix("--output=")
	InputSetup.install()
	LocaleText.set_locale("de",false)
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.selected_characters.assign(["mara","branko","ivo","nora"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"center"})
	game.rounds.running = false
	for node: Node in [game,game.rounds,game.player_camera,game.story,game.solo_story,game.dialogue,game.voice,game.network,game.hud]:
		node.set_process(false)
		node.set_physics_process(false)
	game.dialogue.reset()
	game.camera.zoom = Vector2.ONE*1.25
	for actor: Worker in game.players:
		actor.velocity = Vector2.ZERO
		actor.set_physics_process(false)
		actor.get_node("WorkerWeapon").set_physics_process(false)
		var visual: WorkerVisual = actor.get_node("PixelVisual")
		visual.set_process(false)
		visual.set_physics_process(false)
		visual.locomotion_pose = Personality.stance(PoseArt.neutral(),actor.character_id)
		visual.queue_redraw()
	var crew_lines: Array[String] = ["Ich decke den Reifenwechsel!","Munition liegt im Lager.","Wir halten den Hof.","Ich helfe dir an der Werkbank."]
	game.camera.zoom = Vector2.ONE
	await capture("normal-four-crew",Vector2(720,380),1.0,crew_lines,{},300)
	game.camera.zoom = Vector2.ONE*1.8
	await capture("near-zoom-four-crew",Vector2(720,400),1.0,crew_lines,{},300)
	root.size = Vector2i(960,600)
	for unused in 3: await process_frame
	game.camera.zoom = Vector2.ONE
	var small_view := root.get_visible_rect().size
	await capture("small-window-four-crew",Vector2(small_view.x*.5,380),1.0,crew_lines,{},300)
	await capture("small-window-small-hud",Vector2(small_view.x/.65*.5,380/.65),.65,crew_lines,{},300)
	root.size = Vector2i(1440,900)
	for unused in 3: await process_frame
	game.camera.zoom = Vector2.ONE*1.25
	await capture("four-crew-top",Vector2(720,86),1.0,["Ich verteidige den Reifenwechsel. Du kümmerst dich um die Reparatur!","Die Munition liegt im Lager. Nehmt euch etwas, bevor die nächste Welle kommt.","W".repeat(240),"Ich bringe das Material zur Werkbank und komme dann wieder nach oben."])
	await capture("four-crew-left-top",Vector2(12,76),1.0,["W".repeat(240),"W".repeat(240),"W".repeat(240),"W".repeat(240)])
	await capture("four-crew-right-bottom-scaled",Vector2(1440/1.4-12,900/1.4-76),1.4,["W".repeat(240),"W".repeat(240),"W".repeat(240),"W".repeat(240)])
	LocaleText.set_locale("en",false)
	await capture("literal-public-text-en",Vector2(720,400),1.0,["Danke!","Bereit!","Munition liegt im Lager.",""],{3:"thanks"})
	check(await Cleanup.free_scene(game,self),"prepared game and audio retire cleanly")
	var output := FileAccess.open(folder+"/prepared-states.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"states":states,"checks":checks,"failures":failures,"limitations":"Prepared co-located actors and delivered public text; no external voice, network or play session."},"\t"))
	output.close()
	print("WORKER SPEECH NATIVE: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
