extends "res://tests/network_gameplay_peer.gd"
## Four OS processes exchange every gameplay state over authenticated ENet.
## Files contain only readiness, sample reports and shutdown acknowledgements.
var slot := 1
var environment_id := "ash_foundry"
var rendered := false
var reduced := false
var warmup := 120
var measured_frames := 600
var live_input := false
var hit_counts: Dictionary = {}
var hit_damage: Dictionary = {}
var projectile_spawns := 0
var captured_reloads: Dictionary = {}
var sample_reloads: Dictionary = {}
var input_pulse_until := 0
var next_supply_input := 0
var initial_ammunition_rounds := 0
var combat_start: Dictionary = {}
var combat_began := 0
var combat_failed := false
var last_shots: Array = []
var last_shot_times: Array[int] = []
var maximum_silence: Array[float] = [0.0,0.0,0.0,0.0]
var minimum_ammo: Array[int] = [1000,1000,1000,1000]
const AMMO_CRATE := preload("res://scripts/convoy_supply.gd")

static func release_action(action: String) -> void:
	# Godot synthesizes a released edge even when action_release is repeated on
	# an already released key. A real user releases once, rather than every frame.
	if Input.is_action_pressed(action): Input.action_release(action)

func ammunition_stock() -> int:
	var total := 0
	for crate in get_nodes_in_group("supplies"):
		if crate.game==game and crate.kind=="ammo": total+=int(crate.amount)*AmmoTransfer.PACK_SIZE
	return total

func combat_counters() -> Dictionary:
	var attacks := 0
	for enemy in machines():
		attacks+=int(enemy.attack_count)
		if enemy is SiegeMachine: attacks+=int(enemy.worker_attack_count)
	return {"shots":game.players.map(func(worker): return worker.get_node("WorkerWeapon")._shot_index),"hp":game.players.map(func(worker): return worker.hp),"hits":hit_counts.duplicate(),"damage":hit_damage.duplicate(),"projectiles":projectile_spawns,"attacks":attacks}

func observe_combat() -> void:
	if slot!=1 or combat_began==0 or combat_failed: return
	var now := Time.get_ticks_usec()
	for index in 4:
		var weapon: Node=game.players[index].get_node("WorkerWeapon")
		maximum_silence[index]=maxf(maximum_silence[index],(now-last_shot_times[index])/1000000.0)
		if int(weapon._shot_index)!=int(last_shots[index]):
			last_shots[index]=int(weapon._shot_index)
			last_shot_times[index]=now
		minimum_ammo[index]=mini(minimum_ammo[index],int(weapon.total_ammunition()))
		if maximum_silence[index]>5.0 or minimum_ammo[index]<=0:
			combat_failed=true
			publish("sample_failure"+str(slot),{"worker":index+1,"maximum_silent_seconds":maximum_silence,"minimum_ammunition":minimum_ammo})
			check(false,"each normal weapon sustains measured firing with finite ammunition")
			return

func synchronized_samples() -> bool:
	publish("warmed"+str(slot))
	var deadline := Time.get_ticks_msec()+45000
	while true:
		var ready: bool=[2,3,4].all(func(id): return not read_stage("warmed"+str(id)).is_empty()) if slot==1 else not read_stage("sample_start").is_empty()
		if ready: break
		if Time.get_ticks_msec()>deadline or not playing(): return false
		update_pointer()
		await process_frame
	if slot==1:
		combat_start=combat_counters()
		combat_began=Time.get_ticks_usec()
		last_shots=combat_start.shots.duplicate()
		last_shot_times.assign([combat_began,combat_began,combat_began,combat_began])
		sample_reloads.clear()
		publish("sample_start")
	release_action("p1_reload")
	release_action("p1_cycle_target")
	input_pulse_until=0
	next_supply_input=Time.get_ticks_msec()+700
	return true

