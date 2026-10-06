extends SceneTree
## Actual rain rays must strike the same native helmet surface the articulated
## renderer paints while a loaded worker nods on a heard kick. No new hitbox.
const Geometry := preload("res://scripts/actor_weather_geometry.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): _freeze(child)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	CrewRoster.persistence_enabled = false
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	game.start_scenario(1,{"environment":"mountain_pass","build_type":"bastion","position":"center"})
	game.rounds.running = false
	_freeze(game)
	var actor: Worker = game.players[0]
	actor.position = Vector2(game.scenario_bunker.room_right+150,430)
	actor.velocity = Vector2.ZERO
	actor.hurt_flash = 0.0
	actor.inventory = {"concrete":actor.capacity()}
	actor.selected_kind = "concrete"
	var visual: WorkerVisual = actor.get_node("PixelVisual")
	visual.idle_clock.wait_remaining = 1000.0
	var weather: ShiftWeather = game.weather
	await physics_frame
	for entry: Dictionary in CharacterCatalog.CHARACTERS:
		# Prepared art identity only. Live configure_character deliberately refuses
		# character swaps after a round starts; that gameplay guard stays intact.
		actor.character_id = str(entry.id)
		actor.inventory = {"concrete":actor.capacity()}
		for facing: float in [-1.0,1.0]:
			actor.facing = facing
			visual._process(0.2)
			var resting := visual.pose_skeleton.duplicate(true)
			check(resting.has("cargo"),str(entry.id)+": actual loaded rig retains its cargo")
			var rhythm := Rhythm.new()
			rhythm.configure(str(entry.id))
			rhythm.weight = 1.0
			for age: float in [0.0,.045,.11,.31,.47]:
				var pose := resting.duplicate(true)
				rhythm.apply_carry_nod(pose,{"audible_seconds":3.0+age,"last_kick_seconds":3.0,"last_kick_strength":1.0})
				visual.pose_skeleton = pose
				visual.locomotion_pose = pose
				var expected := Geometry.atlas_top(Identity.head(str(entry.id)),Rect2(0,0,112,112),Rect2(-49,-33,112,112))
				var painted := visual.global_transform*Geometry.worker_transform(visual)*PoseArt.head_transform(pose)
				var surface := Vector2(INF,INF)
				for pair: Array in expected:
					var point: Vector2 = painted*((Vector2(pair[0])+Vector2(pair[1]))*.5)
					if point.y<surface.y: surface=point
				check(surface.is_finite(),str(entry.id)+": real head texture supplies a painted helmet edge")
				weather.refresh_collision_cache()
				var hit: Dictionary = weather.trace_rain(surface-Vector2(0,8),surface+Vector2(0,4))
				check(hit.get("collider")==actor and Vector2(hit.get("position",Vector2.INF)).distance_to(surface)<.08,"Rain reaches the painted neck-pivoted "+str(entry.id)+" helmet at age "+str(age)+" facing "+str(facing))
				var before := [actor.hp,actor.position,actor.velocity,actor.inventory.duplicate(true)]
				var saturation := actor.wetness.amount
				if not hit.is_empty(): weather._rain_contact(hit,Vector2(0,310),1.0)
				check(actor.wetness.amount>=saturation and before==[actor.hp,actor.position,actor.velocity,actor.inventory],"Aligned cosmetic rain preserves movement, cargo and health")
	check(await Cleanup.free_scene(game,self),"Actual rain/head fixture releases its scene and audio")
	print("WORKER RAIN HEAD CONTACT: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
