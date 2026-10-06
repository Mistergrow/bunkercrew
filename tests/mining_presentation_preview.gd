extends SceneTree
## Staged pose sheets are labelled separately from real held-E scenario runs.
## Run with --fixed-fps 30; the six-second film preserves that simulation rate.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo"]
const OUTPUT := "res://artifacts/style-layout/mining"
var failures := 0
var checks := 0
var evidence: Array[Dictionary] = []
var contact_errors: Array[float] = []
var frame_number := 0

class PoseWorld extends Node2D:
	var started := true
	var players: Array = []
	func sound(_kind): pass
	func impact(at: Vector2,kind: String,normal: Vector2,power: float):
		var burst := ImpactBurst.new()
		burst.position=at
		burst.surface_material=kind
		burst.direction=normal
		burst.power=power
		burst.seed_value=1477
		add_child(burst)
	func _draw():
		draw_rect(Rect2(0,0,300,150),Color("222c29"))
		draw_rect(Rect2(0,104,300,46),Color("3b4034"))
		draw_line(Vector2(0,104),Vector2(300,104),Color("7c8069"),2)

class Sheet extends Node2D:
	var phase := ""
	func _draw():
		draw_rect(Rect2(0,0,1920,1440),Color("111b1e"))
		Art.text(self,Vector2(25,35),"ABBAU · "+phase,25,Art.LIGHT)
		Art.text(self,Vector2(25,59),"Vorbereitete echte Figuren und Erzblöcke · 2× Pixelansicht · keine simulierte Spielprogression",15,Art.MUTED)
		for row in 4:
			for col in 3:
				var at := Vector2(20+col*635,91+row*331)
				var title: String = str(IDS[col]).to_upper()+" · "+(["RECHTS / STEHEND","LINKS / STEHEND","RECHTS / TIEFER KONTAKT","LINKS / TIEFER KONTAKT"][row])
				Art.text(self,at,title,16,Color(CharacterCatalog.data(IDS[col]).accent))

class Caption extends CanvasLayer:
	var text_node: Label
	func set_caption(value: String):
		if text_node==null:
			text_node=Label.new()
			text_node.position=Vector2(24,20)
			text_node.add_theme_font_override("font",load("res://assets/mono.ttf"))
			text_node.add_theme_font_size_override("font_size",18)
			text_node.add_theme_color_override("font_color",Color("efe7cc"))
			text_node.add_theme_color_override("font_shadow_color",Color("10191a"))
			text_node.add_theme_constant_override("shadow_offset_x",2)
			text_node.add_theme_constant_override("shadow_offset_y",2)
			add_child(text_node)
		text_node.text=value

func _initialize(): run.call_deferred()
func check(ok: bool,label: String):
	checks+=1
	print("MINING PREVIEW ","PASS " if ok else "FAIL ",label)
	if not ok:
		failures+=1
		push_error(label)
func frames(count: int=3):
	for unused in count: await process_frame
func save_view(view: Viewport,path: String):
	await RenderingServer.frame_post_draw
	var result := view.get_texture().get_image().save_png(path)
	if result!=OK:
		failures+=1
		push_error("Could not save "+path)
func tip_error(worker: Worker,visual: WorkerVisual) -> float:
	if visual.mining_pose.is_empty(): return INF
	var pose: Dictionary=visual.mining_pose
	var tip := worker.to_global(Vector2(pose.tool_tip)*Vector2(float(pose.facing),1))
	return tip.distance_to(Vector2(pose.contact_world))

