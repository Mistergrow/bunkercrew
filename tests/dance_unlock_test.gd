extends SceneTree
## Real character-level signals, durable cosmetic progression and safe UI.
const Dances := preload("res://scripts/worker_dance_catalog.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var capture_enabled := false

class World extends Node2D:
	var players: Array = []
	var network: Node
	var upgrades: Node
	var started := true

class Actor extends Node2D:
	var game: Node
	var character_id := "mara"
	var player_id := 1
	var max_hp := 100.0
	var hp := 100.0
	var progression: PlayerProgression
	func _ready() -> void:
		progression = PlayerProgression.new()
		add_child(progression)
	func is_downed() -> bool: return false

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func service(path: String) -> CombatEvents:
	var result := CombatEvents.new()
	result.save_path = path
	result.persistence_enabled = false
	return result

func capture(name: String) -> void:
	if not capture_enabled: return
	for index in 3: await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://artifacts/dance-unlocks"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	check(root.get_texture().get_image().save_png(directory+"/"+name+".png")==OK,"rendered dance UI capture saved: "+name)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Run dance_unlock_test with --no-profile-save")
		quit(2)
		return
	capture_enabled = DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	LocaleText.set_locale("de",false)
	var prefix := "user://dance-unlock-test-%d"%OS.get_process_id()
	var path := prefix+".cfg"
	var no_save_path := prefix+"-no-save.cfg"
	var invalid_path := prefix+"-invalid.cfg"
	var world := World.new()
	root.add_child(world)
	var events := service(path)
	events.game = world
	world.add_child(events)
	events.set_process(false)
	for index in 2:
		var actor := Actor.new()
		actor.game = world
		actor.character_id = ["mara","branko"][index]
		actor.player_id = index+1
		world.add_child(actor)
		actor.progression.set_physics_process(false)
		world.players.append(actor)
		events.track_player(actor)
	var mara: Actor = world.players[0]
	var branko: Actor = world.players[1]
	check(events.dance_level("mara")==1 and events.unlocked_dance_count()==0,"new characters begin with no own unlocked moves")
	for id: String in Dances.IDS:
		check(Dances.available_styles(id,1)==Dances.SHARED_STYLES,id+": exactly three shared moves are available at level1")
		for index in 5:
			var style: String = Dances.UNIQUE_STYLES[id][index]
			var level: int = Dances.UNLOCK_LEVELS[index]
			check(not Dances.allowed(id,style,level-1) and Dances.allowed(id,style,level),id+": unique move unlocks at its actual character level")
			var foreign := "branko" if id!="branko" else "mara"
			check(not Dances.allowed(foreign,style,30),id+": own move cannot be used by another character")
	mara.progression.award_damage(500)
	check(mara.progression.level==2 and events.dance_level("mara")==2,"real XP level_up signal immediately records Mara's dance milestone")
	check(events.dance_level("branko")==1 and events.unlocked_dance_count()==1,"Mara's real level cannot unlock Branko's moves")
	branko.progression.level = 8
	events._watch_dance_progression()
	check(events.dance_level("branko")==8,"the existing watch captures a campaign-restored character level")
	check(not events.record_character_dance_level("branko",4) and events.dance_level("branko")==8,"lower later run levels never remove learned dances")
	for invalid in [0,-1,31,1000,10.0,NAN,"10",true,[10]]:
		check(not events.record_character_dance_level("nora",invalid) and events.dance_level("nora")==1,"invalid level is rejected without a cosmetic unlock")
	check(not events.record_character_dance_level("future_character",10) and events.dance_level("future_character",30)==1,"unknown character IDs cannot enter dance records")
	check(not FileAccess.file_exists(path),"--no-profile-save prevents ordinary level events from writing the profile")
	var config := ConfigFile.new()
	config.set_value("future_section","keep",77)
	config.set_value("achievements","first_kill",true)
	config.set_value("dance_levels","future_character",20)
	check(config.save(path)==OK,"isolated legacy fixture created")
	events.persistence_enabled = true
	events._save_records()
	var reloaded := service(path)
	reloaded.load_records()
	check(reloaded.dance_level("mara")==2 and reloaded.dance_level("branko")==8,"highest character dance levels survive a persistent reload")
	check(reloaded.unlocked.has("first_kill") and not reloaded.dance_levels.has("future_character"),"legacy achievement stays earned while unknown saved dance IDs are ignored")
	config.load(path)
	check(config.get_value("future_section","keep",0)==77 and config.get_value("dance_levels","future_character",0)==20,"dance persistence preserves unrelated existing records")
	config.set_value("dance_levels","mara",10)
	config.save(path)
	events._save_records()
	config.load(path)
	check(config.get_value("dance_levels","mara",0)==10 and events.dance_level("mara")==10,"saving merges a higher durable level instead of overwriting it")
	for invalid in [0,-3,31,10.0,"10",true,[10],NAN]:
		var malformed := ConfigFile.new()
		malformed.set_value("dance_levels","nora",invalid)
		malformed.set_value("dance_levels","levin",6)
		malformed.set_value("dance_levels","future_character",10)
		malformed.save(invalid_path)
		var loaded := service(invalid_path)
		loaded.load_records()
		check(loaded.dance_level("nora")==1 and loaded.dance_level("levin")==6 and not loaded.dance_levels.has("future_character"),"malformed saved levels do not block independent valid character progress")
		loaded.free()
	var earned_legacy := ConfigFile.new()
	earned_legacy.set_value("achievements","all_dance_moves",true)
	for identity: String in ["mara","branko","ivo","nora","levin","selma"]: earned_legacy.set_value("dance_levels",identity,10)
	check(earned_legacy.save(invalid_path)==OK,"Isolated previous thirty-move completion fixture is persisted")
	var legacy_complete:=service(invalid_path)
	legacy_complete.load_records()
	check(legacy_complete.unlocked.has("all_dance_moves") and legacy_complete.unlocked_dance_count()==30 and legacy_complete.dance_level("oskar")==1 and legacy_complete.dance_level("rika")==1,"Previously earned thirty-move achievement stays earned without granting new character XP")
	legacy_complete.free()
	var all_moves := service(no_save_path)
	world.add_child(all_moves)
	all_moves.set_process(false)
	var earned: Array[String] = []
	all_moves.event.connect(func(kind: String,data: Dictionary):
		if kind=="achievement": earned.append(str(data.id)))
	for index in 7: all_moves.record_character_dance_level(Dances.IDS[index],10)
	check(all_moves.unlocked_dance_count()==35 and not all_moves.unlocked.has("all_dance_moves"),"seven fully trained characters do not grant the all-moves achievement")
	all_moves.record_character_dance_level("rika",8)
	check(all_moves.unlocked_dance_count()==39 and not all_moves.unlocked.has("all_dance_moves"),"the fortieth unique move cannot be granted early")
	all_moves.record_character_dance_level("rika",10)
	check(all_moves.unlocked_dance_count()==40 and all_moves.unlocked.has("all_dance_moves") and all_moves.platform.pending.has("LS_ALL_DANCE_MOVES"),"all eight actual level10 milestones unlock the forty-move achievement and optional platform queue")
	all_moves.record_character_dance_level("rika",20)
	all_moves._save_records()
	check(earned.count("all_dance_moves")==1 and not FileAccess.file_exists(no_save_path),"achievement notification occurs once and --no-profile-save remains effective")
	var dance_record: Dictionary = all_moves.records().filter(func(row): return row.id=="all_dance_moves")[0]
	check(dance_record.progress==40 and dance_record.goal==40,"achievement exposes exact cosmetic progress")
	reloaded.free()
	events.persistence_enabled = false
	check(await CLEANUP.free_scene(world,self),"progression fixture releases its bound actor callbacks")
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.hud._toggle_personnel()
	await process_frame
	var panel: PersonalPanel = game.hud.personal_panel
	panel.select_tab("dances")
	check(game.players.is_empty() and not panel.select_dance("crew_bounce") and panel.dance_buttons.all(func(button): return not button.visible),"pre-game personnel dance tab is safe with no player at index0")
	await capture("menu-no-player")
	game.hud._close_personnel()
	game.selected_characters.assign(["mara","branko","ivo","mara"])
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	game.rounds.set_process(false)
	for player: Node in game.players: player.set_physics_process(false)
	game.hud._toggle_personnel()
	await process_frame
	panel = game.hud.personal_panel
	panel.select_tab("dances")
	check(panel.player_buttons.size()==2,"personnel rebuilds real player tabs after a no-player menu preview")
	check(panel.dance_buttons.size()==9 and panel._dance_style_ids==Dances.styles_for("mara"),"personnel presents automatic, three shared and five own dance options")
	check(panel.dance_buttons.slice(1,4).all(func(button): return not button.disabled) and panel.dance_buttons.slice(4).all(func(button): return button.disabled),"level1 UI enables shared moves and shows every own move locked")
	check(panel.select_dance("crew_two_step") and game.audio.dance_profiles.mara.style=="crew_two_step","actual dance selection applies the valid cosmetic audio profile")
	panel.dance_buttons[1].pressed.emit()
	check(game.audio.dance_profiles.mara.style=="crew_bounce","shared dance button callback selects its own indexed option")
	var chosen: String = game.audio.dance_profiles.mara.style
	check(not panel.select_dance("mara_pivot_finish") and not panel.select_dance("branko_foundry_stomp") and not panel.select_dance("not_a_style") and game.audio.dance_profiles.mara.style==chosen,"locked, foreign and unknown dance choices cannot change the selected profile")
	await capture("level1-de")
	game.players[0].progression.award_damage(500)
	check(not panel.dance_buttons[4].disabled and panel.dance_buttons[5].disabled and panel.select_dance("mara_precision_step"),"real level2 signal refreshes UI and enables exactly the first own move")
	panel.dance_buttons[4].pressed.emit()
	check(game.audio.dance_profiles.mara.style=="mara_precision_step","unlocked own dance button reaches the actual character audio configuration")
	var actual_level: int = game.players[0].progression.level
	var actual_xp: float = game.players[0].progression.xp
	game.combat_events.record_character_dance_level("mara",10)
	check(panel.dance_buttons.slice(4).all(func(button): return not button.disabled) and game.players[0].progression.level==actual_level and game.players[0].progression.xp==actual_xp,"durable cosmetic unlocks never inject gameplay XP or levels")
	panel.select_player(1)
	check(panel._dance_style_ids==Dances.styles_for("branko") and panel.dance_buttons.slice(4).all(func(button): return button.disabled),"changing actor keeps personal repertoires and unlocks separate")
	panel.select_player(0)
	for language in ["de","en"]:
		LocaleText.set_locale(language,false)
		panel.refresh_locale()
		var fit := true
		for button: Button in panel.dance_buttons:
			fit = fit and UiArt.FONT.get_string_size(button.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x<button.size.x-24
		check(fit,language+": complete move titles fit their actual button widths")
		await capture("level10-"+language)
	LocaleText.set_locale("de",false)
	check(await CLEANUP.free_scene(game,self),"real personnel and native audio leave with the scene")
	for candidate in [path,no_save_path,invalid_path]:
		if FileAccess.file_exists(candidate): DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
	print("DANCE UNLOCKS: %d/%d checks passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
