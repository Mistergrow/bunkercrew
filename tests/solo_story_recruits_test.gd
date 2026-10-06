extends SceneTree
## Real shared-rig workers, side-only NPC interactions and isolated atomic roster.
const Roster := preload("res://scripts/crew_roster.gd")
const Npc := preload("res://scripts/solo_story_npc.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Gestures := preload("res://scripts/worker_gesture_library.gd")
const Dances := preload("res://scripts/worker_dance_catalog.gd")
const Moves := preload("res://scripts/worker_dance_moves.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const Clean := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var results: Array[Dictionary] = []

class World extends Node2D:
	var players: Array = []
	var started := false
	var upgrades: Node
	var network: Node
	var authoritative := true
	func can_affect_world() -> bool: return authoritative
	func sound(_kind: String) -> void: pass
	func fx(_point: Vector2,_color: Color,_amount: int) -> void: pass
	func notify(_text: String) -> void: pass

class Director extends Node:
	var enabled := true
	var opened := 0
	var active := false
	var selected := ""
	func encounter_hint(identity: String) -> String: return "Encounter " + identity
	func open_encounter(identity: String,_worker: Node,_npc: Node2D) -> bool:
		if active: return false
		active=true
		selected=identity
		opened+=1
		return true

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,description: String) -> void:
	checks+=1
	results.append({"passed":value,"description":description})
	if not value:
		failures+=1
		push_error(description)

func worker(world: World,identity: String,x: float) -> Worker:
	var actor: Worker=load("res://scenes/player.tscn").instantiate()
	actor.game=world
	actor.character_id=identity
	actor.position=Vector2(x,430)
	world.add_child(actor)
	world.players.append(actor)
	actor.set_physics_process(false)
	actor.get_node("WorkerWeapon").set_physics_process(false)
	actor.progression.set_physics_process(false)
	return actor

func reset_roster(path: String,persistent: bool) -> void:
	Roster.save_path=path
	Roster.persistence_enabled=persistent
	Roster.unlocked.clear()
	Roster._loaded=false
	Roster.last_error=""

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		push_error("Use --no-profile-save; persistent assertions use an isolated test filename.")
		quit(2)
		return
	InputSetup.install()
	LocaleText.set_locale("de",false)
	var folder := "user://solo-recruits-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := folder+"/crew.cfg"
	var initial := ConfigFile.new()
	initial.set_value("crew","levin",true)
	initial.set_value("crew","future_identity",true)
	initial.set_value("future_section","keep",77)
	check(initial.save(path)==OK,"Isolated legacy ConfigFile fixture exists")
	reset_roster(path,true)
	check(Roster.is_unlocked("levin") and not Roster.is_unlocked("oskar") and not Roster.is_unlocked("rika"),"Original rescue file loads without granting new recruits")
	check(not Roster.is_unlocked("future_identity"),"Unknown saved identity never grants a playable character")
	var before := FileAccess.get_sha256(path)
	check(not Roster.unlock("future_identity") and not Roster.unlock(""),"Unknown direct unlocks are rejected")
	check(FileAccess.get_sha256(path)==before,"Rejected IDs leave the durable roster unchanged")
	check(Roster.unlock_for_site("quarry").is_empty() and Roster.unlock_for_site("power_station").is_empty(),"Legacy site rewards cannot silently auto-unlock Oskar or Rika")
	check(Roster.unlock("oskar") and Roster.is_unlocked("oskar"),"Explicit Oskar rescue commits a real atomic roster update")
	var oskar_sha := FileAccess.get_sha256(path)
	var backup_sha := FileAccess.get_sha256(path+".bak")
	check(Roster.unlock("oskar") and FileAccess.get_sha256(path)==oskar_sha and FileAccess.get_sha256(path+".bak")==backup_sha,"Repeated rescue is successful and never rewrites primary or backup")
	Roster.save_path=folder+"/missing-parent/crew.cfg"
	var memory := Roster.unlocked.duplicate()
	check(not Roster.unlock("rika") and Roster.unlocked==memory and Roster.last_error=="write_failed","Unwritable save refuses rescue and rolls back memory")
	Roster.save_path=path
	check(FileAccess.get_sha256(path)==oskar_sha,"Failed rescue preserves the last durable roster byte-for-byte")
	check(Roster.unlock("rika"),"A later valid explicit Rika rescue succeeds")
	var config := ConfigFile.new()
	config.load(path)
	check(config.get_value("future_section","keep",0)==77 and config.get_value("crew","future_identity",false)==true,"Atomic writes preserve unrelated legacy sections and unknown future records")
	reset_roster(path,true)
	check(Roster.is_unlocked("oskar") and Roster.is_unlocked("rika") and Roster.is_unlocked("levin"),"Explicit new rescues survive an actual ConfigFile reload")
	# Structurally valid but semantically corrupt primary must use the good backup.
	config.set_value("crew","levin","broken_boolean")
	config.save(path)
	var good_backup := FileAccess.get_sha256(path+".bak")
	reset_roster(path,true)
	check(Roster.is_unlocked("oskar") and Roster.is_unlocked("levin"),"Malformed primary record recovers valid earlier rescues from backup")
	check(Roster.unlock("rika") and FileAccess.get_sha256(path+".bak")==good_backup,"Recovery cannot replace a good backup with corrupt primary data")
	before=FileAccess.get_sha256(path)
	reset_roster(path,false)
	check(not Roster.is_unlocked("levin"),"--no-profile-save presentation session does not read persistent rescue records")
	check(Roster.unlock("oskar") and Roster.unlock("rika") and FileAccess.get_sha256(path)==before,"No-profile unlocks remain session-local without touching any existing file")
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		check(Dances.IDS.has(entry.id) and Defaults.dance_profiles().has(entry.id),"Every selectable identity has a complete default dance profile: "+entry.id)
	check(Defaults.MUSIC_VOLUME==.5 and Defaults.SFX_VOLUME==.5 and Defaults.VOICE_VOLUME==.5 and Defaults.PARTNER_VOLUME==.5,"All four established volume slider defaults remain exactly fifty percent")
	var world := World.new()
	root.add_child(world)
	var floor_body := StaticBody2D.new()
	var collider := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size=Vector2(1200,20)
	collider.shape=shape
	floor_body.position=Vector2(300,440)
	floor_body.add_child(collider)
	world.add_child(floor_body)
	var oskar := worker(world,"oskar",170)
	var rika := worker(world,"rika",400)
	check(oskar.max_hp==110 and oskar.capacity()==8 and is_equal_approx(oskar.movement_multiplier(),.94),"Oskar's real worker health/carry/slow-stride tradeoff applies")
	check(rika.max_hp==92 and rika.capacity()==5 and is_equal_approx(rika.work_multiplier(),1.20),"Rika's real worker service speed and lighter load apply")
	check(is_equal_approx(oskar.damage_multiplier(),.98) and is_equal_approx(rika.damage_multiplier(),.94),"New profiles retain finite damage tradeoffs rather than new combat powers")
	var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_motion_frames.json"))
	var pose_signatures: Dictionary={}
	for identity: String in ["oskar","rika"]:
		for texture in [Identity.body(identity),Identity.arms(identity),Identity.torso(identity),Identity.head(identity),Identity.torso(identity,true),Identity.head(identity,true)]:
			check(texture!=null and texture.get_image().get_used_rect().has_area(),identity+": real nonempty body/head/arms/back sprite")
		check(Identity.body(identity)!=Identity.body("mara") and Identity.head(identity)!=Identity.head("branko"),identity+": textures never fall back to existing outfits")
		var frames := Personality.frames(identity)
		check(frames.size()==19 and frames.weapon.size()==4 and frames.climb.size()==8,identity+": all nineteen runtime states include exact weapon and ladder frames")
		var base := "branko" if identity=="oskar" else "ivo"
		check(frames.mine[3].tool==metadata[base].mine[3].tool and frames.weapon==metadata[base].weapon,identity+": real mining strike and weapon grips preserve native source-rig contracts")
		var notice = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/"+identity+".source.json"))
		for filename: String in notice.assets:
			check(FileAccess.get_sha256("res://assets/workers/"+filename)==notice.sha256[filename],identity+": current sprite matches adjacent source SHA "+filename)
		var history = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/identities/source-history-20261005.json"))
		check(notice.previous_source_sha256==history.sources[identity].notice_sha256,identity+": original sprite provenance remains linked to its archived source notice")
		check(Personality.gestures(identity).size()>=2 and Personality.reaction(identity,"work_finished")!="" and Personality.reaction(identity,"wave_clear")!="",identity+": owns idle and real-action reaction gestures")
		for gesture: String in Gestures.names(identity):
			var first := WorkerPoseArt.sample(gesture,.0,0,Vector2(24,-13),identity)
			var middle := WorkerPoseArt.sample(gesture,.45,0,Vector2(24,-13),identity)
			check(first.hands!=middle.hands or first.shoulder!=middle.shoulder or first.head_tilt!=middle.head_tilt,identity+": authored gesture actually articulates "+gesture)
		check(Dances.UNIQUE_STYLES[identity].size()==5 and Dances.available_styles(identity,1)==Dances.SHARED_STYLES,identity+": five exclusive XP moves plus three common level-one dances")
		for style: String in Dances.UNIQUE_STYLES[identity]:
			check(Moves.owns(style) and Dances.owner(style)==identity and not Dances.allowed(base,style,30),identity+": exclusive move has authored geometry and cannot be borrowed: "+style)
			var trace: Array=[]
			var first := Rhythm.choreography(style,0,identity)
			var leg_motion := false
			for tick in 33:
				var pose := Rhythm.choreography(style,float(tick)/4.0,identity)
				trace.append([pose.hip,pose.feet.duplicate(),pose.hands.duplicate(),pose.head_tilt])
				leg_motion=leg_motion or pose.feet!=first.feet or pose.foot_angles!=first.foot_angles
				check(not pose.has("front_weight") and (is_equal_approx(pose.feet[0].y,-3) or is_equal_approx(pose.feet[1].y,-3)),style+": side-only beat pose retains an actual support boot")
			check(leg_motion,style+": feet or ankles actually move with the beat")
			pose_signatures[style]=trace
		var old_profiles := {"mara":{"style":"character_default","intensity":.5},"ivo":{"style":"moonwalk","intensity":.75}}
		var normalized := Dances.normalized_profiles(old_profiles)
		check(normalized.size()==8 and normalized.mara==old_profiles.mara and normalized.ivo==old_profiles.ivo and normalized.has(identity),identity+": old audio preferences retain exact saved values while new default profiles appear")
	for first_style: String in pose_signatures:
		for second_style: String in pose_signatures:
			if first_style<second_style: check(pose_signatures[first_style]!=pose_signatures[second_style],"New move joint paths are distinct: "+first_style+" / "+second_style)
	var director := Director.new()
	world.add_child(director)
	var npc := Npc.new()
	npc.game=world
	npc.director=director
	npc.character_id="oskar"
	npc.site_id="quarry"
	npc.position=Vector2(200,430)
	world.add_child(npc)
	await physics_frame
	check(not npc.is_class("PhysicsBody2D") and not npc.is_in_group("players") and not npc.is_in_group("medical_targets") and not npc.has_method("take_damage"),"Physical NPC is never a player, collider, damage actor or medical target")
	check(npc.is_in_group("interactables") and npc.is_in_group("solo_story_npcs") and npc.interaction_point()==Vector2(200,412),"NPC offers the established world interaction point on real terrain")
	check(npc.can_interact(oskar) and npc.work_uses_real_time() and npc.action_hint(oskar)=="Encounter oskar","Own nearby live worker gets the director's actual encounter hint")
	var old_inventory := oskar.inventory.duplicate()
	var old_roster := Roster.unlocked.duplicate()
	check(npc.interact(oskar,.01) and director.selected=="oskar" and npc.facing==-1 and director.opened==1,"Normal E interaction opens the real encounter API and faces its worker")
	check(not npc.interact(oskar,.01) and director.opened==1,"A held E cannot reopen an already active director encounter")
	check(oskar.inventory==old_inventory and Roster.unlocked==old_roster,"Physical interaction alone never pays costs or directly unlocks the roster")
	director.active=false
	director.enabled=false
	check(not npc.can_interact(oskar) and not npc.interact(oskar,.01),"Disabled solo director cannot expose or open encounters")
	director.enabled=true
	world.authoritative=false
	check(not npc.can_interact(oskar),"Replica authority cannot invoke NPC choices")
	world.authoritative=true
	check(not npc.can_interact(rika),"Faraway worker cannot remotely open an encounter")
	npc.hide()
	check(not npc.can_interact(oskar),"Hidden encounter cannot remain an invisible interaction target")
	npc.show()
	oskar.hp=0
	oskar.medical.incapacitate()
	check(not npc.can_interact(oskar),"Downed worker cannot open encounter choices")
	oskar.hp=110
	oskar.medical.state="healthy"
	oskar.down_time=0
	var foreign_view := SubViewport.new()
	foreign_view.world_2d=World2D.new()
	root.add_child(foreign_view)
	var foreign_world := World.new()
	foreign_view.add_child(foreign_world)
	var foreign_actor := worker(foreign_world,"mara",170)
	check(not npc.can_interact(foreign_actor),"Nearby equal-coordinate worker in another World2D cannot interact")
	foreign_actor.queue_free()
	check(not npc.can_interact(foreign_actor),"Queued worker cannot initiate a dialogue")
	var starting_pose := npc.pose.duplicate(true)
	for tick in 90: npc._process(.1)
	check(npc.elapsed>0 and not npc.pose.is_empty() and npc.pose!=starting_pose,"NPC visibly breathes and articulates its own idle poses")
	var foreign_clean := await Clean.free_scene(foreign_view,self)
	var world_clean := await Clean.free_scene(world,self)
	check(foreign_clean and world_clean,"Real workers/NPC fixtures cleanly release scene and audio handles")
	# Exercise the actual HUD context path, including its universal prompt call.
	var actual_game = load("res://scenes/main.tscn").instantiate()
	root.add_child(actual_game)
	current_scene=actual_game
	actual_game.start_scenario(1,{"environment":"basalt_quarry","build_type":"bastion","position":"left"})
	actual_game.rounds.running=false
	actual_game.rounds.set_process(false)
	var actual_director:=Director.new()
	actual_game.add_child(actual_director)
	var actual_npc:=Npc.new()
	actual_npc.game=actual_game
	actual_npc.director=actual_director
	actual_npc.character_id="oskar"
	actual_npc.site_id="quarry"
	actual_npc.position=actual_game.players[0].position+Vector2(24,0)
	actual_game.add_child(actual_npc)
	var actual_worker: Worker=actual_game.players[0]
	actual_worker.set_physics_process(false)
	actual_worker.focus=actual_npc
	for language: String in ["de","en"]:
		LocaleText.set_locale(language,false)
		var context: Dictionary=actual_game.hud.context_details(actual_worker)
		check(context.title=="OSKAR" and context.body==LocaleText.text(CharacterCatalog.data("oskar").detail),language+": actual HUD calls NPC prompt and displays authored profession")
		check(context.key=="E" and context.action==LocaleText.format("%s antippen · sprechen","E"),language+": actual HUD describes tap-to-talk rather than held work")
	actual_game.join_coop()
	var second_worker: Worker=actual_game.players[1]
	second_worker.set_physics_process(false)
	second_worker.focus=actual_npc
	var second_context: Dictionary=actual_game.hud.context_details(second_worker)
	check(second_context.key=="Enter / X" and second_context.action==LocaleText.format("%s antippen · sprechen","Enter / X"),"Actual second worker retains its own keyboard/gamepad talk controls")
	check(await Clean.free_scene(actual_game,self),"Actual HUD/worker integration releases bound audio handles")
	Roster.persistence_enabled=false
	Roster.save_path=Roster.SAVE_PATH
	Roster._loaded=true
	Roster.unlocked.clear()
	var report_path := "res://artifacts/solo-story/recruits/verification.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	var file:=FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failures==0,"checks":checks,"passed":checks-failures,"failures":failures,"results":results},"\t"))
	file.close()
	print("SOLO STORY RECRUITS: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
