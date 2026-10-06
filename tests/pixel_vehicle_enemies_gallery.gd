extends SceneTree
## Native matched samples of the real convoy and enemy rigs. Timelines are
## prepared and stepped explicitly; this is art evidence, not a live playtest.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Wreck := preload("res://scripts/enemy_motion_wreck.gd")
const Journey := preload("res://scripts/convoy_journey.gd")
const OUTPUT := "res://artifacts/pixel-animation-pass-20261005/vehicles-enemies/"
const REFERENCE := Vector2(1440,900)
const ZOOM := 1.25
var phase := "final"
var view: SubViewport
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []
var transient_differences: Array[Dictionary] = []
var game
var truck
var plate: Plate
var actors: Array[Node2D] = []
var wrecks: Array[Node2D] = []

class Weather extends RefCounted:
	var reduced_effects := false

class Plate extends Node2D:
	var weather := Weather.new()
	var labels: Array[Dictionary] = []
	var caption := ""
	func _draw() -> void:
		draw_rect(Rect2(-position,get_viewport().get_visible_rect().size),Color("182220"))
		Art.text(self,Vector2(48,56),"BUNKERCREW / PIXEL MOTION",26,Art.LIGHT)
		Art.text(self,Vector2(48,90),caption,15,Art.MUTED)
		for entry: Dictionary in labels:
			Art.text(self,Vector2(entry.at)+Vector2(-126,-150),str(entry.id),16,Art.AMBER)
			if not entry.air:
				draw_line(Vector2(entry.at)+Vector2(-135,1),Vector2(entry.at)+Vector2(135,1),Color("626950"),1,false)
		Art.text(self,Vector2(48,862),"Prepared real rigs / native viewport / presentation sampled / no profile saves",13,Art.MUTED)

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func _place_plate(resolution: Vector2i) -> void:
	# Inspect native world pixels at the same scale at both viewport sizes.
	# Changing the viewport expands margins; it never stretches the actors or
	# changes the world-space aim point after the first sampled frame.
	view.size=resolution
	plate.scale=Vector2.ONE
	plate.position=(Vector2(resolution)-REFERENCE)*.5
	plate.queue_redraw()

func capture(id: String, resolution: Vector2i, state: Dictionary) -> Image:
	view.size = resolution
	if is_instance_valid(plate): _place_plate(resolution)
	if is_instance_valid(game):
		game.camera.zoom=Vector2.ONE*ZOOM
		game.camera.position=truck.position+Vector2(70*truck.facing,-140)
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		for child in game.get_children():
			if child.get_script()!=null and child.get_script().resource_path=="res://scripts/expedition_road_art.gd":
				child.depth._update_view()
				child.queue_redraw()
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	var filename := "%dx%d-%s.png"%[resolution.x,resolution.y,id]
	check(picture.get_size()==resolution and picture.save_png(OUTPUT+phase+"/"+filename)==OK,"Native framebuffer "+filename)
	captures.append({"file":filename,"id":id,"resolution":[resolution.x,resolution.y],"state":state,"prepared_state":true})
	return picture

func changed_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in first.get_height():
		for x in first.get_width():
			if first.get_pixel(x,y)!=second.get_pixel(x,y): count+=1
	return count

func _make_actor(kind: String, at: Vector2, facing: float) -> Node2D:
	var flying := AirEnemyCatalog.is_air(kind)
	var actor: Node2D=load("res://scenes/air_enemy.tscn" if flying else "res://scenes/enemy.tscn").instantiate()
	actor.kind=kind
	actor.attack_direction=facing
	actor.game=plate
	plate.add_child(actor)
	actor.position=at
	actor.scale=Vector2.ONE*ZOOM
	actor.show_status_labels=false
	freeze(actor)
	actor.age=1.17
	if flying:
		actor.flight_presentation.clock=actor.age
		actor.locked_aim=actor.global_position+Vector2(280*facing,0)
	else:
		actor.motion.pose=preload("res://scripts/enemy_motion_pose.gd").sample("scan",0,kind)
		actor.moving=false
		actor.locomotion_speed=0
	actor._pose_parts()
	plate.labels.append({"id":kind+" / "+("left" if facing<0 else "right"),"at":at,"air":flying})
	return actor

