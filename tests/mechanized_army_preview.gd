extends SceneTree
## Prepared machine sheets and actual combat captured by the native renderer.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const BASE_MACHINES := ["runner","strider","breaker","assault","colossus","siege","shield_guard","lancer","sniper","demolisher","repair_crawler","bastion"]
const NEW_MACHINES := ["scout_car","mortar_carrier"]
var output := "res://artifacts/mechanized-army/after/"
var view: SubViewport
var captures: Array[Dictionary] = []
var checks := 0
var failures := 0
var combat_runs: Array[Dictionary] = []
var film_frame := 0

class Sheet extends Node2D:
	var kinds: Array = []
	var detailed := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("101a1d"))
		Art.text(self,Vector2(24,36),"BODENMASCHINEN / SILHOUETTEN",24,Art.LIGHT)
		Art.text(self,Vector2(24,64),"Echte Gegnerobjekte · gestellte Laufphase · " + ("2,2× / beide Richtungen" if detailed else "Originalgroesse / einheitlicher Massstab"),14,Art.MUTED)
		for i in kinds.size():
			var x := 12+(i%3)*528 if detailed else 12+(i%4)*398
			var y := 87+floori(i/3.0)*400 if detailed else 87+floori(i/4.0)*200
			var w := 512 if detailed else 382
			var h := 386 if detailed else 188
			draw_rect(Rect2(x,y,w,h),Color("25312e"))
			Art.text(self,Vector2(x+12,y+26),str(EnemyCatalog.profile(kinds[i]).label),16,Art.LIGHT)
			draw_line(Vector2(x+16,y+h-28),Vector2(x+w-16,y+h-28),Color("78816b"),1)

class VehicleSheet extends Node2D:
	var stage := "Fahren"
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("101a1d"))
		Art.text(self,Vector2(24,38),"FAHRZEUGE / "+stage.to_upper(),26,Art.LIGHT)
		Art.text(self,Vector2(24,66),"Echte Rigs · vorbereitete Aktionsphasen · 2,6× · links/rechts",14,Art.MUTED)
		for i in 4:
			var x := 14+(i%2)*795
			var y := 88+floori(i/2.0)*395
			draw_rect(Rect2(x,y,777,379),Color("25312e"))
			Art.text(self,Vector2(x+16,y+30),"SPAEHWAGEN" if i%2==0 else "MOERSERTRAEGER",19,Art.LIGHT)
			draw_line(Vector2(x+24,y+342),Vector2(x+753,y+342),Color("78816b"),1)

class Caption extends Node2D:
	var title := ""
	var description := "Vorbereitete Positionen/Deckung · laufende KI · echte Geschosse · originale Figurengroesse"
	func _draw() -> void:
		draw_rect(Rect2(16,16,965,62),Color(.055,.08,.09,.94))
		Art.text(self,Vector2(28,40),title,18,Art.LIGHT)
		Art.text(self,Vector2(28,65),description,12,Art.MUTED)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("MECHANIZED VISUAL ","PASS " if ok else "FAIL ",label)

func frames(count: int=5) -> void:
	for unused in count:
		await process_frame

