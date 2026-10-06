extends SceneTree
## Native renderer evidence. Arranged sheets are separate from live combat runs.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const HUMAN_KINDS := ["scout","rifle_guard","grenadier","heavy_gunner","marksman","combat_medic"]
var output := "res://artifacts/army-diversity/after/"
var view: SubViewport
var captures: Array[Dictionary] = []
var checks := 0
var failures := 0
var combat_runs: Array[Dictionary] = []
var film_frame := 0

class Sheet extends Node2D:
	var title := "LUFTKONTAKTE / MATERIALIEN"
	var subtitle := "Sechs echte Gegnerobjekte · vorbereitete Positionen · 2,2× vergrößert"
	var labels: Array[String] = []
	var human := false
	func _draw() -> void:
		draw_rect(Rect2(0,0,1600,900),Color("101a1d"))
		Art.text(self,Vector2(30,43),title,26,Art.LIGHT)
		Art.text(self,Vector2(30,72),subtitle,14,Art.MUTED)
		for index in labels.size():
			var x := 20+(index%3)*530
			var y := 96+floori(index/3.0)*390
			draw_rect(Rect2(x,y,510,371),Color("26322f"))
			Art.text(self,Vector2(x+20,y+32),labels[index],19,Art.LIGHT)
			if human:
				draw_line(Vector2(x+20,y+315),Vector2(x+490,y+315),Color("77806a"),2)
				Art.text(self,Vector2(x+35,y+342),"NATIV",12,Art.MUTED)
				Art.text(self,Vector2(x+300,y+342),"2,5×",12,Art.MUTED)

class CombatCaption extends Node2D:
	var title := ""
	var description := ""
	func _draw() -> void:
		draw_rect(Rect2(16,16,870,65),Color(.055,.08,.09,.94))
		Art.text(self,Vector2(28,40),title,18,Art.LIGHT)
		Art.text(self,Vector2(28,65),description,12,Art.MUTED)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
	print("ARMY VISUAL ","PASS " if value else "FAIL ",label)

func frames(count: int = 6) -> void:
	for unused in count:
		await process_frame

func capture(label: String, fixture: String, settle: bool = true) -> void:
	if settle:
		await frames()
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440) and image.save_png(output+label+".png")==OK,label+" QHD capture")
	captures.append({"file":label+".png","fixture":fixture,"size":[2560,1440]})

func air_sheet() -> void:
	var sheet := Sheet.new()
	for kind in AirEnemyCatalog.CLASS_ORDER:
		sheet.labels.append(str(AirEnemyCatalog.PROFILES[kind].label))
	view.add_child(sheet)
	for index in AirEnemyCatalog.CLASS_ORDER.size():
		var actor = load("res://scenes/air_enemy.tscn").instantiate()
		actor.kind = AirEnemyCatalog.CLASS_ORDER[index]
		actor.wave = int(AirEnemyCatalog.INTRO_WAVES[actor.kind])
		actor.show_status_labels = false
		sheet.add_child(actor)
		actor.set_physics_process(false)
		actor.set_process(false)
		actor.motion.set_process(false)
		actor.motion.automatic = false
		actor.position = Vector2(275+(index%3)*530,295+floori(index/3.0)*390)
		actor.scale = Vector2.ONE*2.2
		actor.age = 2.3+index*.21
		actor.flight_velocity = Vector2(-28,3)
		actor.locked_aim = actor.global_position+Vector2(-300,80)
		actor._pose_parts()
		for part in [actor.body_part,actor.propulsion_part,actor.weapon_part]:
			part.queue_redraw()
		actor.queue_redraw()
	await capture("air-overview","Six actual aircraft, fixed positions/age/flight velocity and 2.2 scale; physics and motion controller frozen; no combat simulated")
	check(await Cleanup.free_scene(sheet,self),"Air sheet cleanup")