func add_combat_report(report: Dictionary) -> void:
	observe_combat()
	var end := combat_counters()
	report.hit_counts={}
	report.hit_damage={}
	report.normal_reload_seen=captured_reloads.duplicate()
	report.sample_reload_seen=sample_reloads.duplicate()
	report.worker_projectile_spawns=int(end.projectiles)-int(combat_start.projectiles)
	report.enemy_attacks=int(end.attacks)-int(combat_start.attacks)
	report.shots_fired=[]
	report.player_damage_received=[]
	report.ammunition_remaining=[]
	report.total_shots_fired=end.shots.duplicate()
	report.initial_ammunition_rounds=initial_ammunition_rounds
	report.remaining_supply_rounds=ammunition_stock()
	report.minimum_ammunition=minimum_ammo
	report.maximum_silent_seconds=maximum_silence
	report.combat_window_seconds=(Time.get_ticks_usec()-combat_began)/1000000.0
	for index in 4:
		var id := str(index+1)
		report.hit_counts[id]=int(end.hits.get(id,0))-int(combat_start.hits.get(id,0))
		report.hit_damage[id]=float(end.damage.get(id,0.0))-float(combat_start.damage.get(id,0.0))
		report.shots_fired.append(int(end.shots[index])-int(combat_start.shots[index]))
		report.player_damage_received.append(float(combat_start.hp[index])-float(end.hp[index]))
		report.ammunition_remaining.append(game.players[index].get_node("WorkerWeapon").total_ammunition())

func supply_input(worker: Node) -> void:
	var now := Time.get_ticks_msec()
	if now>=input_pulse_until:
		release_action("p1_reload")
		release_action("p1_cycle_target")
	if now<next_supply_input: return
	var weapon: Node=worker.get_node("WorkerWeapon")
	var source: Node=worker.focus
	if int(weapon.reserve)<45:
		var action := "p1_reload" if is_instance_valid(source) and source is Supply and source.kind=="ammo" else "p1_cycle_target"
		Input.action_press(action)
		input_pulse_until=now+300
		next_supply_input=now+700

func _run() -> void:
	overall_timeout_ms=240000
	role=OS.get_environment("LASTSHIFT_GAMEPLAY_ROLE")
	slot=OS.get_environment("LASTSHIFT_PARTY_SLOT").to_int()
	prefix=OS.get_environment("LASTSHIFT_GAMEPLAY_PATH")
	environment_id=OS.get_environment("BUNKERCREW_PERF_ENVIRONMENT")
	reduced=OS.get_environment("BUNKERCREW_PERF_REDUCED")=="1"
	rendered=OS.get_environment("BUNKERCREW_PERF_RENDER_SLOT").to_int()==slot
	warmup=OS.get_environment("BUNKERCREW_PERF_WARMUP").to_int()
	measured_frames=OS.get_environment("BUNKERCREW_PERF_FRAMES").to_int()
	if slot not in [1,2,3,4] or prefix.is_empty() or environment_id not in ["ash_foundry","mountain_pass"] or warmup<60 or measured_frames<120 or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		await finish(false,"invalid isolated benchmark arguments")
		return
	if rendered and DisplayServer.get_name()=="headless":
		await finish(false,"requested rendering requires a native display")
		return
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1920,1080)
	if rendered: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0 if rendered else 60
	game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.combat_events.persistence_enabled=false
	game.hud.overlay="network"
	game.network.listen_port=OS.get_environment("LASTSHIFT_TEST_PORT").to_int()
	game.network.lan_discovery_port=OS.get_environment("LASTSHIFT_TEST_DISCOVERY_PORT").to_int()
	game.network.lan_discovery_targets.assign(["127.0.0.1"])
	if slot==1: await host_combat()
	else: await guest_combat()

func each(stage: String,seconds: float=30.0) -> bool:
	for id in [2,3,4]:
		if not await barrier(stage+str(id),seconds): return false
	return true

func machines() -> Array:
	return get_nodes_in_group("enemies").filter(func(enemy): return enemy.game==game and not enemy.dead and not enemy.is_queued_for_deletion())

func fix_camera() -> void:
	# Hold only camera tracking. Simulation, player animation, audio, AI and
	# weather all retain their real callbacks and engine physics clocks.
	game.player_camera.set_process(false)
	game.camera.position=Vector2(1120,70)
	game.camera.zoom=Vector2.ONE*.75
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.weather.set_reduced_effects(reduced)

func credit(kind: String,data: Dictionary) -> void:
	if kind!="hit": return
	var id: String=str(data.get("player_id",0))
	hit_counts[id]=int(hit_counts.get(id,0))+1
	hit_damage[id]=float(hit_damage.get(id,0.0))+float(data.get("amount",0.0))

func child_created(child: Node) -> void:
	if child is WorkerShot: projectile_spawns+=1

