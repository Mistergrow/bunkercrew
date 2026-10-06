extends SceneTree
## Run unchanged against core or a private pack installed before Godot starts.
## Identity and gameplay values belong to the actor; authored profiles are aliases.
const Registry := preload("res://scripts/content_registry.gd")
const Roster := preload("res://scripts/crew_roster.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Dialogue := preload("res://scripts/story_dialogue_catalog.gd")
const GoreProtocol := preload("res://scripts/combat_gore_protocol.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHARACTER CONTENT: "+label)

func gore(id: String) -> Dictionary:
	return {"material":"flesh","point":Vector2(100,100),"direction":Vector2.RIGHT,"strength":1.0,"part":0,"joint":Vector2(100,100),"tip":Vector2(100,100),"character":id,"front":false,"facing":1.0,"player_id":1}

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var extension_id := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--extension-id="): extension_id = argument.trim_prefix("--extension-id=")
	check(Registry.diagnostics().is_empty(),"all installed catalogs are valid")
	if not extension_id.is_empty():
		check(CharacterCatalog.contains(extension_id),"required ninth fixture exists before catalogs initialize")
		if not CharacterCatalog.contains(extension_id):
			quit(1)
			return
	check(PartyConfig.DEFAULT_CHARACTERS==["mara","branko","ivo","nora"],"additions never replace the four starter slots")
	check(Roster.BASE_CREW==PartyConfig.DEFAULT_CHARACTERS,"roster and party derive the same starters")
	check(Roster.LEGACY_RECRUITS=={"nora":"refinery_archive","levin":"radar_archive","selma":"dam_vault"},"old three secured-site rewards remain exact")
	check(CharacterCatalog.reload_multiplier("levin")==0.85 and CharacterCatalog.medical_speed("selma")==1.25,"existing authored medical/reload bonuses survive data migration")
	check(Dance.IDS.size()==CharacterCatalog.CHARACTERS.size(),"dance preferences enumerate every registered identity")
	check(CharacterCatalog.CHARACTERS.is_read_only(),"compatibility roster is immutable")
	check(CharacterCatalog._presentation_profiles.is_read_only(),"profile index is immutable")
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		check(entry.is_read_only() and CharacterCatalog._presentation_profiles[entry.id].is_read_only(),str(entry.id)+" definition and profile aliases are recursively immutable")
	var reads_before := Registry.read_count()
	var probe := Registry.data("characters","mara")
	probe["hp"] = 9999
	check(CharacterCatalog.data("mara").hp==100,"catalog callers cannot mutate the registry definition")
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		var id := str(entry.id)
		var visual := CharacterCatalog.presentation_id(id,"visual")
		var motion := CharacterCatalog.presentation_id(id,"motion")
		var dance := CharacterCatalog.presentation_id(id,"dance")
		var voice := CharacterCatalog.presentation_id(id,"voice")
		check(CharacterCatalog.data(id).id==id,id+" keeps its true identity")
		check(Identity.body(id)==Identity.body(visual) and Identity.arms(id)==Identity.arms(visual) and Identity.head(id,true)==Identity.head(visual,true),id+" resolves complete visual profile")
		check(Personality.frames(id)==Personality.frames(motion) and Personality.wait_range(id)==Personality.wait_range(motion) and Personality.gestures(id)==Personality.gestures(motion),id+" resolves declared motion profile")
		check(Dance.UNIQUE_STYLES[id]==Dance.UNIQUE_STYLES[dance] and Dance.character_style(id)==Dance.character_style(dance),id+" resolves authored repertoire and default style")
		check(Dance.valid_profiles({id:{"style":Dance.UNIQUE_STYLES[id][0],"intensity":0.75}}),id+" may save its own aliased dance preference")
		check(not Dance.allowed(id,Dance.UNIQUE_STYLES["branko" if dance!="branko" else "mara"][0],10),id+" cannot borrow an undeclared choreography")
		for beat: float in [0.0,0.25,1.0,3.5]:
			check(Rhythm.choreography("crew_two_step",beat,id)==Rhythm.choreography("crew_two_step",beat,dance),id+" interprets shared choreography using declared temperament")
		for locale: String in LocaleText.SUPPORTED:
			LocaleText.set_locale(locale,false)
			var line := Dialogue.line("crew_wall",id)
			check(not line.is_empty() and line.speaker_id==id and line.source_text==Dialogue.source_line("crew_wall",voice).text,id+" speech retains identity and declared script")
			check(line.voice_path==Dialogue.recording_path("crew_wall",voice,locale) and ResourceLoader.exists(line.voice_path),id+" uses available declared recording")
		check(GoreProtocol.valid_data(gore(id)),id+" cosmetic hit event accepts the actual registered identity")
		check(GoreProtocol.valid_event({"serial":1,"actor":"player:1","data":gore(id)}),id+" cosmetic packet retains player identity")
	check(not GoreProtocol.valid_data(gore("missingpack:nobody")),"unknown character cosmetic packets are rejected")
	check(Registry.read_count()==reads_before,"repeated profile adapters never reopen content sources")
	var events := CombatEvents.new()
	events.persistence_enabled = false
	if not extension_id.is_empty():
		check(events.record_character_dance_level(extension_id,10) and events.dance_level(extension_id)==10,"ninth progress owns its actual ID")
		check(events.dance_level(CharacterCatalog.presentation_id(extension_id,"dance"))==1,"alias source does not inherit ninth progress")
		check(events.unlocked_dance_count()==0 and not events.unlocked.has("all_dance_moves"),"aliased pack repertoire does not duplicate the base collection goal")
	for id: String in Dance.BUILTIN_IDS: events.record_character_dance_level(id,10)
	check(events.unlocked_dance_count()==40 and events.unlocked.has("all_dance_moves"),"the existing forty authored-move collection goal stays stable")
	events.free()
	LocaleText.set_locale("de",false)
	InputSetup.install()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	var selected := extension_id if not extension_id.is_empty() else "rika"
	if not CharacterCatalog.is_unlocked(selected): Roster.unlocked[selected]=true
	game.selected_characters.assign([selected,"branko","ivo","nora"])
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.running = false
	for unused in 3: await process_frame
	var actor: Worker = game.players[0]
	check(actor.character_id==selected and actor.max_hp==float(CharacterCatalog.data(selected).hp),"real game spawns selected identity with its own hit points")
	check(actor.damage_multiplier()==float(CharacterCatalog.data(selected).damage),"real game uses own damage rather than alias source stats")
	var worker_visual := actor.get_node("PixelVisual")
	check(worker_visual.rhythm.character_id==selected,"actual visual beat state keeps actor ID")
	check(game.audio.dance_profiles.has(selected),"actual music configuration includes added identity")
	game.dialogue.reset()
	check(game.dialogue.enqueue("crew_wall",selected,1,800),"real dialogue accepts selected actor's identity")
	game.dialogue.advance(0.1)
	check(not game.dialogue.active.is_empty() and game.dialogue.active.speaker_id==selected and game.dialogue.active.anchor_player_id==1 and game.dialogue.voice.stream.resource_path==Dialogue.recording_path("crew_wall",selected,"de"),"real recorded speech keeps selected actor anchor and declared voice")
	check(game.audio.play_footstep("dry",actor.global_position,1.0,false,true,"",selected),"real spatial footsteps accept registered character")
	var latest: AudioStreamPlayer2D
	var serial := -1
	for step_voice: AudioStreamPlayer2D in game.audio.movement.voices:
		if int(step_voice.get_meta("serial",0))>serial:
			serial = int(step_voice.get_meta("serial",0))
			latest = step_voice
	var motion_profile := CharacterCatalog.presentation_id(selected,"motion")
	var boot_family := "boot_heavy" if motion_profile=="branko" else "boot_light" if motion_profile in ["ivo","levin"] else "boot_standard"
	check(is_instance_valid(latest) and latest.get_meta("character_id")==selected and latest.get_meta("kind")==boot_family+"_dry","actual footstep keeps actor identity and declared boot family")
	check(await Cleanup.free_scene(game,self),"real ninth-character scene releases cleanly")
	print("CHARACTER CONTENT: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