func human_sheets() -> void:
	for kind in HUMAN_KINDS:
		check(EnemyCatalog.PROFILES.has(kind) and EnemyCatalog.profile(kind).get("human",false),kind+" is a real human profile")
	if failures:
		return
	var sheet := Sheet.new()
	sheet.human = true
	sheet.title = "BODENTRUPPEN / SECHS ROLLEN"
	for kind in HUMAN_KINDS:
		sheet.labels.append(str(EnemyCatalog.profile(kind).label))
	view.add_child(sheet)
	var actors: Array = []
	for index in HUMAN_KINDS.size():
		for magnification in [1.0,2.5]:
			var actor = load("res://scenes/ground_infantry.tscn").instantiate()
			actor.kind = HUMAN_KINDS[index]
			actor.wave = int(EnemyCatalog.INTRO_WAVES[actor.kind])
			actor.squad_slot = index
			actor.game = sheet
			actor.show_status_labels = false
			actor.position = Vector2(120+(index%3)*530+(250 if magnification>1 else 0),411+floori(index/3.0)*390)
			sheet.add_child(actor)
			actor.scale = Vector2.ONE*magnification
			actor.set_physics_process(false)
			actor.set_process(false)
			actor.infantry.set_process(false)
			var target := Node2D.new()
			target.position = actor.position+Vector2(-150,-10)
			sheet.add_child(target)
			actor.target = target
			actors.append(actor)
	for state in ["march","aim","fire","reload","hit"]:
		sheet.subtitle = {"march":"Vorrücken","aim":"Anlegen","fire":"Schusskontakt","reload":"Nachladen","hit":"Trefferreaktion"}[state]+" · vorbereitete Posen · links Originalgröße, rechts 2,5×"
		sheet.queue_redraw()
		for actor in actors:
			actor.moving = state=="march"
			actor.stance = 0.0 if state=="march" else 1.0
			actor.gait = 1.15
			actor.age = 4.8
			actor.windup = float(actor.profile.windup)*.8 if state=="aim" else 0.0
			actor.muzzle_flash = .11 if state=="fire" else 0.0
			actor.weapon_recoil = 3.0 if state=="fire" else 0.0
			actor.hit_flash = .12 if state=="hit" else 0.0
			var kit := preload("res://scripts/infantry_role_art.gd").spec(actor.kind)
			actor.attack_count = int(kit.magazine) if state=="reload" else 0
			actor.burst_remaining = 0
			actor.attack_clock = float(actor.profile.cooldown)-.12-minf(float(kit.reload_time),float(actor.profile.cooldown)*.72)*.5 if state=="reload" else 0.0
			actor.worker_attack_clock = 0.0
			actor.tracer_end = actor.to_local(actor.target_attack_point())
			actor._pose_parts()
			actor.queue_redraw()
		await capture("human-"+state,"Twelve real infantry scenes: six roles at native scale and 2.5x; explicit "+state+" pose; AI/physics frozen")
	sheet.subtitle = "Zusammenbrechen · echte die()-Lebensdauer · gestellte Ansicht nach 0,3 Sekunden"
	sheet.queue_redraw()
	for actor in actors:
		var magnification: Vector2 = actor.scale
		actor.die()
		var fallen = get_nodes_in_group("infantry_remains")[-1]
		fallen.scale *= magnification
		fallen.set_process(false)
		fallen._process(.3)
	await capture("human-fallen","Real die() creates finite infantry remains; freeze each at 0.3 seconds; gallery scale applied to remains only for matching detail view")
	check(await Cleanup.free_scene(sheet,self),"Human sheets cleanup")

