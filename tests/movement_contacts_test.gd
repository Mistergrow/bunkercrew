extends SceneTree
## Real actors, animation anchors, terrain queries and spatial audio. Movement
## is deterministic here; the shared contact path is also used by client views.
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
var game
var observed_plumes := 0
var wrong_origins := false

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("MOVEMENT %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func walk(worker: Worker,seconds: float,dx: float=100.0) -> void:
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	for frame in ceili(seconds*60):
		worker.velocity = Vector2(dx,0)
		worker.position.x += dx/60.0
		visual._process(1.0/60.0)
		game.weather.surface_effects.advance(1.0/60.0)
		worker.wetness.advance(1.0/60.0)
		observed_plumes = maxi(observed_plumes,game.weather.surface_effects.ground.plumes.size())
		for chip in game.weather.surface_effects.ground.chips:
			wrong_origins = wrong_origins or absf(float(chip.origin.y)-430.0)>.01

func relocate(worker: Worker,point: Vector2) -> void:
	worker.position = point
	worker.wetness._last_position = point
	worker.wetness._previous_contacts.clear()
	worker.wetness._travel = 0
	worker.wetness._last_step_time = -10
	worker._landing_time = 0
	worker._jump_windup = 0
	worker.get_node("PixelVisual")._step = 0

func stage_landing_before_render(worker: Worker,character: String = "ivo") -> int:
	worker.character_id = character
	worker._airborne = true
	worker.climbing = false
	worker.show()
	worker.velocity = Vector2.ZERO
	relocate(worker,Vector2(1000,410))
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	visual._process(.6)
	worker.wetness.advance(.05)
	var before := worker.wetness.steps_emitted
	worker.position.y = 430
	worker._airborne = false
	worker._landing_time = .15
	# Actual scheduling: physics changes the body while visual._process still
	# has its previous authored fall/frame2 sole positions.
	worker.wetness.advance(1.0/60.0)
	return before

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(2,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.settings_path = "user://movement-contact-fixture.cfg"
	game.audio.set_sfx_volume(.65)
	for frame in 3: await physics_frame
	freeze(game)
	var surfaces = game.weather.surface_effects
	var worker: Worker = game.players[0]
	var visual: WorkerVisual = worker.get_node("PixelVisual")
	game.camera.position = Vector2(1000,450)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	for character in ["mara","branko","ivo","nora","levin","selma"]:
		worker.character_id = character
		worker._airborne = false
		relocate(worker,Vector2(900,430))
		var before := worker.wetness.steps_emitted
		var sounds: int = game.audio.movement.steps_played
		observed_plumes = 0
		wrong_origins = false
		walk(worker,3.0)
		var contacts := worker.wetness.steps_emitted-before
		check(contacts>=4 and contacts<=20,"%s real walking poses create bounded foot contacts (%d)"%[character,contacts])
		check(game.audio.movement.steps_played>sounds,"%s contacts reach actual spatial audio voices"%character)
		check(observed_plumes>0 and not wrong_origins,"%s dry dust originates on actual floor support"%character)
	var steps := worker.wetness.steps_emitted
	walk(worker,1.0,0.0)
	check(worker.wetness.steps_emitted==steps,"Standing idle cannot reuse distance from an earlier walk")
	worker.climbing = true
	walk(worker,1.0)
	check(worker.wetness.steps_emitted==steps,"Ladder animation creates no ground footfalls")
	worker.climbing = false
	worker._airborne = true
	relocate(worker,Vector2(950,375))
	walk(worker,.6)
	check(worker.wetness.steps_emitted==steps,"Airborne soles never produce dust, water or footstep sound")
	worker.position.y = 430
	worker._airborne = false
	worker._landing_time = .15
	worker.velocity = Vector2.ZERO
	visual._process(1.0/60.0)
	worker.wetness.advance(1.0/60.0)
	check(worker.wetness.steps_emitted==steps+1,"Landing creates one supported contact for both feet")
	worker._landing_time = 0
	steps = worker.wetness.steps_emitted
	worker.position.x += 300
	worker.wetness.advance(.1)
	check(worker.wetness.steps_emitted==steps,"Teleporting creates no false trail or landing sound")
	worker._airborne = true
	worker.position.y -= 35
	worker.wetness.advance(.1)
	worker._airborne = false
	worker.position = Vector2(930,430)
	worker.wetness.advance(.1)
	worker.wetness.advance(.1)
	check(worker.wetness.steps_emitted==steps,"Air-to-ground teleport cannot become a delayed false landing")
	relocate(worker,Vector2(900,430))
	worker.hide()
	walk(worker,1.0)
	check(worker.wetness.steps_emitted==steps,"Hidden actors do not leave invisible footprints")
	worker.show()
	for character in ["mara","branko","ivo"]:
		var before := stage_landing_before_render(worker,character)
		visual._process(1.0/30.0)
		worker.wetness.advance(1.0/60.0)
		check(worker.wetness.steps_emitted==before+1,"%s physics landing produces exactly one supported contact when the render pose catches up"%character)
		for tick in 12:
			worker.wetness.advance(1.0/60.0)
		check(worker.wetness.steps_emitted==before+1,"%s held landing pose cannot repeat the buffered event"%character)
	for cancellation in ["expired","hidden","climbing","teleport","unsupported"]:
		var before := stage_landing_before_render(worker)
		check(worker.wetness.steps_emitted==before,"Ivo's raised fall soles defer %s fixture until a real contact"%cancellation)
		match cancellation:
			"expired": worker.wetness.advance(.16)
			"hidden":
				worker.hide()
				worker.wetness.advance(1.0/60.0)
				worker.show()
			"climbing":
				worker.climbing = true
				worker.wetness.advance(1.0/60.0)
				worker.climbing = false
			"teleport":
				worker.position.x += 300
				worker.wetness.advance(1.0/60.0)
			"unsupported": worker.position.y = 390
		visual._process(1.0/30.0)
		worker.wetness.advance(1.0/60.0)
		check(worker.wetness.steps_emitted==before,"Pending landing produces no contact after %s"%cancellation)
	worker.wetness.advance(.2)
	steps = worker.wetness.steps_emitted
	game.weather.set_reduced_effects(true)
	relocate(worker,Vector2(900,430))
	var sound_before: int = game.audio.movement.steps_played
	walk(worker,1.8)
	check(game.audio.movement.steps_played>sound_before and surfaces.ground.plumes.is_empty() and surfaces.ground.chips.is_empty(),"F3 preserves useful footstep sound while removing extra debris")
	game.weather.set_reduced_effects(false)
	relocate(worker,Vector2(900,430))
	steps = worker.wetness.steps_emitted
	for frame in 180:
		worker.velocity = Vector2(100,0)
		if frame%2==0:
			worker.position.x += 100.0/30.0
			visual._process(1.0/30.0)
		surfaces._physics_process(1.0/60.0)
		worker.wetness.advance(1.0/60.0)
	check(worker.wetness.steps_emitted>=steps+4,"30 Hz position/animation updates still produce contacts with 60 Hz physics")
	for kind in EnemyCatalog.GROUND_CLASSES:
		var enemy = game._entity("ground_infantry" if EnemyCatalog.is_human(kind) else "enemy",Vector2(960,430),{"kind":kind,"wave":1})
		freeze(enemy)
		enemy.moving = true
		enemy.gait = 0
		enemy.wetness._last_position = enemy.position
		var before: int = enemy.wetness.steps_emitted
		for frame in 180:
			enemy.position.x += float(enemy.move_speed)/60.0
			enemy.gait += float(enemy.profile.gait)/60.0
			enemy._pose_parts()
			surfaces._physics_process(1.0/60.0)
			enemy.wetness.advance(1.0/60.0)
		var contacts: int = enemy.wetness.steps_emitted-before
		check(contacts>=3 and contacts<=20,"%s feet produce weight-appropriate bounded movement contacts (%d)"%[kind,contacts])
		before = enemy.wetness.steps_emitted
		enemy.moving = false
		for frame in 90:
			enemy.gait += .15
			enemy._pose_parts()
			enemy.wetness.advance(1.0/60.0)
		check(enemy.wetness.steps_emitted==before,"%s standing gestures do not create footsteps"%kind)
		enemy.queue_free()
		await process_frame
	# Client entity simulation is frozen, while visual children remain local.
	var replication := preload("res://scripts/network_world.gd").new()
	replication.bind(game)
	replication.freeze_client()
	relocate(worker,Vector2(900,430))
	steps = worker.wetness.steps_emitted
	walk(worker,2.0)
	check(worker.wetness.steps_emitted>steps,"A frozen client actor still presents local movement contacts")
	check(await Cleanup.free_scene(game,self),"All spatial audio and scene resources are released")
	print("MOVEMENT CONTACTS: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