func _guns(resolution: Vector2i, facing: float, quiet: bool) -> void:
	plate=Plate.new()
	plate.caption="Actual weapon mouths / 1.25 world zoom / "+("reduced" if quiet else "standard")
	plate.weather.reduced_effects=quiet
	view.add_child(plate)
	_place_plate(resolution)
	actors.clear()
	var kinds: Array[String]=["scout_car","mortar_carrier","battle_tank","gunship","pulse_fighter","sky_fortress","bomber"]
	for index in kinds.size():
		var at:=Vector2(230+index*440,354) if index<3 else Vector2(180+(index-3)*360,672)
		actors.append(_make_actor(kinds[index],at,facing))
	var snapshots: Array[Dictionary]=[]
	for actor in actors:
		snapshots.append({"position":actor.position,"hp":actor.hp,"damage":actor.profile.damage,"children":actor.get_child_count(),"hitbox":actor.get_node("AircraftHull" if AirEnemyCatalog.is_air(actor.kind) else "MachineHitbox").shape.size})
	var first: Image
	var last: Image
	for sample in [0.0,.025,.065,.115,.225]:
		var states: Array[Dictionary]=[]
		for index in actors.size():
			var actor=actors[index]
			var flying:=AirEnemyCatalog.is_air(actor.kind)
			var duration:=.22 if actor.kind=="sky_fortress" else (.10 if flying else .13)
			actor.muzzle_flash=maxf(0,duration-sample)
			actor.attack_count=7
			actor.weapon_recoil=2.0
			actor.windup=0.0
			if actor.kind=="bomber": actor.burst_remaining=1
			actor._pose_parts()
			actor.weapon_part.queue_redraw()
			actor.body_part.queue_redraw()
			var tip: Vector2=actor.muzzle_global() if flying else actor.weapon_part.to_global(actor.weapon_muzzle())
			states.append({"id":actor.kind,"elapsed":sample,"flash_remaining":actor.muzzle_flash,"duration":duration,"mouth":[tip.x,tip.y],"damage":actor.profile.damage,"shot_count":actor.attack_count})
		var name:="guns-%s-%s-%03d"%["left" if facing<0 else "right","reduced" if quiet else "standard",roundi(sample*1000)]
		var picture:=await capture(name,resolution,{"facing":facing,"reduced":quiet,"zoom":ZOOM,"actors":states})
		if is_zero_approx(sample): first=picture
		if sample==.065: last=picture
		for index in actors.size():
			var actor=actors[index]
			var snapshot:=snapshots[index]
			check(actor.position==snapshot.position and actor.hp==snapshot.hp and actor.profile.damage==snapshot.damage and actor.get_child_count()==snapshot.children,"Draw preserves real combat identity and ownership "+actor.kind)
			check(actor.get_node("AircraftHull" if AirEnemyCatalog.is_air(actor.kind) else "MachineHitbox").shape.size==snapshot.hitbox,"Draw preserves exact hitbox "+actor.kind)
	var changed:=changed_pixels(first,last)
	transient_differences.append({"id":"guns","resolution":[resolution.x,resolution.y],"facing":facing,"reduced":quiet,"ignition_to_65ms_pixels":changed})
	if phase=="final": check(changed>12,"Actual muzzle ignition changes before any remaining ground/heavy flash expires")
	check(await Cleanup.free_scene(plate,self),"Actual weapon rigs release draw delegates")
	plate=null
	actors.clear()

