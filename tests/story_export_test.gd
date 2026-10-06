class_name BetaStoryExportCheck
extends SceneTree
## Run from an empty directory with --main-pack to catch missing exported data.
const DialogueCatalog := preload("res://scripts/story_dialogue_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run with --no-profile-save")
		quit(1)
		return
	check(ScenarioCatalog.environments().size()==9,"All nine world definitions survive export")
	for entry: Dictionary in ScenarioCatalog.environments():
		check(ScenarioCatalog.texture(entry.path)!=null,str(entry.id)+" panorama loads from the pack")
	for path in ["character_motion_frames.json","worker_frames.json","armor_anchors.json","character_visuals.json"]:
		var metadata=JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/"+path))
		check(metadata is Dictionary and not metadata.is_empty(),path+" survives as runtime metadata")
	var voices:=0
	var per_locale:=0
	for id: String in DialogueCatalog.LINES:
		for speaker: String in DialogueCatalog.SPEAKERS:
			if not DialogueCatalog.source_line(id,speaker).is_empty(): per_locale+=1
	var expected_voices:=per_locale*LocaleText.SUPPORTED.size()
	for locale: String in LocaleText.SUPPORTED:
		LocaleText.set_locale(locale,false)
		check(FileAccess.file_exists("res://locales/"+locale+".json"),locale+" global catalog survives export")
		var grenadier:=DialogueCatalog.line("warning_grenadier")
		check(grenadier.text==("Granatwerfer! Bleibt in Deckung." if locale=="de" else "Grenade launcher! Stay in cover."),locale+" grenade warning has its exact localized script")
		for id: String in DialogueCatalog.LINES:
			for speaker: String in DialogueCatalog.SPEAKERS:
				var line:=DialogueCatalog.line(id,speaker)
				if line.is_empty(): continue
				var stream=load(line.voice_path)
				check(stream is AudioStreamWAV and stream.get_length()>.8,str(line.voice_path)+" is a playable exported recording")
				check(line.text==line.source_text if locale=="de" else line.text!=line.source_text,locale+" exported subtitle matches its selected language")
				voices+=1
	check(voices==expected_voices,"Every authored recording ships in both supported languages")
	check(LocaleText.current_locale()=="en" and LocaleText.text("BUNKERCREW")=="BUNKERCREW","English presentation loads the current brand from the exported catalog")
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	await process_frame
	game.story_mode=true
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"right"})
	paused=false
	await process_frame
	check(game.scenario_options.environment=="mountain_pass","Exported story starts in the selected world")
	check(is_instance_valid(game.microphone) and is_instance_valid(game.voice),"Microphone and voice services survive exported scenario construction")
	check(not game.microphone.capturing and not game.voice.speaking,"Exported game never opens a microphone automatically")
	check(is_instance_valid(game.story) and game.story.enabled and game.story.blocks_build(),"Prologue waits for the actual wall in the exported game")
	check(is_instance_valid(game.story.wall) and is_instance_valid(game.story.relay),"Exported story constructs the wall and field radio")
	check(game.dialogue._streams.size()==expected_voices,"Exported dialogue has both complete voice banks available")
	check(game.story.objective().contains("Hold E"),"Exported story objectives use the chosen language")
	check(is_instance_valid(game.weather.storm_events),"Exported weather includes the tree lightning event")
	for family: String in ["rifle","shotgun","arc","cannon","flak"]:
		for phase: String in ["open","load","close"]:
			var sound := "reload_%s_%s"%[family,phase]
			check(game.audio.variants.has(sound) and game.audio.variants[sound].size()==3 and game.audio.variants[sound].all(func(stream):return stream is AudioStreamWAV and stream.get_length()>0.05),sound+" exports all three playable variants")
	for sound: String in ["weapon_mount","weapon_switch"]:
		check(game.audio.variants.has(sound) and game.audio.variants[sound].size()==3,sound+" exports the handling bank")
	check(game.upgrades.node_data("medic_logistics").get("cost")==4 and is_instance_valid(game.medic.logistics),"Exported robot logistics and research are available")
	check(is_instance_valid(game.combat_gore) and game.combat_gore.level==2,"Exported game provides the three-level violence renderer")
	check(game.perimeter.sites.size()==3 and game.perimeter.sites.all(func(site):return site.side==-1 and (site.tier==1 and site.hp==120 if site.role=="fence" else site.tier==0)),"Exported right bunker provides a live west courtyard fence and two unbuilt sentry sites")
	var perimeter_atlas=load("res://assets/perimeter/components_v2.png")
	check(perimeter_atlas is Texture2D and perimeter_atlas.get_size()==Vector2(1536,1024),"The exterior defense sprite atlas survives export with its authored layout")
	check(game.upgrades.node_data("perimeter_automation").get("cost")==7 and game.upgrades.node_data("perimeter_flak").is_empty(),"Compact sentry research survives export without the retired exterior flak")
	check(game.perimeter.sites.filter(func(site):return site.role=="ground").size()==2,"The exported defense line provides two distinct compact sentries")
	var compact_atlas=load("res://assets/perimeter/components_v3.png")
	check(compact_atlas is Texture2D and compact_atlas.get_size()==Vector2(1536,1024),"Compact sentry and industrial-weather sprites survive export")
	check(LocaleText.text("Gewaltdarstellung")=="Violence effects" and LocaleText.text("Betonzaun")=="Concrete fence","Exported English options and defense names are localized")
	check(not game.air_defense_ready() and not game.rounds.air_wave_enabled,"Exported story cannot start with unearned air contacts")
	game.turret.enter(game.players[0])
	game.players[0].get_node("PixelVisual")._process(0.0)
	check(game.players[0].get_node("PixelVisual").special_pose=="mounted","Exported character uses the shared articulated controls")
	game.rounds.set_process(false)
	var roster:=EnemyCatalog.wave_roster(6,8,false)
	for index in roster.size():
		if roster[index] in ["grenadier","rifle_guard"]: game.spawn_enemy(6,index,roster.size())
	var soldiers:=get_nodes_in_group("human_enemies")
	check(soldiers.size()==3,"Exported waves include one human grenadier and two guards")
	for soldier in soldiers:
		soldier.set_physics_process(false)
		check(soldier.get_script().resource_path=="res://scripts/ground_infantry.gd" and is_instance_valid(soldier.infantry),"Exported infantry uses its human rig and scene")
	game.set_camera_zoom(1.7)
	check(game.camera_settings().mode=="follow" and is_equal_approx(game.camera_settings().zoom,1.7),"Exported local camera accepts independent zoom settings")
	game.hud._toggle_audio()
	await process_frame
	check(is_instance_valid(game.hud.options_panel) and game.hud.options_panel.tab_buttons.size()==5,"Exported F4 opens the five-page options menu")
	game.hud._close_audio()
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Exported scene releases its audio and world cleanly")
	LocaleText.set_locale("de",false)
	print("STORY EXPORT: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