func update_pointer() -> void:
	if not live_input or not playing(): return
	var targets:=machines()
	if targets.is_empty(): return
	var worker: Node2D=game.players[slot-1]
	var target: Node2D=targets[0]
	var best:=INF
	for enemy: Node2D in targets:
		if enemy is AirMachine: continue
		var distance: float=worker.global_position.distance_squared_to(enemy.global_position)
		if distance<best: best=distance;target=enemy
	var point: Vector2=target.global_position-Vector2(0,float(target.profile.get("center_y",30.0)))
	var screen: Vector2=root.get_final_transform()*(game.get_global_transform_with_canvas()*point)
	var event:=InputEventMouseMotion.new()
	event.position=screen
	event.global_position=screen
	Input.parse_input_event(event)
	Input.action_press("p1_fire")
	supply_input(worker)
	observe_combat()
	# Observe normal finite reloads on the authoritative host. No ammunition,
	# cooldown, damage or AI timers are rewritten during warmup/measurement.
	if slot==1:
		for index in 4:
			if game.players[index].get_node("WorkerWeapon").reload_timer>0:
				captured_reloads[str(index+1)]=true
				if combat_began>0: sample_reloads[str(index+1)]=true

func frame_step() -> void:
	update_pointer()
	if rendered: await RenderingServer.frame_post_draw
	else: await process_frame
	refresh_game()

func metrics(samples: Array[float]) -> Dictionary:
	var ordered:=samples.duplicate()
	ordered.sort()
	var total:=0.0
	for value in samples: total+=value
	return {"mean":total/samples.size(),"p95":ordered[ceili(ordered.size()*.95)-1],"max":ordered[-1]}

func sample_frames() -> Dictionary:
	fix_camera()
	var warmup_started:=Time.get_ticks_usec()
	var actual_warmup_frames:=0
	while actual_warmup_frames<warmup or Time.get_ticks_usec()-warmup_started<2000000:
		await frame_step()
		actual_warmup_frames+=1
	var warmup_seconds: float=(Time.get_ticks_usec()-warmup_started)/1000000.0
	var size:=Vector2i.ZERO
	if rendered:
		size=root.get_texture().get_image().get_size()
		if not check(size==Vector2i(1920,1080),"native viewport is exactly 1920x1080"): return {}
	if not await synchronized_samples():
		check(false,"all four peers complete warmup before shared combat samples")
		return {}
	var baseline_seq: int=game.network.sent_snapshots if slot==1 else game.network.received_snapshots
	var baseline_clock: float=game.elapsed
	var physics_frame_start:=Engine.get_physics_frames()
	var intervals: Array[float]=[]
	var calls: Array[float]=[]
	var physics: Array[float]=[]
	var process_times: Array[float]=[]
	var min_enemies:=40
	var max_enemies:=40
	var min_live_workers:=4
	var began:=Time.get_ticks_usec()
	var previous:=began
	for _frame in measured_frames:
		await frame_step()
		var now:=Time.get_ticks_usec()
		intervals.append((now-previous)/1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		physics.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0)
		process_times.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		previous=now
		if combat_failed: return {}
		var enemy_count:=machines().size()
		min_enemies=mini(min_enemies,enemy_count)
		max_enemies=maxi(max_enemies,enemy_count)
		var live_workers: int=game.players.filter(func(worker): return not worker.is_downed() and worker.hp>0).size()
		min_live_workers=mini(min_live_workers,live_workers)
		if enemy_count!=40 or live_workers!=4:
			publish("sample_failure"+str(slot),{"frame":_frame,"enemies":enemy_count,"live_workers":live_workers,"worker_levels":game.players.map(func(worker): return worker.progression.level),"worker_max_hp":game.players.map(func(worker): return worker.max_hp)})
			check(false,"prepared population changed during the actual sample window")
			return {}
		if not playing() or not game.network.world.last_error.is_empty():
			publish("sample_failure"+str(slot),{"frame":_frame,"state":game.network.state,"error":game.network.error_message,"world_error":game.network.world.last_error,"paused":paused,"connected":game.network.peer_connected})
			check(false,"all authenticated peers remain playing with valid snapshots")
			return {}
	var seq: int=game.network.sent_snapshots if slot==1 else game.network.received_snapshots
	var elapsed: float=(Time.get_ticks_usec()-began)/1000000.0
	var report: Dictionary={"role":role,"slot":slot,"rendered":rendered,"environment":str(game.scenery.environment_id),"scenario_environment":str(game.scenario_options.environment),"requested_environment":environment_id,"reduced_effects":game.weather.reduced_effects,"viewport":[size.x,size.y],"warmup_frames":actual_warmup_frames,"requested_warmup_frames":warmup,"warmup_seconds":warmup_seconds,"measured_frames":measured_frames,"frame_samples_ms":intervals,"frame_ms":metrics(intervals),"draw_calls":metrics(calls),"physics_ms":metrics(physics),"engine_process_ms":metrics(process_times),"elapsed_seconds":elapsed,"simulation_seconds":game.elapsed-baseline_clock,"physics_ticks":Engine.get_physics_frames()-physics_frame_start,"snapshots":seq-baseline_seq,"snapshots_per_second":(seq-baseline_seq)/elapsed/(3.0 if slot==1 else 1.0),"configured_snapshot_interval_seconds":game.network.SNAPSHOT_INTERVAL,"min_enemies":min_enemies,"max_enemies":max_enemies,"enemies":machines().size(),"min_live_workers":min_live_workers,"players":game.players.size(),"network_error":game.network.world.last_error,"microphone_open":game.microphone.capturing}
	report.mean_fps=1000.0/float(report.frame_ms.mean)
	report.meets_frame_target=rendered and report.mean_fps>=60.0 and report.frame_ms.p95<=16.7
	if rendered and OS.get_environment("BUNKERCREW_PERF_CAPTURE")=="1":
		var output:=OS.get_environment("BUNKERCREW_PERF_CASE_OUTPUT").path_join(role+".png")
		check(root.get_texture().get_image().save_png(output)==OK,"native combat frame capture saved")
	check(min_enemies==40 and max_enemies==40 and min_live_workers==4 and game.players.size()==4,"four real workers and exactly forty living enemies persist during all samples")
	check(report.environment==environment_id and report.scenario_environment==environment_id,"actual scenery and scenario both match the requested environment")
	check(report.physics_ticks>0 and report.simulation_seconds>0,"engine physics and live simulation advance during measurement")
	check(report.snapshots>0,"fresh gameplay snapshots cross the actual local sockets during measurement")
	check(not game.microphone.capturing,"physical microphone remains closed")
	return report