func combat_wave(wave: int) -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"workshop"})
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
	game.players[0].position = Vector2(590,430)
	game.camera.position = Vector2(1110,350)
	game.camera.zoom = Vector2.ONE*1.25
	game.camera.force_update_scroll()
	var wall = load("res://scenes/wall.tscn").instantiate()
	wall.game = game
	wall.initial_state = 4
	wall.position = Vector2(900,430)
	game.add_child(wall)
	wall.hp = 5000
	wall.max_hp = 5000
	var roster := EnemyCatalog.human_fireteam(wave)
	var caption_layer := CanvasLayer.new()
	game.add_child(caption_layer)
	var caption := CombatCaption.new()
	caption.title = "TRUPP WELLE %02d / ECHTE KAMPF-KI"%wave
	caption.description = "Vorbereitete Positionen und Deckung · normale Gegnergröße · originale Wellenzusammenstellung"
	caption_layer.add_child(caption)
	var troops: Array = []
	var medic
	var patient
	for index in roster.size():
		var actor = load("res://scenes/ground_infantry.tscn").instantiate()
		actor.kind = roster[index]
		actor.wave = wave
		actor.squad_slot = index
		actor.game = game
		actor.position = Vector2(900+float(EnemyCatalog.profile(actor.kind).reach)+35,430)
		game.add_child(actor)
		actor.set_physics_process(false)
		actor.attack_clock = .3+index*.1
		actor.worker_attack_clock = 0
		troops.append(actor)
		if actor.kind=="combat_medic":
			medic = actor
		elif actor.kind=="rifle_guard":
			patient = actor
	var patient_before := 0.0
	if is_instance_valid(medic) and is_instance_valid(patient):
		patient.hp -= 30
		patient_before = patient.hp
		# Keep the actual treatment readable instead of hiding the medic behind
		# the wounded actor in the artificially prepared starting formation.
		medic.position.x = patient.position.x-60
		medic.abilities.repair_clock = .2
	await capture("wave-%02d-approach"%wave,"Actual campaign fireteam "+str(roster)+" in prepared sector07/workshop. Starting positions, wall HP5000 and paused wave clock prepared; character dimensions remain native")
	game.camera.zoom = Vector2.ONE*2.1
	game.camera.position = Vector2(1160,360)
	game.camera.force_update_scroll()
	for actor in troops:
		actor.set_physics_process(true)
	var firing_seen := {}
	var healing_seen := false
	var physical_projectiles := false
	var simulation_seconds := 0.0
	var record := "--film" in OS.get_cmdline_user_args()
	if record:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output+"frames"))
	for frame in 300:
		await process_frame
		simulation_seconds += root.get_process_delta_time()
		for actor in troops:
			if actor.muzzle_flash>0:
				firing_seen[actor.kind] = true
		for shot in get_nodes_in_group("ground_ordnance"):
			if shot.game==game:
				physical_projectiles = true
		if is_instance_valid(medic) and not healing_seen and medic.abilities.repair_flash>.35 and medic.abilities.repair_flash<.65:
			healing_seen = true
			await capture("wave-%02d-healing"%wave,"Live medic treatment after ordinary AI update; wounded ally HP and finite medical reserve measured",false)
		if frame in [70,150,290]:
			await capture("wave-%02d-combat-%03d"%[wave,frame],"Live AI and real projectiles; prepared starting positions and wall, frame "+str(frame)+" at capped30FPS",false)
		if record and frame<90:
			await RenderingServer.frame_post_draw
			view.get_texture().get_image().save_jpg(output+"frames/%05d.jpg"%film_frame,.92)
			film_frame += 1
	var attacks := {}
	for actor in troops:
		attacks[actor.kind] = actor.attack_count
		check(actor.attack_count>0,"Wave%d %s fires via actual AI"%[wave,actor.kind])
	check(physical_projectiles and wall.hp<5000,"Wave%d swept projectiles reach prepared cover"%wave)
	var healed := 0.0
	if is_instance_valid(medic):
		healed = patient.hp-patient_before
		check(healing_seen and healed>0 and medic.abilities.repaired_total==healed,"Live medic visibly treats ally and consumes finite reserve")
	combat_runs.append({"wave":wave,"roster":roster,"attacks":attacks,"firing_seen":firing_seen,"projectiles_seen":physical_projectiles,"wall_hp_before":5000,"wall_hp_after":wall.hp,"healed_hp":healed,"healing_seen":healing_seen,"simulation_seconds":simulation_seconds,"prepared":"Native-size real actors, actual campaign team, starting positions, wall5000HP, paused wave clock, wounded rifleman only for wave14. Medic starts60worldpixels ahead of patient for a readable treatment. Actual AI/physics/ordnance run for300 process frames at capped30FPS. No direct fire/heal call in this fixture."})
	check(await Cleanup.free_scene(game,self),"Combat wave%d cleanup"%wave)

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.ends_with("/"):
		output += "/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(320,180)
	Engine.max_fps = 30
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	view = SubViewport.new()
	view.size = Vector2i(2560,1440)
	view.size_2d_override = Vector2i(1600,900)
	view.size_2d_override_stretch = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await air_sheet()
	if "--air-only" not in OS.get_cmdline_user_args():
		await human_sheets()
		if not failures and "--sheets-only" not in OS.get_cmdline_user_args():
			for wave in [8,13,14]:
				await combat_wave(wave)
	view.queue_free()
	await frames()
	var report := FileAccess.open(output+"visual-evidence.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":RenderingServer.get_current_rendering_driver_name(),"logical_resolution":[1600,900],"captures":captures,"combat_runs":combat_runs,"checks":checks,"failures":failures},"\t"))
	print("ARMY VISUAL ",checks-failures,"/",checks," checks")
	quit(1 if failures else 0)