func pose_sheets():
	var sheet_view := SubViewport.new()
	sheet_view.size=Vector2i(1920,1440)
	sheet_view.world_2d=World2D.new()
	sheet_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(sheet_view)
	var sheet := Sheet.new()
	sheet_view.add_child(sheet)
	var samples: Array[Dictionary]=[]
	for row in 4:
		for col in 3:
			var view := SubViewport.new()
			view.size=Vector2i(300,150)
			view.world_2d=World2D.new()
			view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
			sheet.add_child(view)
			var world := PoseWorld.new()
			view.add_child(world)
			var reversed := row%2==1
			var low := row>=2
			var actor: Worker=load("res://scenes/player.tscn").instantiate()
			actor.game=world
			actor.character_id=IDS[col]
			actor.position=Vector2(168 if reversed else 132,104)
			actor.facing=-1 if reversed else 1
			world.add_child(actor)
			world.players.append(actor)
			actor.set_physics_process(false)
			var block: MineBlock=load("res://scenes/mine_block.tscn").instantiate()
			block.game=world
			block.kind="ore"
			block.position=Vector2(104 if reversed else 196,125 if low else 80)
			world.add_child(block)
			block.mining=block.mining_duration()*.35
			actor.focus=block
			actor.mining=true
			var visual: WorkerVisual=actor.get_node("PixelVisual")
			visual.set_process(false)
			visual.set_physics_process(false)
			visual.crouched=low
			visual.idle_clock.wait_remaining=100
			visual._process(0)
			visual._identity.hide()
			var display := TextureRect.new()
			display.texture=view.get_texture()
			display.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			display.position=Vector2(20+col*635,102+row*331)
			display.size=Vector2(600,300)
			sheet.add_child(display)
			samples.append({"actor":actor,"block":block,"visual":visual,"world":world,"row":row})
	await frames(4)
	for pose_frame in [1,3,5]:
		sheet.phase={1:"AUSHOLEN",3:"KONTAKT",5:"RÜCKFÜHRUNG"}[pose_frame]
		sheet.queue_redraw()
		for sample in samples:
			var visual: WorkerVisual=sample.visual
			visual._step=float(pose_frame)
			visual._process(0)
			visual._identity.hide()
			sample.block.contact_point=sample.block._contact_from(sample.actor.position+Vector2(0,-22))
			sample.block.queue_redraw()
			if pose_frame==3:
				var error := tip_error(sample.actor,visual)
				contact_errors.append(error)
				check(error<.01,"%s row %d pick tip meets the exposed face"%[sample.actor.character_id,int(sample.row)+1])
				sample.block.mining_strike(sample.actor)
		await frames(2)
		await save_view(sheet_view,OUTPUT+"/pose-%s.png"%{1:"before",3:"contact",5:"after"}[pose_frame])
	check(await Cleanup.free_scene(sheet,self),"Pose sheet resources released")
	sheet_view.queue_free()
	await frames()

