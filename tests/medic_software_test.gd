class_name BetaMedicSoftwareCheck
extends SceneTree
## Paid research, real normal-game idle gates and durable robot software. Scene
## state and spare research points are prepared; transactions use production APIs.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const NetWorld := preload("res://scripts/network_world.gd")
const Schema := preload("res://scripts/network_replication_schema.gd")
var checks := 0
var failures := 0
var game

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.combat_events.persistence_enabled = false
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.rounds.set_process(false)
	game.rounds.wave = 1
	game.medic.set_physics_process(false)
	game.medic.set_process(false)
	await physics_frame
	await physics_frame
	var medic: FieldMedic = game.medic
	medic.position = medic._home()
	medic.velocity = Vector2.ZERO
	medic._idle_time = 3.0
	check(medic.dance_level() == 0 and not medic.dance_allowed(),"Unresearched SAN-1 does not dance even in safe standby")
	game.upgrades.points = 100
	check(not game.upgrades.purchase("bunker_dance_5"),"Later software cannot bypass its research chain")
	var spent := 0
	for index in CampaignCatalog.MEDIC_UPGRADES.size():
		var id: String = CampaignCatalog.MEDIC_UPGRADES[index]
		spent += int(game.upgrades.node_data(id).cost)
		check(game.upgrades.purchase(id),"Real research purchase unlocks " + id)
		check(medic.dance_level() == index + 1,"SAN-1 software level matches paid progression")
		check(game.upgrades.points == 100-spent,"Software debits the exact shared research cost")
		check(not game.upgrades.purchase(id),"A software level cannot be purchased twice")
	check(medic.dance_allowed(),"Fully stocked researched SAN-1 may dance at its standby station")
	check(not medic.logistics.enabled() and not medic.logistics.collection_enabled(),"Dance research does not secretly unlock transport or recovery")
	check(game.upgrades.persistent_owned() == CampaignCatalog.MEDIC_UPGRADES,"All five robot software levels travel with the crew")
	var campaign := CampaignState.new("user://unused-san-software.json",false)
	check(campaign.begin_new(game.scenario_options,["mara"],1),"Prepared campaign starts normally without saving the player profile")
	campaign.mission_start()
	check(not campaign.complete_mission(campaign.mission_id,20,game.players,game.upgrades).is_empty(),"Normal mission completion captures portable SAN-1 research")
	check(campaign.shared_personal_upgrades == CampaignCatalog.MEDIC_UPGRADES and CampaignState.valid_checkpoint(campaign.checkpoint()),"Software levels are retained in a valid durable checkpoint")
	var damaged: Dictionary = campaign.checkpoint()
	damaged.shared_personal_upgrades = ["bunker_dance_5"]
	check(not CampaignState.valid_checkpoint(damaged),"Corrupt save cannot grant final software without the earlier levels")
	var fresh := UpgradeSystem.new()
	game.add_child(fresh)
	var previous = game.upgrades
	game.upgrades = fresh
	fresh.game = game
	CampaignBonus.restore_players(game,campaign)
	check(fresh.medic_dance_level() == 5 and not fresh.has_upgrade("medic_collection"),"New bunker restores robot software independently of infrastructure")
	game.upgrades = previous
	fresh.queue_free()
	medic.logistics_cargo = "steel"
	check(not medic.dance_allowed(),"Physical cargo suppresses dance")
	medic.logistics_cargo = ""
	for phase: String in ["collect","deliver","return","holding","medical"]:
		medic.logistics_phase = phase
		check(not medic.dance_allowed(),"Active task suppresses dance: " + phase)
	medic.logistics_phase = "idle"
	medic.target = game.players[0]
	check(not medic.dance_allowed(),"Medical target suppresses dance before treatment starts")
	medic.target = null
	medic.treating = true
	check(not medic.dance_allowed(),"Treatment suppresses dance")
	medic.treating = false
	medic.climbing = true
	check(not medic.dance_allowed(),"Ladder movement suppresses dance")
	medic.climbing = false
	medic.medical_supplies = 1
	check(not medic.dance_allowed(),"A pending medical refill suppresses dance")
	medic.medical_supplies = MedicalCatalog.MAX_CHARGES
	medic._rest_delay = 1
	check(not medic.dance_allowed(),"Recent core damage suppresses dance")
	medic._rest_delay = 0
	medic.position.x += 60
	check(not medic.dance_allowed(),"A robot stranded away from home cannot enter standby dance")
	medic.position = medic._home()
	medic.status_label = LocaleText.text("SAN-1 · Rückweg blockiert")
	check(not medic.dance_allowed(),"A blocked route suppresses dance despite zero velocity")
	medic._process(0.016)
	check(medic.expression.kind == "search","Real blocked status produces a brief search reaction")
	medic.status_label = LocaleText.text("SAN-1 · Bereitschaft")
	medic._process(0.016)
	medic.target = game.players[0]
	medic._process(0.016)
	check(medic.expression.kind == "alert","New patient produces a brief alert reaction")
	medic.target = null
	var mirror: FieldMedic = load("res://scenes/field_medic.tscn").instantiate()
	mirror.game = game
	game.add_child(mirror)
	mirror.set_physics_process(false)
	mirror.set_process(false)
	var net := NetWorld.new()
	net.game = game
	medic.logistics_phase = "deliver"
	medic.logistics_cargo = "glass"
	var state: Dictionary = net._capture_fields(medic,Schema.fields("field_medic"))
	check(Schema.valid_state("field_medic",state),"Cargo and dance eligibility fields retain the existing network schema")
	net._apply_fields(mirror,state)
	check(mirror.logistics_cargo == "glass" and not mirror.dance_allowed() and mirror.dance_level() == 5,"Replica receives task inhibition and shared software without executing a cargo transaction")
	net = null
	await Cleanup.free_scene(game,self)
	print("SAN SOFTWARE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
