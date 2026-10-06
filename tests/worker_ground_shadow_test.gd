extends SceneTree
## Real CharacterBody2D jumps over real colliders in two isolated World2Ds.
const PLAYER:=preload("res://scenes/player.tscn")
const CLEANUP:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/solo-story/shadows/"
var checks:=0
var failures:=0
var evidence: Dictionary={}

class TestWorld extends Node2D:
	var started:=true
	var players: Array=[]
	func can_affect_world() -> bool: return true

class PhysicsDriver extends Node:
	var actor: Worker
	var falling:=false
	func _physics_process(delta: float) -> void:
		if not falling: return
		actor.velocity.y+=Worker.GRAVITY*delta
		actor.move_and_slide()
		actor._airborne=not actor.is_on_floor()

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func view_with_world() -> Dictionary:
	var view:=SubViewport.new()
	view.size=Vector2i(800,600)
	view.world_2d=World2D.new()
	root.add_child(view)
	var world:=TestWorld.new()
	view.add_child(world)
	return {"view":view,"world":world}

func rectangle(world: Node2D,rect: Rect2,layer:=1) -> StaticBody2D:
	var body:=StaticBody2D.new()
	body.collision_layer=layer
	body.collision_mask=0
	var collider:=CollisionShape2D.new()
	var shape:=RectangleShape2D.new()
	shape.size=rect.size
	collider.shape=shape
	collider.position=rect.get_center()
	body.add_child(collider)
	world.add_child(body)
	return body

func actor_in(world: TestWorld,point: Vector2,id:=1) -> Worker:
	var actor:=PLAYER.instantiate() as Worker
	actor.game=world
	actor.player_id=id
	actor.position=point
	world.players.append(actor)
	world.add_child(actor)
	actor.set_physics_process(false)
	for child in actor.find_children("*","Node",true,false):
		if child.name!="GroundShadow": child.set_physics_process(false)
	actor.get_node("PixelVisual").set_process(false)
	actor.get_node("WorkerWeapon").set_process(false)
	return actor

func settled(count:=2) -> void:
	for frame in count:
		await physics_frame
		await process_frame