func capture(label: String,fixture: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var img := view.get_texture().get_image()
	check(img.get_size()==Vector2i(2560,1440) and img.save_png(output+label+".png")==OK,label+" QHD capture")
	captures.append({"file":label+".png","fixture":fixture,"size":[2560,1440]})

func prepared_actor(kind: String,parent: Node2D,where: Vector2,magnification: float,direction: float) -> Node2D:
	var actor = load("res://scenes/enemy.tscn").instantiate()
	actor.kind = kind
	actor.wave = EnemyCatalog.INTRO_WAVES[kind]
	actor.show_status_labels = false
	actor.attack_direction = direction
	actor.position = where
	parent.add_child(actor)
	actor.scale = Vector2.ONE*magnification
	actor.set_physics_process(false)
	actor.set_process(false)
	actor.motion.set_process(false)
	actor.motion.automatic = false
	actor.gait = 1.4
	actor.age = 3.2
	actor.moving = true
	actor.locomotion_speed = actor.move_speed
	actor._pose_parts()
	for part in [actor.body_part,actor.legs_part,actor.weapon_part]:
		part.queue_redraw()
	actor.queue_redraw()
	return actor

func sheets() -> void:
	var sheet := Sheet.new()
	sheet.kinds = BASE_MACHINES.duplicate()
	if "--baseline" not in OS.get_cmdline_user_args():
		for kind in NEW_MACHINES:
			check(EnemyCatalog.PROFILES.has(kind),kind+" exists")
			if EnemyCatalog.PROFILES.has(kind): sheet.kinds.append(kind)
	view.add_child(sheet)
	for i in sheet.kinds.size():
		prepared_actor(sheet.kinds[i],sheet,Vector2(203+(i%4)*398,247+floori(i/4.0)*200),1.0,-1)
	await capture("machine-overview","Real machine scenes at native scale; fixed age3.2/gait1.4/moving; AI and motion controller frozen. Baseline12 and after14 share the first12 positions.")
	check(await Cleanup.free_scene(sheet,self),"Overview cleanup")
	var details := Sheet.new()
	details.detailed = true
	details.kinds = ["shield_guard","repair_crawler","bastion","shield_guard","repair_crawler","bastion"]
	view.add_child(details)
	for i in details.kinds.size():
		prepared_actor(details.kinds[i],details,Vector2(260+(i%3)*528,445+floori(i/3.0)*400),2.2,-1 if i<3 else 1)
	await capture("specialists-detail","Actual shield_guard/repair_crawler/bastion in two facing directions at2.2 scale; fixed age3.2/gait1.4/moving; AI and motion frozen")
	check(await Cleanup.free_scene(details,self),"Specialist cleanup")

func vehicle_sheets() -> void:
	var sheet := VehicleSheet.new()
	view.add_child(sheet)
	var actors: Array = []
	for i in 4:
		var actor = prepared_actor(NEW_MACHINES[i%2],sheet,Vector2(398+(i%2)*795,430+floori(i/2.0)*395),2.6,-1 if i<2 else 1)
		var target := Node2D.new()
		target.position = actor.position+Vector2(actor.attack_direction*420,-15)
		sheet.add_child(target)
		actor.target = target
		actors.append(actor)
	for stage in ["movement","aim","fire","service","hit"]:
		sheet.stage = {"movement":"Fahren","aim":"Abstuetzen / Zielen","fire":"Feuern","service":"Nachladen","hit":"Treffer"}[stage]
		sheet.queue_redraw()
		for actor in actors:
			actor.moving = stage=="movement"
			actor.locomotion_speed = actor.move_speed if actor.moving else 0.0
			actor.windup = float(actor.profile.windup)*.8 if stage=="aim" else 0.0
			actor.muzzle_flash = .11 if stage=="fire" else 0.0
			actor.weapon_recoil = 4.0 if stage=="fire" else 0.0
			actor.hit_flash = .13 if stage=="hit" else 0.0
			actor.motion.state = ""
			actor.motion.advance(2)
			if stage=="service":
				actor.motion.play("service",true)
				actor.motion.advance(.48)
			actor.abilities.aim_point = actor.target.global_position-Vector2(0,20)
			actor.abilities.aim_locked = stage=="aim"
			actor.abilities.warning_point = actor.abilities.aim_point
			actor.tracer_end = actor.to_local(actor.target.global_position)
			actor._pose_parts()
			for child in actor.get_children():
				if child is CanvasItem: child.queue_redraw()
			actor.queue_redraw()
		await capture("vehicles-"+stage,"Four actual vehicle scenes, both facings,2.6x; explicit "+stage+" phase; AI frozen; actual shared rigs and presentation controller")
	for actor in actors:
		actor.die()
	for wreck in get_nodes_in_group("enemy_motion_wrecks"):
		wreck.set_process(false)
		wreck._process(.3)
		check(wreck.artist.body_part.global_transform.y.y>0 and wreck.artist.body_part.global_transform.x.x*wreck.mirror>0,wreck.identity+" wreck preserves facing and upright hull")
	sheet.stage = "ZERSTOERT / 0,3 SEKUNDEN"
	sheet.queue_redraw()
	await capture("vehicles-wreck","Normal die() generates actual finite wrecks; frozen at0.3seconds; real presentation delegate and2.6x actor transform")
	check(await Cleanup.free_scene(sheet,self),"Vehicle sheets cleanup")

func prepare_game(mode: String,wave: int) -> Node2D:
	var game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"sector07","position":mode,"build_type":"workshop"})
	game.rounds.set_process(false)
	game.rounds.wave = wave
	game.story.enabled = false
	game.dialogue.reset()
	game.dialogue.set_process(false)
	game.notice_time = 0
	game.hud.visible = false
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.turret.set_physics_process(false)
	game.players[0].set_physics_process(false)
	game.players[0].position = Vector2(game.scenario_combat.core_x,430)
	return game

