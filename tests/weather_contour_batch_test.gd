extends SceneTree
## Compare cached alpha contours with the original per-endpoint native mapping.
## Warm-cache motion, mirrored/nonuniform transforms and pose changes must still
## follow the painted art immediately, without caching actor world positions.
const Geometry := preload("res://scripts/actor_weather_geometry.gd")
const Identity := preload("res://scripts/worker_identity_art.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)

func atlas_matches(node: Node2D, transform: Transform2D, texture: Texture2D, region: Rect2, destination: Rect2, material: String, label: String) -> void:
	var pairs := Geometry.atlas_top(texture,region,destination)
	var result: Array[Dictionary]=[]
	Geometry._atlas_segments(result,node,transform,texture,region,destination,material)
	var same := result.size()==pairs.size() and not pairs.is_empty()
	for index in pairs.size():
		var a := node.to_global(transform*Vector2(pairs[index][0]))
		var b := node.to_global(transform*Vector2(pairs[index][1]))
		var normal := (b-a).orthogonal().normalized()
		if normal.y>0: normal=-normal
		var segment: Dictionary=result[index]
		same=same and a.is_equal_approx(segment.from) and b.is_equal_approx(segment.to) and normal.is_equal_approx(segment.normal) and segment.material==material
	check(same,label+": every endpoint, normal and material matches original native mapping")
	var cached: Array=Geometry.atlas_top(texture,region,destination)
	check(is_same(cached,pairs),label+": immutable alpha samples reuse their original backing array")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args(): quit(2);return
	var game: Node=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(4,{"environment":"mountain_pass","build_type":"bastion","position":"left"})
	game.set_process(false)
	game.rounds.set_process(false)
	game.weather.set_process(false)
	game.weather.surface_effects.set_physics_process(false)
	game.medic.set_physics_process(false)
	for worker: Worker in game.players:
		worker.set_physics_process(false)
		worker.wetness.set_physics_process(false)
		worker.get_node("PixelVisual").set_process(false)
	var worker: Worker=game.players[0]
	var visual := worker.get_node("PixelVisual") as Node2D
	for character: Dictionary in CharacterCatalog.CHARACTERS:
		for back in [false,true]:
			for phase in [0.0,.7,2.1]:
				worker.position=Vector2(600+phase*40,430-phase*7)
				worker.rotation=phase*.13
				worker.scale=Vector2(-.9 if back else 1.15,.85+phase*.10)
				visual.skew=phase*.08
				var local := Transform2D(phase*.31,Vector2(phase*3,-phase*4)).scaled_local(Vector2(-1 if back else 1,1))
				var label := str(character.id)+(" back" if back else " front")+" phase "+str(phase)
				atlas_matches(visual,local,Identity.head(str(character.id),back),Rect2(0,0,112,112),Rect2(-49,-33,112,112),"metal",label+" head")
				atlas_matches(visual,local,Identity.torso(str(character.id),back),Rect2(0,0,112,112),Rect2(-48,-48,112,112),"cloth",label+" coat")
	worker.transform=Transform2D.IDENTITY
	worker.position=Vector2(600,430)
	visual.skew=0.0
	for kind: String in EnemyCatalog.CLASS_ORDER:
		if EnemyCatalog.is_human(kind): continue
		var air := AirEnemyCatalog.is_air(kind)
		var enemy: Node2D=game._entity("air_enemy" if air else "enemy",Vector2(1100,180 if air else 430),{"kind":kind,"wave":20})
		enemy.set_physics_process(false)
		enemy.wetness.set_physics_process(false)
		for phase in [0.0,.7,2.1]:
			enemy.age=phase
			enemy.weapon_recoil=phase
			if enemy is SiegeMachine: enemy.gait=phase;enemy.moving=true
			enemy._pose_parts()
			if enemy.has_method("uses_rolling_contacts") and enemy.uses_rolling_contacts(): continue
			var region: Rect2
			var destination: Rect2
			if air:
				region=AirMachine.BODY_REGIONS[enemy.profile.atlas]
				var size: Vector2=enemy.profile.body_size
				destination=Rect2(-size*.5,size)
			else:
				var chassis: String=enemy.chassis_kind()
				region=SiegeMachine.BODY_REGIONS[chassis]
				var width: float=enemy.profile.body_size.x
				if chassis=="colossus": width=74.0
				elif chassis=="siege": width=79.0
				elif chassis=="breaker": width=78.0
				destination=Rect2(Vector2(-width*.5,-19 if chassis=="runner" else -24),Vector2(width,width*region.size.y/region.size.x))
			atlas_matches(enemy.body_part,Transform2D.IDENTITY,enemy.chassis_atlas,region,destination,"metal",kind+" animated hull "+str(phase))
		enemy.free()
	var segments_before: Array[Dictionary]=worker.wetness.rain_segments()
	var images_before := Geometry._images.size()
	worker.position+=Vector2(23,-7)
	var moved: Array[Dictionary]=worker.wetness.rain_segments()
	check(moved.size()==segments_before.size() and moved[0].from.is_equal_approx(Vector2(segments_before[0].from)+Vector2(23,-7)),"Warm alpha cache follows same-frame world motion")
	check(Geometry._images.size()==images_before,"Warm silhouettes perform no additional image readback")
	check(await Cleanup.free_scene(game,self),"Actual rainy main scene releases its actor/weather nodes")
	print("WEATHER CONTOUR BATCH: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