func real_run(identity: String,from_right: bool):
	var view := SubViewport.new()
	view.size=Vector2i(1600,900)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var game=load("res://scenes/main.tscn").instantiate()
	var selected: Array[String]=[identity,"ivo"]
	game.selected_characters=selected
	view.add_child(game)
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"center"})
	game.rounds.set_process(false)
	game.rounds.phase="build"
	game.set_process(false)
	game.medic.set_physics_process(false)
	game.hud.hide()
	game.notice_time=0
	game.dialogue.reset()
	var field: DiggableTerrain=game.scenario_bunker.fields[0]
	var target: MineBlock=field.cell_at(Vector2i(3 if from_right else 0,2))
	var worker: Worker=game.players[0]
	worker.inventory.clear()
	worker.position=Vector2(field.bounds.end.x+23 if from_right else field.bounds.position.x-30,field.bounds.end.y)
	worker.velocity=Vector2.ZERO
	worker.facing=-1 if from_right else 1
	worker.preferred_focus=target
	var original_position := worker.position
	var original_count := field.remaining_count()
	var expected_yield := target.yield_amount
	var resource := target.kind
	var target_location := target.position
	game.player_camera.mode="overview"
	game.player_camera.view_zoom=3.0
	game.camera_target_center=worker.position+Vector2(-18 if from_right else 18,-37)
	game.camera_target_zoom=1.0
	game.player_camera.update_view(0,true)
	var caption := Caption.new()
	view.add_child(caption)
	var label := identity+"-"+("left" if from_right else "right")
	caption.set_caption("%s · %s\nEchte E-Eingabe · Ausgangsposition und Nahkamera vorbereitet"%[identity.to_upper(),"Abbau nach links" if from_right else "Abbau nach rechts"])
	await frames(6)
	var visual: WorkerVisual=worker.get_node("PixelVisual")
	var mined_frame := -1
	var captured_contact := false
	var captured_follow := false
	var progress_seen := false
	var actual_frames := 90
	for index in actual_frames:
		var stills: Array[String]=[]
		if index==10: Input.action_press("p1_interact")
		await process_frame
		if is_instance_valid(target): progress_seen=progress_seen or target.mining>0
		if worker.inventory.get(resource,0)>=expected_yield and mined_frame<0:
			mined_frame=index
			Input.action_release("p1_interact")
			caption.set_caption("%s · %d %s gewonnen\nDurchgehend gehaltenes E bis Ertrag · echte Physik und echter Zellabbau"%[identity.to_upper(),worker.inventory.get(resource,0),LocaleText.text(Balance.RESOURCE_NAMES[resource])])
		if visual.pose_frame==3 and worker.mining and not visual.mining_pose.is_empty():
			contact_errors.append(tip_error(worker,visual))
			if not captured_contact:
				stills.append(OUTPUT+"/"+label+"-contact.png")
				captured_contact=true
		if visual.pose_frame==5 and worker.mining and not captured_follow:
			stills.append(OUTPUT+"/"+label+"-follow-through.png")
			captured_follow=true
		if index==7: stills.append(OUTPUT+"/"+label+"-before.png")
		if index==89: stills.append(OUTPUT+"/"+label+"-yield.png")
		await RenderingServer.frame_post_draw
		var picture := view.get_texture().get_image()
		stills.append(OUTPUT+"/frames/%04d.png"%frame_number)
		for path in stills:
			if picture.save_png(path)!=OK: failures+=1
		frame_number+=1
	Input.action_release("p1_interact")
	check(progress_seen and mined_frame>10,"%s held E advances real work before yield"%label)
	check(field.remaining_count()==original_count-1 and worker.inventory.get(resource,0)==expected_yield,"%s exactly one original scenario cell yields its actual cargo"%label)
	check(worker.position.distance_to(original_position)<3,"%s stays at its prepared starting feet during the entire real run"%label)
	check(captured_contact and captured_follow,"%s captures forward contact and recovery from the live animation"%label)
	evidence.append({"kind":"real-held-input","character":identity,"direction":"left" if from_right else "right","frames":90,"fps":30,"input":"p1_interact (E)","pressed_frame":10,"released_on_yield_frame":mined_frame,"resource":resource,"yield":worker.inventory.get(resource,0),"cells_before":original_count,"cells_after":field.remaining_count(),"prepared_start":[original_position.x,original_position.y],"final_position":[worker.position.x,worker.position.y],"original_target":[target_location.x,target_location.y],"camera_zoom":3.0,"prepared":"Scenario center/ash_foundry/bastion. Wave clock and medic paused. Original starter ore seam untouched. Only worker starting position, facing, preferred target, camera and empty inventory prepared. Physics and interaction run normally; no movement/animation fields changed during the recorded run."})
	check(await Cleanup.free_scene(game,self),"%s scene released"%label)
	view.queue_free()
	await frames()

func run():
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	InputSetup.install()
	LocaleText.set_locale("de",false)
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"/frames"))
	root.size=Vector2i(320,180)
	await pose_sheets()
	if "--sheets-only" in OS.get_cmdline_user_args():
		var report := FileAccess.open(OUTPUT+"/pose-evidence.json",FileAccess.WRITE)
		report.store_string(JSON.stringify({"checks":checks,"failures":failures,"size":[1920,1440],"contact_errors_world_pixels":contact_errors},"\t"))
		print("MINING SHEETS: %d/%d checks"%[checks-failures,checks])
		quit(0 if failures==0 else 1)
		return
	root.size=Vector2i(320,180)
	await real_run("mara",false)
	await real_run("branko",true)
	check(contact_errors.all(func(error): return error<.01),"All measured held-input contacts remain on the exposed rock face")
	var output := FileAccess.open(OUTPUT+"/evidence.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":RenderingServer.get_current_rendering_driver_name(),"staged_sheets":"Twelve real workers and ore blocks: Mara/Branko/Ivo, right/left, standing/low. Pose frames 1/3/5 prepared explicitly. Low contacts and crouching are presentation fixtures; no progression claimed.","video":"180 rendered frames at fixed simulation rate 30 FPS; 6 seconds, two real held-E runs. Silent MP4; in-game contact audio is exercised but not captured.","contact_errors_world_pixels":contact_errors,"runs":evidence},"\t"))
	print("MINING PRESENTATION: %d/%d checks, %d rendered video frames"%[checks-failures,checks,frame_number])
	quit(0 if failures==0 else 1)