func host_combat() -> void:
	game.network.host_room("")
	if not await wait_for(func(): return game.network.state=="lobby","local host lobby",20.0): await finish(false,"host");return
	publish("room",{"code":game.network.room_code})
	if not await each("joined") or not await wait_for(func(): return game.network.connected_player_count()==4,"four authenticated connections",30.0): await finish(false,"joins");return
	game.network.start_match({"environment":environment_id,"build_type":"bastion","position":"left"},game.selected_characters)
	if not await wait_for(playing,"host playing",40.0) or not await each("started",40.0): await finish(false,"start");return
	game.rounds.running=false
	game.rounds.wave=20
	game.rounds.phase="attack"
	# Bound HP pools preserve this repeatable load. All collision, damage,
	# windups, abilities, player medical reactions and enemy physics remain real.
	game.core.max_hp=1000000.0
	game.core.hp=1000000.0
	for wall in get_nodes_in_group("walls"):
		# The starter perimeter keeps its catalogue HP and can genuinely break.
		if wall is DefenseWall and wall.game==game and wall.max_hp>0: wall.max_hp=1000000.0;wall.hp=1000000.0
	for index in 4:
		var worker=game.players[index]
		# Normal level-up recalculates HP from character stats. Prepare capped
		# crew so this temporary HP load remains stable without intercepting XP,
		# damage, medicine or any physics callback during the measurement.
		worker.progression.level=PlayerProgression.MAX_LEVEL
		worker.progression.xp=0.0
		worker.max_hp=1000000.0
		worker.hp=1000000.0
		worker.global_position=Vector2(980+index*28,430)
		worker.inventory.clear()
		var weapon=worker.get_node("WorkerWeapon")
		weapon.loaded.rifle=6
		weapon.reserve=90
	# Fifteen finite dynamic crates cover the real defense apron. Each contains
	# 100 normal twenty-round packs. Refills consume crates through normal focus,
	# sampled reload input and AmmoTransfer; no timer or ammo is rewritten later.
	for x in range(750,1690,64):
		var crate := AMMO_CRATE.new()
		crate.game=game
		crate.position=Vector2(x,430)
		crate.amount=100
		game.add_child(crate)
	initial_ammunition_rounds=ammunition_stock()+4*96
	game.combat_events.event.connect(credit)
	game.child_entered_tree.connect(child_created)
	for index in 40:
		var kind: String=EnemyCatalog.CLASS_ORDER[index%EnemyCatalog.CLASS_ORDER.size()]
		var at:=Vector2(1190+index%12*32,430)
		var factory: String="ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"
		if AirEnemyCatalog.is_air(kind): factory="air_enemy";at.y=180+index%3*40
		var enemy=game._entity(factory,at,{"kind":kind,"wave":20})
		enemy.max_hp=500000.0
		enemy.hp=500000.0
		if is_instance_valid(enemy.get("wetness")): enemy.wetness.amount=.85 if environment_id=="mountain_pass" else 0.0
	fix_camera()
	publish("prepared")
	if not await each("snapshot_ready",40.0): await finish(false,"snapshot barrier");return
	live_input=true
	publish("measure")
	var report:=await sample_frames()
	if report.is_empty(): await finish(false,"measurement");return
	var sampling_deadline:=Time.get_ticks_msec()+80000
	while [2,3,4].any(func(id): return read_stage("sample_done"+str(id)).is_empty()):
		if Time.get_ticks_msec()>sampling_deadline or not playing() or combat_failed: await finish(false,"peer sampling");return
		update_pointer()
		await process_frame
	add_combat_report(report)
	check(report.worker_projectile_spawns>0 and report.hit_counts.values().all(func(count): return count>0) and report.shots_fired.all(func(count): return count>0),"all four normal weapons launch measured real projectiles and receive measured collision hit credit")
	check(report.enemy_attacks>0 and report.player_damage_received.any(func(amount): return amount>0),"genuine enemy attacks deal real damage during the measurement window")
	check(captured_reloads.size()==4 and report.minimum_ammunition.all(func(amount): return amount>0),"all four weapons perform authentic reloads and sustain measured finite ammunition")
	var rounds_left: int=report.remaining_supply_rounds
	var spent := 0
	for index in 4:
		rounds_left+=int(report.ammunition_remaining[index])
		spent+=int(report.total_shots_fired[index])
	check(initial_ammunition_rounds-rounds_left==spent,"finite crates and weapon ammunition conserve every normally fired round")
	publish("host_report",report)
	live_input=false
	release_action("p1_fire")
	release_action("p1_reload")
	release_action("p1_cycle_target")
	publish("shutdown")
	if not await each("shutdown_seen"): await finish(false,"shutdown acknowledgements");return
	await finish(failures==0,"live combat, finite weapons, attacks, configured 20Hz snapshots and real four-peer cleanup")

