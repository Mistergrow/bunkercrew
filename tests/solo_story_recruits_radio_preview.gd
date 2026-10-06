extends SceneTree
## Native actual first-air presentation for both new crew; SAN is its own speaker.
const Clean:=preload("res://tests/scene_cleanup.gd")
const Roster:=preload("res://scripts/crew_roster.gd")
const Catalog:=preload("res://scripts/air_raid_intro_catalog.gd")
const OUT:="res://artifacts/solo-story/recruits/"
var view: SubViewport
var game: Node
var checks:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func frames() -> void:
	for tick in 4: await process_frame
func prepare(identity: String) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.selected_characters.assign([identity])
	game.start_scenario(1,{"environment":"storm_dam","position":"left","build_type":"bastion"})
	game.rounds.set_process(false)
	game.air_raid_intro.set_process(false)
	game.rounds.wave=6
	game.flak_station.unlock()
	var actor: Worker=game.players[0]
	actor.inventory={"steel":3,"concrete":2,"ammo":1}
	for kind: String in ["steel","concrete","ammo"]:
		actor.selected_kind=kind
		for transfer in 8:
			if int(actor.inventory.get(kind,0))<=0: break
			game.flak_station.interact(actor,Balance.TRANSFER_TIME)
	game.flak_station.interact(actor,3.0)
	check(game.air_defense_ready(),"Native first-air fixture commissions the actual finite AA structure")
	game.rounds.wave=7
	game.rounds.phase="build"
	game.rounds.begin_warning()
	game.rounds._begin_attack()
	check(game.players[0].character_id==identity,"Actual pre-start selection creates the requested worker: "+identity)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	view=SubViewport.new()
	view.size=Vector2i(1440,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	Roster.persistence_enabled=false
	Roster.unlock("oskar")
	Roster.unlock("rika")
	for identity: String in ["oskar","rika"]:
		prepare(identity)
		var roster:=EnemyCatalog.wave_roster(7,game.rounds.wave_total,true)
		for language: String in ["de","en"]:
			LocaleText.set_locale(language,false)
			paused=false
			game.hud.overlay=""
			game.campaign.air_raid_intro_seen=false
			game.air_raid_intro.seen=false
			check(game.air_raid_intro.before_spawn(7,roster.find("scout_drone"),roster.size()) and game.air_raid_intro.context.character_id==identity and game.players[0].character_id==identity,identity+"/"+language+": actual native controller begins with this real selected worker")
			game.air_raid_intro.elapsed=3.5
			game.hud.air_raid_panel._process(0)
			# Speech uses real wall time; GPU readback may outlast a brief line.
			# Its audible playback is independently proven by the native mix test.
			await frames()
			await RenderingServer.frame_post_draw
			var panel: Control=game.hud.air_raid_panel
			var line:=Catalog.line(identity)
			check(panel.dialogue.portrait_id=="san" and panel.dialogue.speaker_id=="san" and panel.speaker_label.text==line.speaker_name and panel.caption_label.text==line.text,identity+"/"+language+": native caption explicitly belongs to SAN")
			check(panel.portrait_canvas is Node2D and panel.voice.can_process() and panel.voice.stream!=null and panel.voice.stream.resource_path==line.voice_path,identity+"/"+language+": robot portrait and actual matching localized voice exist")
			var image:=view.get_texture().get_image()
			check(image.get_size()==view.size and image.save_png(OUT+"air-radio-"+identity+"-"+language+".png")==OK,"Actual radio presentation capture exported")
			game.air_raid_intro.finish(true)
			await frames()
		paused=false
		check(await Clean.free_scene(game,self),"Real selected worker scene retires: "+identity)
	paused=false
	check(await Clean.free_scene(view,self),"Native radio fixture releases game, speech and flyover")
	print("SOLO RECRUIT RADIO PREVIEW: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
