extends SceneTree
## Real menus and prepared co-op story state at native QHD and 960x600.
const L:=preload("res://scripts/locale_text.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
const OUTPUT:="res://artifacts/industrial-ui/"
var game
var view: SubViewport
var checks:=0
var failures:=0
var captures: Array[String]=[]
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func overlay(value: String) -> void:
	game.hud.overlay=value
	game.hud._apply_overlay_pause()
	await frames()
func capture(label: String) -> void:
	await frames()
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	check(image.get_size()==view.size and image.save_png(OUTPUT+label+".png")==OK,label+" native renderer capture")
	captures.append(label)
	print("CAPTURE ",label)
func click(control: Control) -> void:
	var at:=view.get_final_transform()*control.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new()
	motion.position=at
	view.push_input(motion,false)
	await process_frame
	for down in [true,false]:
		var event:=InputEventMouseButton.new()
		event.position=at
		event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=down
		view.push_input(event,false)
		await process_frame
	await frames()

func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.combat_events.persistence_enabled=false
	game.audio.set_music_volume(0)
	game.audio.set_voice_volume(0)
	await frames(6)
	if "--markers-only" in OS.get_cmdline_user_args():
		game.story_mode=true
		game.start_scenario(2,{"environment":"overgrown_steelworks","position":"center","build_type":"bastion"})
		game.rounds.set_process(false)
		game.dialogue.reset()
		game.dialogue.set_process(false)
		game.notice_time=0
		game.set_camera_zoom(2.5)
		for worker in game.players: worker.set_physics_process(false)
		var target: Vector2=game.story.target_position()
		for worker in game.players: worker.global_position=Vector2(minf(game.world_right-55,target.x+610)+(worker.player_id-1.5)*40,430)
		L.set_locale("de",false)
		await overlay("")
		game.player_camera.update_view(0,true)
		await capture("qhd-de-objective-left")
		for worker in game.players: worker.global_position=Vector2(game.scenario_bunker.core_x+(worker.player_id-1.5)*40,245)
		game.player_camera.update_view(0,true)
		L.set_locale("en",false)
		game.dialogue.enqueue("wall_hint","san")
		game.dialogue.advance(.4)
		await frames()
		game.dialogue.advance(.4)
		await capture("qhd-en-objective-below-radio")
		await Cleanup.free_scene(game,self)
		print("Industrial UI objective update: %d/%d checks passed"%[checks-failures,checks])
		quit(1 if failures else 0)
		return
	if "--camera-only" in OS.get_cmdline_user_args():
		for resolution in ["qhd","small"]:
			view.size=Vector2i(2560,1440) if resolution=="qhd" else Vector2i(960,600)
			view.size_2d_override=Vector2i(1600,900) if resolution=="qhd" else Vector2i(1440,900)
			await frames()
			game.hud._layout_viewport()
			for locale in ["de","en"]:
				L.set_locale(locale,false)
				await overlay("audio")
				game.hud.options_panel.select_tab(1)
				await capture(resolution+"-"+locale+"-options-1")
		await Cleanup.free_scene(game,self)
		print("Industrial UI camera update: %d/%d checks passed"%[checks-failures,checks])
		quit(1 if failures else 0)
		return
	for resolution in ["qhd","small"]:
		view.size=Vector2i(2560,1440) if resolution=="qhd" else Vector2i(960,600)
		view.size_2d_override=Vector2i(1600,900) if resolution=="qhd" else Vector2i(1440,900)
		await frames()
		game.hud._layout_viewport()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			await overlay("menu")
			await capture(resolution+"-"+locale+"-menu")
			game.hud.audio_return_overlay="menu"
			await overlay("audio")
			await click(game.hud.options_panel.tab_buttons[2])
			check(game.hud.options_panel.tab==2,"Physical mouse coordinates select audio tab at "+resolution)
			for index in 4:
				game.hud.options_panel.select_tab(index)
				await capture(resolution+"-"+locale+"-options-"+str(index))
			if resolution=="qhd":
				await overlay("scenario")
				await capture(resolution+"-"+locale+"-scenario")
				await overlay("characters")
				await capture(resolution+"-"+locale+"-characters")
				await overlay("network")
				await capture(resolution+"-"+locale+"-network")
			await overlay("microphone")
			check(not game.microphone.capturing,"Capture does not activate physical microphone")
			await capture(resolution+"-"+locale+"-microphone")
	game.story_mode=true
	game.start_scenario(2,{"environment":"overgrown_steelworks","position":"center","build_type":"bastion"})
	game.notice_time=0
	game.reset_camera_view()
	for worker in game.players: worker.set_physics_process(false)
	game.rounds.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	game.players[0].add_item("steel",2)
	game.players[0].add_item("concrete",2)
	game.players[1].hp=54
	game.players[1].medical.bleeding=1
	game.upgrades.add_points(8)
	game.notice_time=0
	for resolution in ["qhd","small"]:
		view.size=Vector2i(2560,1440) if resolution=="qhd" else Vector2i(960,600)
		view.size_2d_override=Vector2i(1600,900) if resolution=="qhd" else Vector2i(1440,900)
		await frames()
		game.hud._layout_viewport()
		for locale in ["de","en"]:
			L.set_locale(locale,false)
			await overlay("")
			game.set_camera_zoom(1.25)
			game.player_camera.update_view(0,true)
			await capture(resolution+"-"+locale+"-coop-story")
			game.set_camera_zoom(1.8)
			game.player_camera.update_view(0,true)
			await capture(resolution+"-"+locale+"-coop-zoom")
			game.set_camera_zoom(1.25)
			game.player_camera.update_view(0,true)
			for modal in ["upgrades","personal","help"]:
				await overlay(modal)
				await capture(resolution+"-"+locale+"-"+modal)
	await Cleanup.free_scene(game,self)
	print("Industrial UI preview: %d/%d checks passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