func guest_combat() -> void:
	if not await barrier("room",30.0): await finish(false,"host marker");return
	game.network.join_room("",str(read_stage("room").code))
	if not await wait_for(func(): return game.network.state=="lobby" and game.network._authenticated,"guest authenticated",30.0): await finish(false,"join");return
	check(game.network.local_player_id==slot,"sequential authentication assigns the actual requested slot")
	publish("joined"+str(slot))
	if not await wait_for(playing,"guest playing",40.0): await finish(false,"start");return
	publish("started"+str(slot))
	if not await barrier("prepared",40.0) or not await wait_for(func(): return machines().size()==40 and game.players.size()==4 and game.network.received_snapshots>=3,"actual world snapshot barrier",40.0): await finish(false,"prepared");return
	fix_camera()
	publish("snapshot_ready"+str(slot))
	if not await barrier("measure",40.0): await finish(false,"measure");return
	live_input=true
	var report:=await sample_frames()
	if report.is_empty(): await finish(false,"measurement");return
	# Keep the normal fire input active until the host has also sampled its
	# requested frames; different renderer speeds must not starve remote combat.
	publish("peer_report"+str(slot),report)
	publish("sample_done"+str(slot))
	while read_stage("shutdown").is_empty() and not done:
		update_pointer()
		await process_frame
	live_input=false
	release_action("p1_fire")
	release_action("p1_reload")
	release_action("p1_cycle_target")
	publish("shutdown_seen"+str(slot))
	# Retire together after acknowledgements; do not trigger a reconnect pause
	# while another peer is still being sampled.
	await delay(.15)
	await finish(failures==0,"replica combat snapshots, local sampled input and cleanup")
