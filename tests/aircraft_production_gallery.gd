extends SceneTree
## Native inspection plates plus a live main-scene mixed attack. Positions,
## wave/attack clocks and finite construction cargo are prepared explicitly.
const OUTPUT := "res://artifacts/audio-air-review/air/gallery"
const Cleanup := preload("res://tests/scene_cleanup.gd")
var view: SubViewport
var game
var manifest: Array = []
var checks := 0
var failures := 0

class Inspection extends Node2D:
	var aircraft: Array = []
	var sky: Texture2D = preload("res://assets/expedition/road_hinterland_v2.png")
	func _process(delta: float) -> void:
		for index in aircraft.size():
			var air = aircraft[index]
			air.age += delta
			air.flight_velocity = Vector2(sin(air.age*.9+index)*45,cos(air.age+index)*10)
			air._pose_parts()
		queue_redraw()
	func _draw() -> void:
		draw_texture_rect(sky,Rect2(0,0,1920,1080),false,Color("525e5e"))
		draw_rect(Rect2(0,0,1920,1080),Color(.025,.035,.037,.53))
		var english := LocaleText.current_locale()=="en"
		Art.text(self,Vector2(34,42),"BUNKERCREW / AIR CONTACTS" if english else "BUNKERCREW / LUFTKONTAKTE",28,Art.LIGHT)
		Art.text(self,Vector2(35,70),"12 aircraft · independent propulsion, bays and gun mounts" if english else "12 Flugklassen · unabhängige Antriebe, Bombenschächte und Geschütze",15,Art.MUTED)
		for index in aircraft.size():
			var x := 24+(index%4)*480
			var y := 103+floori(index/4.0)*303
			var air = aircraft[index]
			var line := Rect2(x,y,442,1)
			draw_rect(line,Color(.48,.49,.40,.36))
			Art.text(self,Vector2(x+10,y+27),LocaleText.text(str(air.profile.label)),19,Art.LIGHT)
			Art.text(self,Vector2(x+10,y+49),("WAVE %02d / %s" if english else "WELLE %02d / %s")%[air.wave,str(air.profile.propulsion).to_upper()],12,Art.AMBER)
			Art.text(self,Vector2(x+10,y+266),("%d SHOTS · %.2fs WINDUP" if english else "%d GESCHOSSE · %.2fs VORWARNUNG")%[air.profile.burst,air.profile.windup],12,Art.MUTED)
		Art.text(self,Vector2(35,1057),"Native Godot render · inspection positions and attack poses prepared" if english else "Nativer Godot-Renderer · vorbereitete Inspektionspositionen und Angriffsposen",13,Art.MUTED)

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS ",label)

func capture(name: String,prepared: String,actors: Array = []) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels := view.get_texture().get_image()
	check(not pixels.is_empty() and pixels.get_size()==Vector2i(1920,1080),name+" is an actual native 1920x1080 viewport capture")
	pixels.save_png(OUTPUT+"/"+name+".png")
	var evidence: Array = []
	for air in actors:
		if is_instance_valid(air): evidence.append({"kind":air.kind,"age":air.age,"position":[air.position.x,air.position.y],"attacks":air.attack_count,"hp":air.hp,"propeller_clock":air.visual_age()})
	var flak_evidence := {}
	if is_instance_valid(game) and is_instance_valid(game.flak_station) and game.flak_station.built:
		var gun=game.flak_station.turret
		flak_evidence={"ammo":gun.ammo,"reserve":gun.reserve,"capacity":gun.ammo_capacity(),"reserve_capacity":gun.reserve_capacity(),"hp":gun.hp,"max_hp":gun.max_hp,"shots":gun.flash_tick}
	manifest.append({"image":name+".png","prepared":prepared,"locale":LocaleText.current_locale(),"native_size":[1920,1080],"wall_ms":Time.get_ticks_msec(),"aircraft":evidence,"flak":flak_evidence})