func _wrecks(resolution: Vector2i, quiet: bool) -> void:
	plate=Plate.new()
	plate.caption="Actual detached equipment / 1.25 world zoom / "+("reduced" if quiet else "standard")
	plate.weather.reduced_effects=quiet
	view.add_child(plate)
	_place_plate(resolution)
	wrecks.clear()
	var kinds: Array[String]=["strider","battle_tank","gunship"]
	for index in 6:
		var actor:=_make_actor(kinds[index%3],Vector2(245+(index%3)*455,360 if index<3 else 675),-1 if index<3 else 1)
		var wreck:=Wreck.spawn(actor,actor.kind,index%3==2)
		freeze(wreck)
		wrecks.append(wreck)
		actor.free()
	var previous:=0.0
	for age in [0.0,.05,.20,.55,1.10]:
		var states: Array[Dictionary]=[]
		for wreck in wrecks:
			wreck._process(age-previous)
			states.append({"id":wreck.identity,"elapsed":wreck.elapsed,"duration":wreck.duration,"mirror":wreck.mirror,"rolling":wreck.rolling,"airborne":wreck.airborne,"parts":wreck.get_child_count()})
		await capture("wrecks-%s-%03d"%["reduced" if quiet else "standard",roundi(age*100)],resolution,{"reduced":quiet,"zoom":ZOOM,"wrecks":states})
		for wreck in wrecks:
			check(wreck.get_child_count()>=3 and not wreck.is_in_group("enemies") and not wreck.artist.is_inside_tree(),"Detached art never returns to combat "+wreck.identity)
		previous=age
	check(await Cleanup.free_scene(plate,self),"Actual detached rigs release every draw delegate")
	plate=null
	wrecks.clear()

