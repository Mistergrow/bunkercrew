extends SceneTree
## Prepared wave20 victory; actual four-worker garage commands, boarding,
## physical drive/fire/reverse/work InputMap processing and native thresholds.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/convoy-experience-20261004/root"
var game: Node
var checks := 0
var failures := 0
var capture_enabled := false
var recording := false
var capture_clock := 0.0
var states: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var evidence: Dictionary = {}
var _record_started := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	print("CONVOY EXPERIENCE %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures+=1
		push_error(label)

func release_inputs() -> void:
	for id in range(1,5):
		for action in ["right","left","fire","reload","aim_up","aim_down","interact"]:
			Input.action_release("p%d_%s" % [id,action])

func _process(delta: float) -> bool:
	if not recording or not capture_enabled: return false
	capture_clock+=delta
	if capture_clock<1.0/12.0: return false
	capture_clock=fmod(capture_clock,1.0/12.0)
	if not is_instance_valid(game) or not is_instance_valid(game.expedition.vehicle): return false
	var truck=game.expedition.vehicle
	var name:="drive-%04d.png" % frames.size()
	var picture:=root.get_texture().get_image()
	var saved:=picture.save_png(OUTPUT+"/frames/"+name)==OK
	frames.append({"file":name,"seconds":float(Time.get_ticks_msec()-_record_started)/1000.0,"saved":saved,"x":truck.position.x,"speed":truck.velocity.x,"phase":truck.journey_state.phase,"phase_time":truck.journey_state.phase_time})
	return false

func trace(label: String) -> void:
	var truck=game.expedition.vehicle
	var presentation=truck.get_node("ConvoyPresentation")
	states.append({"label":label,"position":[truck.position.x,truck.position.y],"velocity":[truck.velocity.x,truck.velocity.y],"facing":truck.facing,"fuel":truck.fuel,"wheel_phase":truck.wheel_phase,"suspension":truck.suspension,"phase":truck.journey_state.phase,"phase_time":truck.journey_state.phase_time,"mg_ammo":truck.ammo,"camera_position":[game.camera.position.x,game.camera.position.y],"zoom":game.camera.zoom.x,"body_pitch":presentation.body_pitch,"body_heave":presentation.body_heave,"burst_remaining":presentation.burst_remaining})

func wait_physics(seconds: float) -> void:
	var target:=Engine.get_physics_frames()+ceili(seconds*Engine.physics_ticks_per_second)
	while Engine.get_physics_frames()<target: await physics_frame

func finish() -> void:
	recording=false
	release_inputs()
	check(frames.all(func(frame):return frame.saved),"All requested live native frames save successfully")
	if is_instance_valid(game): check(await Cleanup.free_scene(game,self),"Real crew, road, projectiles and sounds clean up")
	var out:=FileAccess.open(OUTPUT+("/drive-rendered.json" if capture_enabled else "/drive-integration.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"passed":checks-failures,"failures":failures,"evidence":evidence,"states":states,"frames":frames,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Prepared four-player completed ash_foundry wave20 and two finite ammo crates/research points. Genuine garage commands, boarding, scene reload/ignition, human InputMap forward/coast/reverse/aim/fire/tool actions, native first ambush and flat threshold. No chassis-position, velocity, HP, damage, ammo or work-speed overrides after real road launch. Native window off-screen; captured root framebuffer at12Hz with actual timestamps. Silent video; full physics and sounds still execute. No external OS input or twenty-wave claim."},"\t"))
	out.close()
	print("CONVOY EXPERIENCE DRIVE: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if not "--no-profile-save" in args or not "--no-upnp" in args: quit(2); return
	capture_enabled="--capture" in args
	if capture_enabled and DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"/frames"))
	if capture_enabled: root.size=Vector2i(1280,720)
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(4,{"environment":"ash_foundry","position":"left","build_type":"bastion"})
	game.rounds.running=false
	game.rounds.wave=20
	game.upgrades.points=30
	game.players[0].inventory={"ammo":2}
	check(game.expedition.on_victory(),"Prepared siege victory commits the actual garage boundary")
	check(game.upgrades.purchase("convoy_mg"),"Real research unlocks the finite MG")
	check(game.expedition.handle_command("prepare",{},1),"Open real garage")
	check(game.expedition.handle_command("route",{"id":"harbor"},1),"Select the real harbor route")
	check(game.expedition.handle_command("load",{"kind":"ammo","amount":2},1),"Load exactly two actual ammo crates")
	var old_id:=game.get_instance_id()
	check(game.expedition.handle_command("depart",{},1),"Valid departure begins visible boarding")
	var garage=game.expedition.vehicle
	for person in game.players:
		person.global_position=garage.global_position+Vector2(-100+person.player_id*20,0)
		check(garage.board(person,garage.SEAT_ROLES[person.player_id-1]),"Actual P%d occupies its distinct crew seat" % person.player_id)
	var deadline:=Time.get_ticks_msec()+15000
	var launched:=false
	while Time.get_ticks_msec()<deadline:
		await process_frame
		if not is_instance_valid(current_scene) or current_scene.get_instance_id()==old_id: continue
		game=current_scene
		if game.started and game.expedition.stage=="travel" and game.expedition.vehicle.journey_state.phase=="driving":
			launched=true
			break
	check(launched,"Normal crew countdown, world reload and ignition launch the real road")
	if not launched: await finish(); return
	var truck=game.expedition.vehicle
	check(game.players.size()==4 and truck.defenders.is_empty(),"Four actual human seats have no extra solo actors")
	var initial_x: float=truck.position.x
	var initial_fuel: float=truck.fuel
	var initial_distance: float=truck.travel_distance
	var initial_wheel: float=truck.wheel_phase
	var personal: Array[Node]=[game.players[2].get_node("WorkerWeapon"),game.players[3].get_node("WorkerWeapon")]
	var rounds: Array[int]=[personal[0].current_ammo()+personal[0].reserve,personal[1].current_ammo()+personal[1].reserve]
	var mg_rounds: int=truck.ammo+truck.reserve+truck.open_pack+20*int(truck.cargo.get("ammo",0))
	if capture_enabled:
		game.notice_time=0
		game.hud.combat_overlay.banners.clear()
	_record_started=Time.get_ticks_msec()
	recording=true
	Input.action_press("p1_right")
	Input.action_press("p2_reload")
	await wait_physics(.32)
	Input.action_release("p2_reload")
	check(truck.velocity.x>35 and truck.velocity.x<truck.top_speed,"Actual held throttle accelerates progressively")
	trace("accelerating")
	await wait_physics(.65)
	check(is_equal_approx(truck.velocity.x,truck.top_speed),"Held driver input reaches researched top speed")
	await wait_physics(.5)
	check(truck.ammo>0 and truck.reload_timer==0,"Actual gunner reload opens finite cargo and loads the empty starting MG")
	# Mounted keyboard crew aim with their actual input bindings. The rear guard
	# keeps its natural rear-facing stance; the MG and side guard face ahead.
	Input.action_press("p2_aim_down")
	Input.action_press("p4_aim_down")
	await wait_physics(.13)
	Input.action_release("p2_aim_down")
	Input.action_release("p4_aim_down")
	for id in [2,3,4]: Input.action_press("p%d_fire" % id)
	await wait_physics(.75)
	for id in [2,3,4]: Input.action_release("p%d_fire" % id)
	check(truck.flash_tick>0 and truck.ammo+truck.reserve+truck.open_pack+20*int(truck.cargo.get("ammo",0))<mg_rounds,"Gunner held fire emits actual finite MG rounds while moving")
	check(personal[0].current_ammo()+personal[0].reserve<rounds[0] and personal[1].current_ammo()+personal[1].reserve<rounds[1],"Both actual passengers spend their own magazines while riding")
	check(game.players[2].facing<0 and game.players[3].facing>0,"Rear and side guards keep distinct firing directions")
	trace("crew-fired-while-moving")
	var coasting_x: float=truck.position.x
	Input.action_release("p1_right")
	await wait_physics(.6)
	check(absf(truck.velocity.x)<.01 and truck.position.x>coasting_x,"Releasing throttle brakes naturally to rest instead of freezing displacement")
	trace("braked")
	var stopped_fuel: float=truck.fuel
	await wait_physics(.2)
	check(is_equal_approx(truck.fuel,stopped_fuel),"Waiting car spends no distance-based fuel")
	var reverse_x: float=truck.position.x
	var reverse_wheel: float=truck.wheel_phase
	Input.action_press("p1_left")
	await wait_physics(.4)
	check(truck.position.x<reverse_x and truck.velocity.x<0 and truck.facing<0 and truck.wheel_phase<reverse_wheel,"Real reverse input drives and rolls the mirrored car backward")
	trace("reversing")
	Input.action_release("p1_left")
	await wait_physics(.5)
	Input.action_press("p1_right")
	deadline=Time.get_ticks_msec()+12000
	while truck.journey_state.phase=="driving" and Time.get_ticks_msec()<deadline:
		await physics_frame
		if truck.position.x>1500:
			for id in [2,3,4]: Input.action_press("p%d_fire" % id)
	Input.action_release("p1_right")
	for id in [2,3,4]: Input.action_release("p%d_fire" % id)
	check(game.expedition.ambushes>=1,"Forward driving genuinely reaches and spawns the first route ambush")
	check(truck.journey_state.phase=="repair" and is_zero_approx(truck.velocity.x),"Actual driving reaches the authored flat threshold and stops for service")
	trace("rupture-onset")
	check(truck.driver_seat.occupant==null and truck.can_service(game.players[0]),"Actual flat ejects only the driver beside the reachable damaged wheel")
	check(game.players[1].mounted_turret==truck.gunner_seat and game.players[2].mounted_turret==truck.passenger_left_seat and game.players[3].mounted_turret==truck.passenger_right_seat,"Other actual crew retain their firing seats during tire failure")
	check(truck.fuel<initial_fuel and is_equal_approx(truck.fuel,initial_fuel-(truck.travel_distance-initial_distance)*truck.FUEL_PER_PIXEL*truck.fuel_multiplier),"Forward and reverse distance consume the exact finite trip fuel")
	check(truck.position.x>initial_x and truck.wheel_phase>initial_wheel,"Wheel rotation and trip displacement have stayed linked")
	await wait_physics(.18)
	trace("rupture-impact")
	await wait_physics(.52)
	trace("rupture-settled")
	Input.action_press("p1_interact")
	await wait_physics(.4)
	Input.action_release("p1_interact")
	check(truck.journey_state.repair_operator==1 and truck.journey_state.repair_work>0,"Real tool input works during the live hostile flat scene")
	check(truck.defenders.is_empty() and game.players.size()==4,"Presentation has not changed crew or authority ownership")
	evidence={"distance":truck.travel_distance-initial_distance,"fuel_spent":initial_fuel-truck.fuel,"mg_shots":truck.flash_tick,"personal_rounds_remaining":[personal[0].current_ammo()+personal[0].reserve,personal[1].current_ammo()+personal[1].reserve],"initial_personal_rounds":rounds,"phase":truck.journey_state.phase,"work":truck.journey_state.repair_work,"human_count":game.players.size(),"ambushes":game.expedition.ambushes}
	await finish()