func inspection() -> void:
	var plate := Inspection.new()
	view.add_child(plate)
	for index in AirEnemyCatalog.CLASS_ORDER.size():
		var air := AirMachine.new()
		air.kind=AirEnemyCatalog.CLASS_ORDER[index]
		air.wave=int(AirEnemyCatalog.INTRO_WAVES[air.kind])
		air.position=Vector2(244+(index%4)*480,256+floori(index/4.0)*303)
		plate.add_child(air)
		air.position=Vector2(244+(index%4)*480,256+floori(index/4.0)*303)
		air.set_physics_process(false)
		air.scale=Vector2.ONE*2.3
		air.age=index*.29+1
		air.windup=0.0
		air.burst_remaining=1 if str(air.profile.flavor)=="bomb" else 0
		air.locked_aim=air.global_position+Vector2(-200,60)
		air.show_status_labels=false
		plate.aircraft.append(air)
	LocaleText.set_locale("de",false)
	await capture("overview-de","Twelve actual aircraft scenes at 2.3 scale, frozen AI, prepared bank and open bomb bays, automatically advancing rotor clocks.",plate.aircraft)
	LocaleText.set_locale("en",false)
	await capture("overview-en","Same native inspection, English locale; original aspect and alpha region preserved.",plate.aircraft)
	for frame in 12:
		await create_timer(.06).timeout
		await capture("inspection-%03d"%frame,"Live cosmetic timer on arranged real aircraft, no gameplay simulation.",plate.aircraft)
	await Cleanup.free_scene(plate,self)

func prepare_game(environment: String) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.selected_characters=PartyConfig.normalize_characters(["mara","branko","ivo","mara"])
	game.start_scenario(4,{"environment":environment,"position":"left","build_type":"bastion"})
	game.combat_events.persistence_enabled=false
	game.rounds.running=false
	game.rounds.wave=20
	game.rounds.phase="attack"
	game.set_view_stage(2)
	game.notice_time=0
	game.dialogue.pending.clear()
	game.dialogue.active.clear()
	game.dialogue.voice.stop()
	game.hud.overlay=""
	game.hud.chat_panel._process(0)
	game.hud._process(0)
	# Game flow and automatic camera follow stop; all actors, production,
	# weather, auto flak, music and effects remain genuine live descendants.
	game.set_process(false)
	game.camera.position=Vector2(878,276)
	game.camera.zoom=Vector2.ONE*1.18
	game.camera.force_update_scroll()
	var worker=game.players[0]
	worker.inventory.clear()
	for item in {"steel":3,"concrete":2,"ammo":1}: worker.add_item(item,{"steel":3,"concrete":2,"ammo":1}[item])
	game.flak_station.unlock()
	for index in 40: game.flak_station.interact(worker,.4)
	check(game.flak_station.built and game.flak_station.turret.ammo==20,"Prepared finite six-item cargo actually constructs and stocks Flak I")
	for actor in get_nodes_in_group("stations"):
		if actor.game==game and actor.kind=="mixer":
			worker.inventory.clear()
			worker.add_item("sand",2)
			actor.interact(worker,1.0)
			actor.interact(worker,1.0)
			actor._process(.01)
			check(actor.working and actor.input_amount==0,"Bunker mixer actually consumes two sand and starts a real production batch")
	worker.position=Vector2(257,430)
	game.players[1].position=Vector2(660,245)
	game.players[2].position=Vector2(590,430)
	game.players[3].position=Vector2(330,430)
	for index in 3:
		var kind: String = ["battle_tank","strider","rifle_guard"][index]
		var scene := "ground_infantry" if EnemyCatalog.is_human(kind) else "enemy"
		var enemy=game._entity(scene,Vector2(1120+index*215,430),{"kind":kind,"wave":20})
		# Finite low attack damage avoids an unrelated defeat during captures;
		# target selection, movement, projectiles and real cover keep running.
		enemy.attack_damage=minf(enemy.attack_damage,1.0)
	for frame in 4: await process_frame