func add_caption(game: Node,title: String,description: String="") -> void:
	var layer := CanvasLayer.new()
	game.add_child(layer)
	var caption := Caption.new()
	caption.title = title
	if not description.is_empty(): caption.description = description
	layer.add_child(caption)

func add_wall(game: Node,x: float) -> Node2D:
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.initial_state = 4
	wall.position = Vector2(x,430)
	game.add_child(wall)
	wall.hp = 5000
	wall.max_hp = 5000
	return wall

func combat_vehicle(kind: String,direction: float) -> void:
	var suffix := "left" if direction<0 else "right"
	var label := kind+"-"+suffix
	var game = prepare_game("left" if direction<0 else "right",int(EnemyCatalog.INTRO_WAVES[kind]))
	var wall_x: float = game.scenario_combat.bunker_right+170 if direction<0 else game.scenario_combat.bunker_left-170
	var wall = add_wall(game,wall_x)
	var actor = load("res://scenes/enemy.tscn").instantiate()
	actor.kind = kind
	actor.wave = int(EnemyCatalog.INTRO_WAVES[kind])
	actor.attack_direction = direction
	actor.game = game
	actor.position = Vector2(wall_x-direction*(float(EnemyCatalog.profile(kind).reach)+75),430)
	game.add_child(actor)
	actor.set_physics_process(false)
	actor.attack_clock = .2
	var start_x: float = actor.position.x
	game.camera.position = Vector2((actor.position.x+wall_x)*.5,325)
	game.camera.zoom = Vector2.ONE*1.75
	game.camera.force_update_scroll()
	add_caption(game,str(actor.profile.label)+" / ANGRIFF NACH "+("LINKS" if direction<0 else "RECHTS"))
	await capture(label+"-approach","Real "+kind+" at native size; prepared start75px outside reach and concrete wall5000HP; camera1.75; AI initially frozen")
	actor.set_physics_process(true)
	var moving_seen := false
	var charge_seen := false
	var fire_seen := false
	var projectile_seen := false
	var ascending := false
	var descending := false
	var damage_seen := false
	var seconds := 0.0
	var projectiles: Dictionary = {}
	var filming := "--film" in OS.get_cmdline_user_args()
	if filming: DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+"frames"))
	for frame in 330:
		await process_frame
		seconds += root.get_process_delta_time()
		moving_seen = moving_seen or actor.moving
		fire_seen = fire_seen or actor.muzzle_flash>0
		if not charge_seen and actor.windup>float(actor.profile.windup)*.45:
			charge_seen = true
			await capture(label+"-aim","Actual AI windup, warning and support pose during normal update; no direct attack call")
		for shot in get_nodes_in_group("ground_ordnance"):
			if shot.game!=game: continue
			projectile_seen = true
			projectiles[shot.get_instance_id()] = true
			ascending = ascending or shot.velocity.y < -8
			descending = descending or shot.velocity.y > 8
		if projectile_seen and frame==95:
			await capture(label+"-combat","Real runtime AI and physical projectiles after95 observed processframes")
		if not damage_seen and wall.hp<5000:
			damage_seen = true
			await capture(label+"-impact","First actual projectile impact reduces prepared cover HP; ordinary swept collision")
		if filming and frame<150:
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_jpg(output+"frames/%05d.jpg"%film_frame,.92)
			film_frame += 1
	check(moving_seen and absf(actor.position.x-start_x)>50,label+" real movement")
	check(charge_seen and fire_seen and actor.attack_count>0,label+" actual windup and firing")
	check(projectile_seen and damage_seen,label+" physical ordnance hits cover")
	if kind=="mortar_carrier": check(ascending and descending,label+" ballistic ascent and descent")
	combat_runs.append({"kind":kind,"facing":direction,"attacks":actor.attack_count,"moved_pixels":absf(actor.position.x-start_x),"windup_seen":charge_seen,"muzzle_seen":fire_seen,"projectiles_seen":projectiles.size(),"ascending":ascending,"descending":descending,"wall_hp_before":5000,"wall_hp_after":wall.hp,"simulation_seconds":seconds,"fixture":"Native actor,75px outside reach,concretewall5000HP,paused wave/player/roofgun/SAN; actual AI/physics/projectiles330 observed frames; no direct fire call"})
	await capture(label+"-end","End of330 observed live AI processframes; original actor dimensions; prepared cover persists")
	check(await Cleanup.free_scene(game,self),label+" combat cleanup")