func support_at(actor: Worker,at: Vector2,y: float,label: String) -> void:
	actor.position=at
	await settled()
	var shadow:=actor.get_node("PixelVisual/GroundShadow")
	check(shadow.has_support and absf(shadow.ground_point.y-y)<.1,label+" uses the real support height")
	check(shadow.global_position.is_equal_approx(shadow.ground_point),label+" draws at world support, independent of actor transform")
	check(shadow.rays_last_tick==3,label+" spends exactly three bounded rays")

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	InputSetup.install()
	var fixture:=view_with_world()
	var world: TestWorld=fixture.world
	rectangle(world,Rect2(-1000,430,3000,40))
	var roof:=rectangle(world,Rect2(400,245,200,20))
	# Wrong-layer bodies and Areas at a higher Y must not become support.
	rectangle(world,Rect2(70,330,60,10),2)
	var area:=Area2D.new()
	area.collision_layer=1
	var area_shape:=CollisionShape2D.new()
	var area_rect:=RectangleShape2D.new()
	area_rect.size=Vector2(80,10)
	area_shape.shape=area_rect
	area.position=Vector2(100,350)
	area.add_child(area_shape)
	world.add_child(area)
	var slope:=StaticBody2D.new()
	slope.collision_layer=1
	slope.collision_mask=0
	var polygon:=CollisionPolygon2D.new()
	polygon.polygon=PackedVector2Array([Vector2(700,350),Vector2(860,302),Vector2(860,450),Vector2(700,450)])
	slope.add_child(polygon)
	world.add_child(slope)
	var actor:=actor_in(world,Vector2(100,430))
	var shadow:=actor.get_node("PixelVisual/GroundShadow")
	await support_at(actor,Vector2(100,400),430,"Terrain with decorative body and Area above it")
	check(shadow.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST and shadow.is_set_as_top_level(),"Ground shadow has native nearest filtering and independent world transform")
	check(shadow.z_index==actor.z_index-1,"Ground shadow stays immediately behind worker art")
	# The actual collision body moves with gravity/move_and_slide, not a tween.
	actor.position=Vector2(180,430)
	actor.velocity=Vector2.ZERO
	var driver:=PhysicsDriver.new()
	driver.actor=actor
	driver.process_physics_priority=-1
	world.add_child(driver)
	driver.falling=true
	await settled(4)
	check(actor.is_on_floor(),"Actual player collider lands on actual terrain")
	var rest_width: float=shadow.right_extent-shadow.left_extent
	var rest_opacity: float=shadow.opacity
	actor.velocity.y=-Worker.JUMP_SPEED
	actor._airborne=true
	var lowest:=actor.position.y
	var apex_width:=rest_width
	var apex_opacity:=rest_opacity
	for frame in 56:
		await settled(1)
		check(shadow.has_support and absf(shadow.global_position.y-430)<.1,"Actual jump frame %d leaves shadow on ground"%frame)
		check(shadow.rays_last_tick<=3,"Actual jump frame %d respects query budget"%frame)
		if actor.position.y<lowest:
			lowest=actor.position.y
			apex_width=shadow.right_extent-shadow.left_extent
			apex_opacity=shadow.opacity
	check(lowest<370 and apex_width<rest_width-5 and apex_opacity<rest_opacity-.05,"Real airborne height softens and narrows shadow without moving it upward")
	check(actor.is_on_floor() and absf(shadow.opacity-rest_opacity)<.01,"Landing restores the ground contact shadow")
	evidence.jump={"floor_y":430,"actual_apex_feet_y":lowest,"ground_width":rest_width,"apex_width":apex_width,"ground_opacity":rest_opacity,"apex_opacity":apex_opacity,"frames":56}
	driver.falling=false
	await support_at(actor,Vector2(500,180),245,"Roof jump")
	await support_at(actor,Vector2(500,400),430,"Actor below roof")
	await support_at(actor,Vector2(595,190),245,"Roof edge")
	check(shadow.right_extent<=5.01 and shadow.left_extent<-10,"Roof edge clips only the unsupported side at exact collider edge")
	check((shadow.global_transform*Vector2(shadow.right_extent,0)).x<=600.01,"No projected roof shadow hangs beyond roof collider")
	await support_at(actor,Vector2(625,280),430,"Leaving roof edge")
	await support_at(actor,Vector2(500,180),245,"Closed hatch collider")
	roof.collision_layer=0
	actor.position.y=280
	await settled()
	check(shadow.has_support and absf(shadow.ground_point.y-430)<.1,"Opening real support collider immediately exposes lower floor")
	roof.collision_layer=1
	actor.position=Vector2(780,270)
	await settled()
	check(shadow.has_support and absf(shadow.ground_point.y-326)<.1,"Slope projects to actual CollisionPolygon2D surface")
	check(absf(shadow.global_rotation-atan(-.3))<.01,"Slope shadow aligns to actual physics surface normal")
	for endpoint in [shadow.left_extent,shadow.right_extent]:
		var point: Vector2=shadow.global_transform*Vector2(endpoint,0)
		check(absf(point.y-(350-(point.x-700)*.3))<.1,"Slope shadow endpoint stays on actual sloped support")
	actor.position=Vector2(858,260)
	await settled()
	check(shadow.has_support and (shadow.global_transform*Vector2(shadow.right_extent,0)).x<=860.1,"Sloped platform edge uses real polygon boundary")
	# Adjacent real tiles remain one uninterrupted coplanar support.
	rectangle(world,Rect2(-100,245,100,20))
	rectangle(world,Rect2(0,245,100,20))
	await support_at(actor,Vector2(-2,200),245,"Adjacent floor tiles")
	check(shadow.right_extent>10 and shadow.left_extent< -10,"Coplanar neighboring tile keeps full shadow across tile seam")
	var other_fixture:=view_with_world()
	rectangle(other_fixture.world,Rect2(-1000,540,3000,30))
	var other_actor:=actor_in(other_fixture.world,Vector2(100,410),2)
	await settled()
	var other_shadow:=other_actor.get_node("PixelVisual/GroundShadow")
	check(other_shadow.has_support and other_shadow.ground_point.y==540,"Separate World2D projects onto its own support rather than foreign world floor")
	check(shadow.get_world_2d()!=other_shadow.get_world_2d(),"Cross-world counterfixture genuinely has a different physics space")
	await support_at(actor,Vector2(180,370),430,"Visibility and pause fixture")
	actor.hide()
	await settled()
	check(not shadow.is_visible_in_tree() and not shadow.has_support and shadow.rays_last_tick==0,"Hidden worker suppresses ground shadow and support queries")
	actor.show()
	await settled()
	actor.get_node("PixelVisual").hide()
	await settled()
	check(not shadow.is_visible_in_tree() and shadow.rays_last_tick==0,"Hidden WorkerVisual suppresses top-level shadow")
	actor.get_node("PixelVisual").show()
	await settled()
	check(shadow.is_visible_in_tree(),"Showing worker art restores ground shadow")
	var mounted:=Node2D.new()
	world.add_child(mounted)
	actor.mounted_turret=mounted
	await settled()
	check(not shadow.has_support and shadow.rays_last_tick==0,"Mounted worker does not cast a misleading walking contact shadow")
	actor.mounted_turret=null
	await settled()
	var old_ticks: int=shadow.query_ticks
	var old_point: Vector2=shadow.global_position
	paused=true
	actor.position.y-=40
	for frame in 5: await process_frame
	check(shadow.query_ticks==old_ticks and shadow.global_position==old_point,"Actual SceneTree pause freezes shadow probes and presentation")
	paused=false
	await settled()
	check(shadow.query_ticks>old_ticks and shadow.ground_point.y==430,"Unpausing resumes actual support projection")
	world.started=false
	await settled()
	check(not shadow.has_support and shadow.rays_last_tick==0,"Menu/fake preview world without started gameplay performs no support probes")
	world.started=true
	world.players.erase(actor)
	await settled()
	check(shadow.rays_last_tick==0,"Unregistered or detached worker performs no support probes")
	world.players.append(actor)
	actor.position=Vector2(180,390)
	actor.scale=Vector2(1.4,.8)
	await settled()
	check(shadow.global_scale.is_equal_approx(Vector2.ONE) and shadow.ground_point.y==430,"Actor pose/scale cannot scale or raise its world contact shadow")
	actor.scale=Vector2.ONE
	var camera:=Camera2D.new()
	world.add_child(camera)
	camera.position=Vector2(180,390)
	camera.make_current()
	for zoom in [.45,1.0,2.5]:
		camera.zoom=Vector2.ONE*zoom
		await settled()
		check(shadow.ground_point.y==430 and shadow.global_scale==Vector2.ONE,"Camera zoom %.2f preserves world-space shadow support"%zoom)
	actor.climbing=true
	actor.inventory={"steel":3}
	actor.get_node("PixelVisual").pose_skeleton=preload("res://scripts/worker_rhythm_pose.gd").choreography("headnod",.5,"mara")
	await settled()
	check(shadow.has_support and shadow.ground_point.y==430,"Climbing, carrying and local pose offsets retain actual support")
	actor.climbing=false
	# Four-player maximum remains fixed regardless of repeated drawing calls.
	var actors: Array[Worker]=[actor]
	for id in range(2,5): actors.append(actor_in(world,Vector2(150+id*60,385),id))
	await settled()
	var total_rays:=0
	for item in actors:
		var projection:=item.get_node("PixelVisual/GroundShadow")
		total_rays+=int(projection.rays_last_tick)
		var ticks: int=projection.query_ticks
		for redraw in 20:
			projection.queue_redraw()
			projection._physics_process(0.0)
		check(projection.query_ticks==ticks,"Repeated same-frame callbacks/draw requests cannot exceed one support query set")
	check(total_rays==12,"Four active workers use at most twelve support rays per physics tick")
	evidence.query_budget={"players":4,"rays_per_physics_tick":total_rays,"calls_per_player_per_tick_maximum":3}
	actor.position=Vector2(1500,100)
	await settled()
	check(not shadow.has_support and shadow.rays_last_tick==1,"Excessive airborne drop fades out instead of inventing a floating floor")
	world.position=Vector2(900,25)
	actor.position=Vector2(180,400)
	await settled()
	check(shadow.has_support and absf(shadow.global_position.y-455)<.1 and absf(shadow.global_position.x-1080)<.1,"Translated world support is transformed exactly once")
	await CLEANUP.free_scene(fixture.view,self)
	await CLEANUP.free_scene(other_fixture.view,self)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	evidence.checks=checks
	evidence.failures=failures
	evidence.prepared_state="Actual player.tscn CharacterBody2D; real static terrain, roof, slope, changing collision layer, foreign World2D; controller disabled only to drive actual gravity/move_and_slide deterministically."
	var file:=FileAccess.open(OUTPUT+"verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(evidence,"\t"))
	file.close()
	print("WORKER GROUND SHADOW: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
