extends SceneTree
## Prepare a won siege and the approach position. Actual departure reload,
## physical E input, hostile attacks, escort shots, SAN and reboarding run live.
const Journey := preload("res://scripts/convoy_journey.gd")
const Controller := preload("res://scripts/expedition_controller.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-defense-20261004/root"
var game: Node
var checks := 0
var failures := 0
var evidence: Dictionary = {}
var capture_enabled := false

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("SOLO CONVOY %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func wait_world(previous: int) -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not is_instance_valid(current_scene) or current_scene.get_instance_id()==previous: continue
		game=current_scene
		if game.started and game.expedition.stage=="travel" and game.expedition.vehicle.journey_state.phase=="driving": return true
	return false

func guards() -> Array:
	return get_nodes_in_group("enemies").filter(func(enemy): return enemy.get("game")==game and not enemy.is_queued_for_deletion() and not enemy.dead and bool(enemy.get_meta("expedition_guard",false)))

func total_guard_hp() -> float:
	var result:=0.0
	for enemy in guards(): result+=float(enemy.hp)
	return result

func escort_shots(truck: Node) -> int:
	var result:=0
	for escort in truck.defenders: result+=int(escort.shots_fired)
	return result

func escort_rounds(truck: Node) -> int:
	var result:=0
	for escort in truck.defenders: result+=int(escort.ammo)+int(escort.reserve)
	return result

func capture(name: String) -> void:
	if not capture_enabled: return
	paused=true
	game.notice_time=0
	game.hud.combat_overlay.banners.clear()
	game.player_camera.set_zoom(1.25)
	game.player_camera.update_view(0,true)
	game.camera.force_update_scroll()
	var truck=game.expedition.vehicle
	truck.queue_redraw()
	truck.visual.queue_redraw()
	truck.get_node("ConvoyPresentation").queue_redraw()
	for person in game.players:
		person.get_node("PixelVisual")._process(0)
		person.get_node("PixelVisual").queue_redraw()
	for escort in truck.defenders:
		escort.body_visual.queue_redraw()
		escort.weapon_visual.queue_redraw()
	for frame in 3: await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(OUTPUT+"/"+name+".png")==OK,"Save actual solo road defense "+name)
	paused=false

func finish() -> void:
	Input.action_release("p1_interact")
	paused=false
	if is_instance_valid(game): check(await Cleanup.free_scene(game,self),"Real campaign, escort children and audio release cleanly")
	var report:=FileAccess.open(OUTPUT+("/solo-rendered.json" if capture_enabled else "/solo-integration.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"evidence":evidence,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Prepared real won ash_foundry siege and approach at the authored flat threshold; actual garage command, boarding, scene reload/ignition, live NPC/enemy combat, physical E work, timed rear/front reinforcements, SAN tools and reboarding. No HP/damage/ammo/repair-speed edits; default physics/time scale."},"\t"))
	report.close()
	print("SOLO CONVOY DEFENSE INTEGRATION: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not "--no-profile-save" in args or not "--no-upnp" in args: quit(2); return
	capture_enabled="--capture" in args
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if capture_enabled: root.size=Vector2i(1920,1080)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	check(game.expedition.on_victory(),"Actual completed solo siege opens the garage")
	check(game.expedition.handle_command("prepare",{},1),"Open actual travel preparation")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Select actual harbor route")
	var old_id:=game.get_instance_id()
	var garage=game.expedition.vehicle
	game.players[0].global_position=garage.global_position+Vector2(-110,0)
	check(game.expedition.handle_command("depart",{},1),"Departure begins actual boarding")
	check(garage.board(game.players[0]),"Real solo human occupies the driver seat")
	check(await wait_world(old_id),"Boarding countdown reloads the road and starts the engine")
	if failures: await finish(); return
	var truck=game.expedition.vehicle
	var person=game.players[0]
	check(game.players.size()==1 and game.player_count==1,"Solo world still has exactly one actual player")
	check(truck.defenders.size()==2 and truck.active_defenders()==0,"Two finite escorts ride stowed during driving")
	var stocks: Dictionary=game.campaign.expedition.garage_stock.duplicate(true)
	var inventory: Dictionary=person.inventory.duplicate(true)
	var xp: float=person.progression.xp
	truck.position.x=Controller.ROAD_START+(Controller.ROAD_END-Controller.ROAD_START)*Journey.BREAKDOWN_PROGRESS+.1
	var deadline:=Time.get_ticks_msec()+4000
	while truck.journey_state.phase!="repair" and Time.get_ticks_msec()<deadline: await physics_frame
	check(truck.journey_state.phase=="repair" and truck.active_defenders()==2,"Native breakdown deploys both actual offline guards")
	check(not is_instance_valid(person.mounted_turret) and truck.can_service(person),"Driver exits beside the real repair wheel")
	check(guards().size()>0,"Native flat spawns actual live attacking opponents")
	if failures: await finish(); return
	var hp_before:=total_guard_hp()
	var rounds_before:=escort_rounds(truck)
	var shots_before:=escort_shots(truck)
	# The priority check uses a real nearby loot pile, then removes only that
	# deliberately prepared pile so the stock fixture remains unchanged.
	var pile: Node2D=load("res://scenes/resource_pickup.tscn").instantiate()
	pile.game=game
	pile.kind="scrap"
	pile.amount=1
	game.add_child(pile)
	pile.global_position=person.global_position
	await physics_frame
	check(game.get_focus(person)==truck,"Nearby loot cannot steal the wheel tool interaction")
	pile.queue_free()
	Input.action_press("p1_interact")
	deadline=Time.get_ticks_msec()+3500
	while (float(truck.journey_state.repair_work)<.2 or escort_shots(truck)<=shots_before) and Time.get_ticks_msec()<deadline: await physics_frame
	check(person._interacting and person.focus==truck and truck.journey_state.repair_operator==1,"Actual held E makes the solo human the sole repairer")
	check(escort_shots(truck)>shots_before and total_guard_hp()<hp_before,"Actual NPC bullets damage live opponents during human tool work")
	check(rounds_before-escort_rounds(truck)==escort_shots(truck)-shots_before,"Every escort shot spends exactly one round from its own finite loadout")
	evidence["human_repair_npc_cover"]={"operator":truck.journey_state.repair_operator,"work":truck.journey_state.repair_work,"shots_before":shots_before,"shots_after":escort_shots(truck),"enemy_hp_before":hp_before,"enemy_hp_after":total_guard_hp(),"rounds_before":rounds_before,"rounds_after":escort_rounds(truck)}
	await capture("solo-human-repair")
	Input.action_release("p1_interact")
	var work_before: float=truck.journey_state.repair_work
	deadline=Time.get_ticks_msec()+6500
	while (not game.medic.visible or truck.journey_state.repair_operator!=0 or float(truck.journey_state.repair_work)<=work_before) and Time.get_ticks_msec()<deadline: await physics_frame
	check(game.medic.visible and truck.journey_state.repair_operator==0 and float(truck.journey_state.repair_work)>work_before,"Real SAN takes the tools after release while the human can defend")
	check(game.campaign.expedition.garage_stock==stocks and person.inventory==inventory and person.progression.xp==xp,"Escort and tool assistance consume no player supplies or award fake XP")
	deadline=Time.get_ticks_msec()+15000
	while game.expedition._repair_guard_batches<1 and truck.journey_state.phase=="repair" and Time.get_ticks_msec()<deadline: await physics_frame
	check(game.expedition._repair_guard_batches>=1 and guards().any(func(enemy):return enemy.position.x<truck.position.x),"Timed genuine reinforcement attacks the rear during repair")
	await capture("solo-san-repair-rear-defense")
	deadline=Time.get_ticks_msec()+12000
	while game.expedition._repair_guard_batches<2 and truck.journey_state.phase=="repair" and Time.get_ticks_msec()<deadline: await physics_frame
	check(game.expedition._repair_guard_batches==2 and guards().size()<=Balance.CONVOY_DEFENSE_MAX_ENEMIES,"Second finite reinforcement is bounded by the defense cap")
	evidence["reinforcements"]={"batches":game.expedition._repair_guard_batches,"living_guards":guards().size(),"shots":escort_shots(truck),"escort_hp":truck.defenders.map(func(escort):return escort.hp)}
	# Choosing the already reachable wheel is the same explicit target choice
	# available with Tab; normal input and native reach guards still own work.
	person.preferred_focus=truck
	Input.action_press("p1_interact")
	deadline=Time.get_ticks_msec()+20000
	while truck.journey_state.phase=="repair" and Time.get_ticks_msec()<deadline: await physics_frame
	Input.action_release("p1_interact")
	check(truck.journey_state.phase=="reboarding" and truck.journey_state.breakdown_done,"Actual tool work finishes all wheel stages and three bolts")
	await physics_frame
	check(truck.active_defenders()==0 and truck.defenders.all(func(escort):return not escort.visible),"Both escorts stow after the completed wheel without respawning")
	var fuel: float=truck.fuel
	person.global_position=truck.global_position+Vector2(116,0)
	check(truck.board(person),"Actual repaired vehicle accepts its returning driver")
	deadline=Time.get_ticks_msec()+3000
	while truck.journey_state.phase!="driving" and Time.get_ticks_msec()<deadline: await physics_frame
	check(truck.journey_state.phase=="driving" and truck.driving_enabled and is_equal_approx(truck.fuel,fuel),"Real crew-ready countdown enables forward travel without stationary fuel loss")
	check(not truck.begin_breakdown(),"The completed repair never repeats in the same journey")
	evidence["finish"]={"phase":truck.journey_state.phase,"escort_rounds":escort_rounds(truck),"shots":escort_shots(truck),"human_slots":game.players.size(),"fuel":truck.fuel}
	await finish()
