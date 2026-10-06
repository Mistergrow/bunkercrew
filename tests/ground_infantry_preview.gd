extends SceneTree
## Prepared real sector, native QHD output, then eight seconds of live squad AI.
const OUTPUT="res://artifacts/ground-reinforcements/"
var output:=OUTPUT
var game
var view: SubViewport
var squad: Array=[]
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("INFANTRY VISUAL ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames(count: int):
	for index in count: await process_frame
func capture(label: String):
	await frames(2)
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==Vector2i(2560,1440),label+" native QHD")
	check(picture.save_png(output+label+".png")==OK,label+" saved")
func run():
	if not OS.get_environment("LASTSHIFT_INFANTRY_OUTPUT").is_empty(): output=OS.get_environment("LASTSHIFT_INFANTRY_OUTPUT")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	var screen:=TextureRect.new()
	screen.texture=view.get_texture()
	screen.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	screen.size=Vector2(1440,900)
	root.add_child(screen)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)

	game.start_scenario(1,{"environment":"sector07","position":"left","build_type":"workshop"})
	game.rounds.set_process(false)
	game.story.enabled=false
	game.dialogue.reset()
	game.hud.visible=false
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.players[0].set_physics_process(false)
	game.players[0].position=Vector2(620,430)
	game.turret.set_physics_process(false)
	var wall=preload("res://scenes/wall.tscn").instantiate()
	wall.game=game
	wall.initial_state=4
	wall.position=Vector2(800,430)
	game.add_child(wall)
	wall.max_hp=2000
	wall.hp=2000
	var roster:=EnemyCatalog.wave_roster(6,Balance.WAVE_COUNTS[5],false)
	for index in roster.size():
		if not roster[index] in ["grenadier","rifle_guard"]: continue
		game.spawn_enemy(6,index,roster.size())
		var unit=get_nodes_in_group("human_enemies")[-1]
		unit.set_physics_process(false)
		unit.position=Vector2(1150-unit.squad_slot*80,430)
		unit.target=wall
		unit.worker_attack_clock=0
		unit.moving=true
		unit.gait=1.0+unit.squad_slot*.8
		unit._pose_parts()
		squad.append(unit)
	game.camera.zoom=Vector2.ONE*2.45
	game.camera.position=Vector2(1010,362)
	game.camera.force_update_scroll()
	await capture("squad-advance")
	for unit in squad:
		unit.stance=1.0
		unit.moving=false
		unit.windup=.7
		unit.abilities.prepare_attack(wall.global_position-Vector2(0,40))
		unit._pose_parts()
	await capture("squad-braced")
	game.camera.zoom=Vector2.ONE*4.2
	game.camera.position=Vector2(1085,386)
	game.camera.force_update_scroll()
	await capture("squad-detail")
	for unit in squad:
		unit.attack_count=1
		unit.attack_clock=float(unit.profile.cooldown)-.8
		unit.worker_attack_clock=0
		unit.windup=0
		unit.abilities.aim_locked=false
		unit._pose_parts()
	await capture("squad-reload")
	game.camera.zoom=Vector2.ONE*2.3
	game.camera.position=Vector2(1010,352)
	game.camera.force_update_scroll()
	for unit in squad:
		unit.position=Vector2(1160-unit.squad_slot*30,430)
		unit.stance=0
		unit.attack_count=0
		unit.attack_clock=.4
		unit.worker_attack_clock=0
		unit.windup=0
		unit.set_physics_process(true)
	for frame in 240:
		await process_frame
		if frame==110: await capture("squad-ballistics")
	check(squad[0].attack_count>0 and squad[1].attack_count>=2 and squad[2].attack_count>=2,"Live AI visibly walks, kneels and fires actual grenade/rifle bursts")
	check(wall.hp<2000,"Live projectiles actually hit the prepared cover")
	squad[1].take_damage(10000)
	await frames(12)
	await capture("squad-defeat")
	await frames(30)
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Preview releases the real scene")
	view.queue_free()
	screen.queue_free()
	await process_frame
	print("INFANTRY VISUAL: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