func _prepare_road(facing: float, quiet: bool) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	AudioServer.set_bus_mute(0,true)
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","oskar"])
	game.start_scenario(4,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	game.audio.persistence_enabled=false
	game.campaign.persistence_enabled=false
	game.expedition.state.pending_node="harbor"
	game.expedition.state.expedition.stage="travel"
	game.expedition.ensure_road()
	for unused in 3: await physics_frame
	freeze(game)
	game.hud.hide()
	game.weather.reduced_effects=quiet
	truck=load("res://scenes/convoy_vehicle.tscn").instantiate()
	truck.game=game
	game.add_child(truck)
	truck.configure_trip(Vector2(1910,430),Vector2(740,3700),{"hp":600,"fuel":12,"ammo":40,"reserve":0,"cargo":{"steel":4}})
	truck.has_mg=true
	truck.facing=facing
	truck.aim_angle=-.10 if facing>0 else -PI+.10
	for index in game.players.size():
		var worker=game.players[index]
		worker.position=truck.position
		worker.visible=true
		check(truck.board(worker,truck.SEAT_ROLES[index]),"Prepared actual crew seat "+truck.SEAT_ROLES[index])
	freeze(truck)

func _road(resolution: Vector2i, facing: float, quiet: bool) -> void:
	await _prepare_road(facing,quiet)
	var presentation=truck.get_node("ConvoyPresentation")
	var invariant: Dictionary={"position":truck.position,"service":truck.service_point(),"gun":truck.gun_origin(),"ammo":truck.ammo,"fuel":truck.fuel,"cargo":truck.cargo.duplicate(true),"children":truck.get_child_count()}
	var label:="road-%s-%s"%["left" if facing<0 else "right","reduced" if quiet else "standard"]
	for sample in [0.0,.13,.27,.40]:
		truck.animation_time=2.17+sample
		truck.wheel_phase=1.25+sample*5
		truck.velocity.x=60*facing
		truck.hp=180.0
		truck.journey_state=Journey.new_state("driving")
		truck.sync_replica()
		presentation._casings.clear()
		var origin: Vector2=truck.gun_origin()+Vector2(8,5).rotated(truck.aim_angle)
		if not quiet: presentation._casings.append(Vector4(origin.x,origin.y,facing,sample))
		presentation.update_state(0)
		truck.flash=maxf(0,.075-sample)
		truck.recoil=2*exp(-sample*18)
		truck.weapon_visual.queue_redraw()
		for worker in game.players:
			worker.get_node("PixelVisual")._process(0)
			worker.get_node("PixelVisual").queue_redraw()
		await capture(label+"-%03d"%roundi(sample*100),resolution,{"zoom":ZOOM,"facing":facing,"reduced":quiet,"age":sample,"speed":truck.velocity.x,"health":truck.hp,"hull_position":[truck.position.x,truck.position.y],"casings":presentation._casings.size(),"wheel_phase":truck.wheel_phase})
		check(truck.position==invariant.position and truck.service_point()==invariant.service and truck.ammo==invariant.ammo and truck.fuel==invariant.fuel and truck.cargo==invariant.cargo and truck.get_child_count()==invariant.children,"Road art preserves authority/crew/cargo/axle "+label)
	truck.velocity=Vector2.ZERO
	truck.journey_state=Journey.new_state("repair")
	truck.journey_state.repair_step="tighten"
	truck.journey_state.repair_work=.60
	truck.journey_state.repair_bolts=2
	truck.journey_state.repair_operator=1
	var mechanic=truck.driver_seat.occupant
	truck.driver_seat.exit()
	mechanic.position=truck.position+Vector2(-114*facing,0)
	mechanic.facing=facing
	mechanic.focus=truck
	mechanic._interacting=true
	for index in [2,3]:
		var worker=truck.seats[index].occupant
		truck.seats[index].exit()
		worker.position=truck.position+Vector2((-180 if index==2 else 180)*facing,0)
		worker.facing=-facing if index==2 else facing
		var weapon=worker.get_node("WorkerWeapon")
		weapon.aiming=true
		weapon.aim_direction=Vector2(worker.facing,0)
		weapon._aim_hold=1.0
		weapon._update_origin()
		weapon.queue_redraw()
	truck.hp=truck.max_hp
	presentation._casings.clear()
	truck.sync_replica()
	presentation.update_state(0)
	presentation.get_node("ServiceDetails").queue_redraw()
	for worker in game.players:
		worker.get_node("PixelVisual")._process(0)
		worker.get_node("PixelVisual").queue_redraw()
	await capture(label+"-repair-defense",resolution,{"zoom":ZOOM,"facing":facing,"reduced":quiet,"repair_step":"tighten","repair_work":.60,"operator":1,"defenders":2,"gunner":2})
	check(not game.network.active and not game.microphone.capturing and AudioServer.is_bus_mute(0),"Native road sample saves no profiles and opens no sockets/microphone")
	check(await Cleanup.free_scene(game,self),"Prepared road releases actual scene/audio handles")
	game=null
	truck=null

func _run() -> void:
	var args:=OS.get_cmdline_user_args()
	if "--no-profile-save" not in args or "--capture" not in args or DisplayServer.get_name()=="headless": quit(2); return
	for argument in args:
		if argument.begins_with("--phase="): phase=argument.trim_prefix("--phase=")
	if phase not in ["baseline","final"]: quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+phase))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	for resolution in [Vector2i(1440,900),Vector2i(1920,1080)]:
		for facing in [-1.0,1.0]:
			for quiet in [false,true]:
				await _guns(resolution,facing,quiet)
				await _road(resolution,facing,quiet)
		for quiet in [false,true]: await _wrecks(resolution,quiet)
	var adapter:=RenderingServer.get_video_adapter_name()
	view.queue_free()
	await process_frame
	var report: Dictionary={"checks":checks,"passed":checks-failures,"failures":failures,"phase":phase,"renderer":adapter,"captures":captures,"transient_differences":transient_differences,"fixture":"Frozen actual four-worker Aschewerk road; exact original enemies and detached wrecks. World zoom1.25 (normal default), both facings, native1440x900/1920x1080, standard/reduced. Velocities, age, flash/shot clocks, repair stage and casing ages explicitly prepared. No authority input or campaign-completion claim."}
	FileAccess.open(OUTPUT+phase+"/gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("PIXEL VEHICLE ENEMIES GALLERY: %d/%d passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