func mixed_wave() -> void:
	var game = prepare_game("left",14)
	var count := 10
	var roster := EnemyCatalog.wave_roster(14,count,false)
	var troops: Array = []
	for i in count:
		game.spawn_enemy(14,i,count)
		var actor = get_nodes_in_group("enemies")[-1]
		actor.set_physics_process(false)
		actor.position = Vector2(850+i*86,430)
		troops.append(actor)
	game.camera.position = Vector2(1240,335)
	game.camera.zoom = Vector2.ONE*1.25
	game.camera.force_update_scroll()
	add_caption(game,"GEMISCHTE WELLE 14 / ORIGINALER KATALOG / NORMALZOOM 1,25","Echte Gegnerfabrik · vorbereitete Abstaende · angehaltene Bewegung · Originalgroesse")
	await capture("mixed-wave-normal","Actual game.spawn_enemy(14,index,10) factory and roster; arranged86px separation; native scale, camera1.25; frozen for readable mixedarmy composition")
	var humans := 0
	var machines := 0
	var vehicles := 0
	for actor in troops:
		humans += int(EnemyCatalog.is_human(actor.kind))
		machines += int(not EnemyCatalog.is_human(actor.kind))
		vehicles += int(actor.kind in NEW_MACHINES)
	check(humans==3 and machines>=2 and vehicles>0,"Mixed wave factory contains human fireteam and vehicles")
	combat_runs.append({"fixture":"Actual campaign wave14 roster through production enemy factory; only positions/physics prepared for composition; no combat simulated","roster":roster,"human_count":humans,"machine_count":machines,"vehicle_count":vehicles})
	check(await Cleanup.free_scene(game,self),"Mixed wave cleanup")

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	if not output.ends_with("/"): output += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(320,180)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	Engine.max_fps = 30
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	view = SubViewport.new()
	view.size = Vector2i(2560,1440)
	view.size_2d_override = Vector2i(1600,900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	if "--combat-only" not in OS.get_cmdline_user_args(): await sheets()
	if "--baseline" not in OS.get_cmdline_user_args() and not failures:
		if "--combat-only" not in OS.get_cmdline_user_args(): await vehicle_sheets()
		if "--sheets-only" not in OS.get_cmdline_user_args():
			for kind in NEW_MACHINES:
				for direction in [-1.0,1.0]:
					await combat_vehicle(kind,direction)
			await mixed_wave()
	view.queue_free()
	await frames()
	var file := FileAccess.open(output+"visual-evidence.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"captures":captures,"combat_runs":combat_runs,"checks":checks,"failures":failures},"\t"))
	print("MECHANIZED VISUAL ",checks-failures,"/",checks," checks")
	quit(1 if failures else 0)