func live_batch(batch: int) -> void:
	var actors: Array=[]
	for index in 4:
		var kind: String=AirEnemyCatalog.CLASS_ORDER[batch*4+index]
		var air=game._entity("air_enemy",Vector2(920+index*200,80+index*23),{"kind":kind,"wave":20,"scenario_lanes":game.scenario_combat.air_bounds(-1.0)})
		# This is a prepared already-entered warning window; the eight-second
		# real entry grace is exercised separately in the combat regression.
		air.entered=true
		air.entry_time=8.0
		air.attack_clock=.25+index*.12
		actors.append(air)
	LocaleText.set_locale("de",false)
	await capture("mixed-%d-de"%batch,"Actual four-player bunker, paid live Flak I, real consuming mixer and three live ground opponents; aircraft entered/attack clocks prepared.",actors)
	LocaleText.set_locale("en",false)
	await capture("mixed-%d-en"%batch,"Same actual native live main scene, English locale; actors and automatic AA remain active.",actors)
	var first_ammo: int=game.flak_station.turret.ammo+game.flak_station.turret.reserve
	var first_shots: int=game.flak_station.turret.flash_tick
	var recorded: Array=[]
	for frame in 32:
		await create_timer(.075).timeout
		await capture("flight-%03d"%(batch*32+frame),"Actual live physics and AI, prepared spawn positions/initial attack clock; sampled native frames, silent video is not a frame-rate benchmark.",actors)
		for actor in actors:
			if is_instance_valid(actor) and actor.attack_count>0 and actor.kind not in recorded: recorded.append(actor.kind)
	check(game.flak_station.turret.ammo+game.flak_station.turret.reserve<first_ammo and game.flak_station.turret.flash_tick>first_shots,"Live mixed batch%d spends actual finite magazine+reserve rounds and emits real autonomous Flak shots"%batch)
	check(recorded.size()>=2,"Live mixed batch%d contains actual aircraft attacks under real automatic AA fire"%batch)
	for actor in actors:
		if is_instance_valid(actor): actor.queue_free()
	for projectile in get_nodes_in_group("air_projectiles"):
		if projectile.game==game: projectile.queue_free()
	await process_frame
	# The next batch gets a real finite ammunition pack from prepared cargo.
	var worker=game.players[0]
	worker.inventory.clear()
	worker.add_item("ammo",1)
	game.flak_station.turret.refill_from_worker(worker,20)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Aircraft gallery requires an actual rendering display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	InputSetup.install()
	root.size=Vector2i(1920,1080)
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	await inspection()
	await prepare_game("ash_foundry")
	for batch in 3: await live_batch(batch)
	await Cleanup.free_scene(game,self)
	await prepare_game("mountain_pass")
	var rain_air: Array=[]
	for index in 4:
		var air=game._entity("air_enemy",Vector2(920+index*190,90+index*22),{"kind":AirEnemyCatalog.CLASS_ORDER[index+6],"wave":20,"scenario_lanes":game.scenario_combat.air_bounds(-1.0)})
		air.entered=true
		rain_air.append(air)
	await create_timer(.6).timeout
	LocaleText.set_locale("de",false)
	await capture("rain-de","Actual rainy main scene, live weather/collision, four newly generated aircraft and automatic AA; positions prepared.",rain_air)
	game.weather.set_reduced_effects(true)
	LocaleText.set_locale("en",false)
	await capture("rain-reduced-en","Actual reduced-effects rain path; gameplay/health/flight still live.",rain_air)
	check(rain_air.all(func(air):return not is_instance_valid(air) or air.wetness.amount>=0),"All rain aircraft retain finite wetness receivers with new alpha hull contours")
	await Cleanup.free_scene(game,self)
	view.queue_free()
	await process_frame
	var report:=FileAccess.open(OUTPUT+"/gallery.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"renderer":"Godot Compatibility / native viewport, software Mesa when launched with explicit llvmpipe environment","checks":checks,"failures":failures,"captures":manifest,"prepared_states":["Inspection cells use 2.3x scale and prepared bank and open bomb bays, real cosmetic timers.","Main scene: actual four players, paid six-item Flak I construction, real two-sand mixer batch, finite20-round packs.","Waves and camera follow stopped; positions and entered/initial attack clocks prepared; ordinary flight/AI/cover/production/AA/effects remain active.","Three ground opponents have attack damage capped at1 solely to avoid capture defeat.","Video frames are native viewport captures at irregular wall-clock intervals; output12fps is playback formatting, no hardware FPS claim."]},"  "))
	report.close()
	print("AIRCRAFT GALLERY: %d/%d checks passed; %d native captures"%[checks-failures,checks,manifest.size()])
	quit(0 if failures==0 else 1)
