extends "res://tests/medical_test.gd"
const Roster = preload("res://scripts/crew_roster.gd")
const Identity = preload("res://scripts/worker_identity_art.gd")
func recruit_at(identity: String, x: float) -> Worker:
	var person: Worker = load("res://scenes/player.tscn").instantiate()
	person.character_id = identity
	person.game = game
	person.position = Vector2(x,430)
	game.add_child(person)
	person.set_physics_process(false)
	person.get_node("WorkerWeapon").set_physics_process(false)
	person.progression.set_physics_process(false)
	return person
func run() -> void:
	InputSetup.install()
	Roster.save_path = "user://crew-roster-test-%d.cfg" % OS.get_process_id()
	Roster.persistence_enabled = true
	Roster.unlocked.clear()
	Roster._loaded = false
	check(CharacterCatalog.CHARACTERS.size() == 8, "Eight crew identities exist")
	for identity in ["mara", "branko", "ivo", "nora"]: check(CharacterCatalog.is_unlocked(identity), "Four distinct starters remain available")
	for identity in ["levin", "selma", "oskar", "rika"]: check(not CharacterCatalog.is_unlocked(identity), "Rescued recruit starts locked")
	check(CharacterCatalog.unlock_for_site("unknown").is_empty(), "Unknown encounter cannot unlock a recruit")
	check(CharacterCatalog.unlock_for_site("quarry").is_empty() and CharacterCatalog.unlock_for_site("power_station").is_empty(), "Two new recruits require explicit physical encounter recruitment")
	check(CharacterCatalog.unlock_for_site("refinery_archive").is_empty(), "Secured refinery does not duplicate starter Nora's entitlement")
	check(CharacterCatalog.unlock_for_site("radar_archive") == ["levin"], "Secured radar site rescues only scout Levin")
	check(CharacterCatalog.unlock_for_site("dam_vault") == ["selma"], "Secured dam rescues only medic Selma")
	check(CharacterCatalog.unlock_for_site("dam_vault").is_empty(), "Rescue reward cannot repeat")
	Roster.unlocked.clear()
	Roster._loaded = false
	check(CharacterCatalog.is_unlocked("nora") and CharacterCatalog.is_unlocked("levin") and CharacterCatalog.is_unlocked("selma"), "Atomic isolated roster reload preserves all rescues")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Roster.save_path))
	Roster.persistence_enabled = false
	game = MedicalGame.new()
	root.add_child(game)
	var nora := recruit_at("nora",200)
	var levin := recruit_at("levin",340)
	var selma := recruit_at("selma",500)
	var patient := recruit_at("mara",530)
	check(nora.max_hp == 95 and nora.capacity() == 5 and is_equal_approx(nora.work_multiplier(),1.30), "Nora has real engineering speed with lower health and cargo tradeoffs")
	check(levin.max_hp == 85 and levin.capacity() == 5 and is_equal_approx(levin.movement_multiplier(),1.18), "Levin has actual scouting movement and lighter equipment")
	var gun: WorkerWeapon = levin.get_node("WorkerWeapon")
	gun.loaded.rifle = 0
	gun.reserve = 20
	game.started = true
	check(gun.start_reload() and is_equal_approx(gun.reload_timer,1.05*.85), "Levin starts a genuinely15percent shorter reload")
	gun._physics_process(1.05*.85+.01)
	check(gun.current_ammo() == 20 and gun.reserve == 0, "Faster reload preserves finite rounds and magazine capacity")
	game.started = false
	fresh(patient,40)
	await physics_frame
	var charges := selma.medical.charges
	check(not patient.medical.begin_or_continue_aid(selma,MedicalCatalog.TREAT_TIME/1.25-.01), "Selma still has a real uninterrupted treatment channel")
	check(patient.medical.begin_or_continue_aid(selma,.011) and selma.medical.charges == charges-1, "Selma completes treatment25percent faster using exactly one charge")
	fresh(patient,10)
	patient._begin_knockout()
	check(patient.is_downed(), "Real injured worker is downed before revival")
	check(patient.medical.begin_or_continue_aid(selma,MedicalCatalog.REVIVE_TIME/1.25+.01) and not patient.is_downed() and selma.medical.charges == charges-2, "Medic trait also speeds actual revive without bypassing charge costs")
	for identity in ["nora","levin","selma"]:
		for texture in [Identity.body(identity),Identity.arms(identity),Identity.torso(identity),Identity.head(identity)]:
			check(texture != null and texture.get_image().get_used_rect().has_area(), "New identity uses a real nonempty authored rig texture")
		check(Identity.body(identity) != Identity.body("mara"), "Recruit owns a separate body atlas rather than falling back to Mara")
		var frames: Dictionary = preload("res://scripts/worker_personality.gd").frames(identity)
		check(frames.size() == 19 and frames.weapon.size() == 4, "Recruit has all19 runtime animation states including weapon grips")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self), "Crew effect fixture releases real workers")
	print("CREW RECRUITS: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
