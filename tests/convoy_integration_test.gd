extends SceneTree
## Actual workers, SAN, UI and audited world replication in one loaded road.
const Journey := preload("res://scripts/convoy_journey.gd")
const Mechanic := preload("res://scripts/convoy_mechanic_pose.gd")
const World := preload("res://scripts/network_world.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const L := preload("res://scripts/locale_text.gd")
var game
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	else: print("CONVOY INTEGRATION PASS ",label)

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2);return
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"center","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Actual victory opens a finite campaign garage")
	check(game.campaign.select_destination("harbor") and not game.campaign.begin_journey().is_empty(),"Real checkpoint accepts the road")
	game.expedition._start_road()
	game.expedition.set_physics_process(false)
	game.set_process(false)
	var truck=game.expedition.vehicle
	truck.set_physics_process(false)
	var worker=game.players[0]
	worker.set_physics_process(false)
	worker.get_node("WorkerWeapon").set_physics_process(false)
	game.medic.set_physics_process(false)
	paused=false
	for unused in 3: await physics_frame
	check(not game.valid_focus(worker,game.core),"Hidden bunker core cannot steal a road interaction")
	check(not game.weather.roof_flag_visible(),"Old bunker roof flag is absent from travel")
	var rain: Dictionary=game.weather.collision.surface_at(game.scenario_bunker.room_right-23)
	check(not rain.is_empty() and absf(float(rain.position.y)-430)<1 and rain.material=="concrete","Rain contacts the real road beyond the truck, with the road material")
	var boarded_position: Vector2=worker.position
	worker.position=game.core.position
	worker.hp=worker.max_hp-8
	worker.medical.charges=0
	worker.since_hit=99
	for unused in 80: worker._update_health(.1)
	check(not worker._near_core() and worker.hp==worker.max_hp-8 and worker.medical.charges==0,"Hidden departure core cannot refill personal aid or regenerate road health")
	worker.hp=worker.max_hp
	worker.medical.state="healthy"
	worker.position=boarded_position
	check(truck.journey_state.phase=="starting","Loaded travel world starts with a braked ignition phase")
	Journey.change_phase(truck.journey_state,"driving")
	check(truck.begin_breakdown() and truck.can_service(worker),"Real breakdown places a dismounted player beside the rear wheel")
	check(game.valid_focus(worker,truck),"Visible repair vehicle remains a valid reachable interaction")
	worker.focus=truck
	worker._interacting=true
	check(game.hud.context_details(worker).title==truck.display_name(),"Wheel context names the transporter instead of a bunker wall")
	truck.journey_state.repair_operator=worker.player_id
	var visual=worker.get_node("PixelVisual")
	var cargo: Dictionary=worker.inventory.duplicate(true)
	var work: float=truck.journey_state.repair_work
	for character: Dictionary in CharacterCatalog.CHARACTERS:
		worker.character_id=character.id
		for step: String in ["jack","remove","fit","tighten","lower"]:
			truck.journey_state.repair_step=step
			visual._process(.05)
			var pose: Dictionary=visual.pose_skeleton
			check(visual.special_pose=="convoy_service" and not pose.is_empty(),character.id+" uses the working rig for "+step)
			if pose.is_empty(): continue
			check(pose.hip.is_finite() and pose.shoulder.is_finite() and pose.feet.all(func(point):return point.is_finite()) and pose.hands.all(func(point):return point.is_finite()),"Finite articulated feet and hands: "+character.id+"/"+step)
	check(worker.inventory==cargo and truck.journey_state.repair_work==work,"Cosmetic worker poses never advance tools or alter materials")
	worker.character_id="mara"
	truck.journey_state.repair_step="jack"
	truck.journey_state.phase_time=.1
	var first: Dictionary=Mechanic.sample(worker)
	truck.journey_state.phase_time=.3
	check(first.hands!=Mechanic.sample(worker).hands,"Jack stroke changes continuously with the authoritative clock")
	worker._interacting=false
	check(Mechanic.sample(worker).is_empty(),"Releasing interaction immediately clears the mechanic pose")
	worker._interacting=true
	truck.journey_state.solo_assist=true
	game.medic.medical_supplies=1
	game.medic.global_position=truck.global_position+Vector2(-40,-24)
	var xp: float=worker.progression.xp
	var stocks: Dictionary=game.campaign.expedition.garage_stock.duplicate(true)
	for unused in 24:
		await physics_frame
		game.medic._physics_process(1.0/60)
	check(game.medic.visible and (game.medic.global_position-Vector2(0,20)).distance_to(truck.service_point())<64,"Actual SAN travels into physical tool range")
	check(game.medic._road_tool_active(),"SAN animates a wrench only at the actual repair site")
	check(game.medic.medical_supplies==1 and game.campaign.expedition.garage_stock==stocks and worker.progression.xp==xp,"Road assistance creates no medical charges, resources or XP")
	truck.journey_state.solo_assist=false
	game.medic._physics_process(1.0/60)
	check(not game.medic.visible and game.medic.velocity==Vector2.ZERO and game.medic.refill_progress==0,"Unneeded SAN stows aboard without hidden-bunker refills")
	# Ordinary injury remains treatable on the road with the real finite channel.
	worker._interacting=false
	worker.hp=worker.max_hp-8
	worker.medical.state="wounded"
	worker.medical.bleeding=0
	worker.velocity=Vector2.ZERO
	worker.hurt_stun=0
	worker.invulnerability=0
	game.medic.position=truck.global_position+Vector2(-40,-24)
	var before_treatments: int=game.medic.treatments_completed
	var deadline:=Time.get_ticks_msec()+9000
	while game.medic.treatments_completed==before_treatments and Time.get_ticks_msec()<deadline:
		await physics_frame
		game.medic._physics_process(1.0/60)
	check(game.medic.treatments_completed==before_treatments+1 and worker.hp==worker.max_hp,"Solo road injury completes the actual medical treatment")
	check(game.medic.medical_supplies==0,"Road treatment spends one real charge without restocking")
	game.medic._physics_process(1.0/60)
	check(not game.medic.visible,"Finished SAN returns to the transport")
	worker.focus=truck
	truck.journey_state.repair_operator=1
	truck.journey_state.phase_time=.5
	truck.journey_state.repair_work=.4
	var authority:=World.new()
	authority.bind(game)
	var audit: Dictionary=authority.capture()
	var replica:=World.new()
	replica.bind(game)
	check(replica.apply(audit),"A real repair snapshot validates and applies: "+replica.last_error)
	for mutation: Dictionary in [{"phase":"execute"},{"repair_work":NAN},{"repair_operator":5},{"events":[{"serial":1,"kind":"load_resource","quality":"normal"}],"event_serial":1},{"unexpected":true}]:
		var bad:=audit.duplicate(true)
		for record: Dictionary in bad.entities:
			if record.type=="convoy_vehicle": record.state.journey_state.merge(mutation,true)
		var before_hp: float=worker.hp
		var before_x: float=truck.position.x
		check(not replica.apply(bad) and worker.hp==before_hp and truck.position.x==before_x,"Malformed journey rejected atomically: "+str(mutation.keys()[0]))
	check(replica.apply(audit) and truck.journey_state.repair_work==.4,"Valid reconnect retains the actual partial repair after rejected snapshots")
	var bad_revision:=audit.duplicate(true)
	bad_revision.version=2
	check(not replica.apply(bad_revision),"Previous world revision cannot apply the new journey entities")
	game.hud.overlay="expedition"
	game.hud._rebuild_buttons()
	for locale: String in ["de","en"]:
		L.set_locale(locale,false)
		for phase: String in ["boarding","starting","repair","reboarding"]:
			truck.journey_state.phase=phase
			check(not game.hud._convoy_controls().is_empty(),"Contextual convoy controls in "+locale+"/"+phase)
			worker.focus=truck
			if phase=="boarding":
				check(game.hud.context_details(worker).action==L.format("%s antippen · einsteigen","E"),"Boarding describes a tap instead of tool work in "+locale)
		truck.journey_state.phase="repair"
		truck.journey_state.repair_step="tighten"
		truck.journey_state.repair_bolts=2
		game.hud._layout_viewport()
		var header: Rect2=game.hud.status_bounds()
		check(game.hud.screen_rect().encloses(header),"Repair status stays within the authored UI canvas in "+locale)
		var panel=game.hud.expedition_panel
		panel._refresh()
		check(panel.garage_button.visible and not panel.garage_button.disabled,"Road UI exposes an authoritative garage escape in "+locale)
		check(not panel.garage_button.get_rect().intersects(panel.depart_button.get_rect()),"Garage and travel commands have separate click targets")
	L.set_locale("de",false)
	check(await Cleanup.free_scene(game,self),"Workers, robot, convoy audio and road release cleanly")
	print("CONVOY INTEGRATION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
