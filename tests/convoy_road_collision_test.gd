extends SceneTree
## Real physics queries through the dedicated road at all source positions.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	print("ROAD COLLISION %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if not "--no-profile-save" in OS.get_cmdline_user_args() or not "--no-upnp" in OS.get_cmdline_user_args(): quit(2); return
	for position: String in ["left","center","right"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		game.start_scenario(1,{"environment":"ash_foundry","position":position,"build_type":"bastion"})
		game.rounds.running=false
		game.rounds.set_process(false)
		game.rounds.wave=20
		game.expedition.on_victory()
		game.campaign.select_destination("harbor")
		game.campaign.begin_journey()
		game.expedition._start_road()
		game.expedition.set_physics_process(false)
		game.expedition.vehicle.set_physics_process(false)
		game.medic.set_physics_process(false)
		game.players[0].set_physics_process(false)
		var truck=game.expedition.vehicle
		# physics_frame signals before the server step. Flush moved/configured
		# bodies before querying an existing van relocated from the source garage.
		for frame in 3: await physics_frame
		var query := PhysicsRayQueryParameters2D.create(Vector2(760,400),Vector2(1450,400),2,[truck.get_rid(),game.players[0].get_rid()])
		var hit: Dictionary=game.get_world_2d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): print("OLD HIDDEN HIT: ",position," ",hit.collider," ",hit.position)
		check(hit.is_empty(),position+": personal and hostile shots see no invisible bunker walls")
		query=PhysicsRayQueryParameters2D.create(Vector2(1600,400),Vector2(1600,470),1)
		hit=game.get_world_2d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and absf(hit.position.y-430)<.01,position+": actual road floor remains solid at y430")
		query=PhysicsRayQueryParameters2D.create(truck.position+Vector2(240,-20),truck.position+Vector2(-240,-20),2)
		hit=game.get_world_2d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.collider==truck,position+": real hostile fire still collides with the vehicle")
		check(game.scenario_bunker.is_inside_tree() and game.core.hp>0,position+": old authoritative bunker nodes remain alive")
		check(game.ladders.is_empty(),position+": journey exposes no invisible bunker climbing route")
		await Cleanup.free_scene(game,self)
	print("CONVOY ROAD COLLISION CHECKS: %d passed, %d failed" % [checks-failures,failures])
	quit(1 if failures else 0)
