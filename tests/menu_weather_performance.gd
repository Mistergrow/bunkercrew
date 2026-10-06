extends SceneTree
## Finite real rendered samples; timings describe this machine, not a minimum
## supported GPU. No profile, campaign, sound or network changes are saved.
const OUT := "res://artifacts/menu-weather/performance.json"
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	AudioServer.set_bus_mute(0,true)
	var view := SubViewport.new()
	view.world_2d=World2D.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(),true)
	var game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	for frame in 12: await process_frame
	var panel=game.hud.main_menu_panel
	var records: Array=[]
	for id: String in ["ash_foundry","abandoned_harbor","frozen_rail_yard","storm_dam"]:
		for reduced in [false,true]:
			for index in panel.environments.size():
				if panel.environments[index].id==id: panel.environment_index=index
			panel._show_environment()
			game.weather.reduced_effects=reduced
			for frame in 20: await process_frame
			var frame_ms: Array[float]=[]
			var render_cpu: Array[float]=[]
			var render_gpu: Array[float]=[]
			var last:=Time.get_ticks_usec()
			for frame in 120:
				await process_frame
				var now:=Time.get_ticks_usec()
				frame_ms.append((now-last)/1000.0)
				last=now
				render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(view.get_viewport_rid()))
				render_gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(view.get_viewport_rid()))
			frame_ms.sort(); render_cpu.sort(); render_gpu.sort()
			records.append({"environment":id,"reduced":reduced,"frames":120,"frame_median_ms":frame_ms[60],"frame_p95_ms":frame_ms[114],"viewport_cpu_median_ms":render_cpu[60],"viewport_gpu_median_ms":render_gpu[60],"particle_limit":panel.preview.atmosphere.precipitation_count()+panel.preview.atmosphere.ash_count(),"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))})
			print("MEASURE ",JSON.stringify(records.back()))
	var result:={"resolution":[2560,1440],"vsync":false,"renderer":ProjectSettings.get_setting("rendering/renderer/rendering_method"),"adapter":RenderingServer.get_video_adapter_name(),"cpu":OS.get_processor_name(),"gameplay_paused":paused and not game.started,"samples":records}
	var file:=FileAccess.open(OUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  ")); file.close()
	paused=false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("MENU WEATHER PERFORMANCE: eight QHD samples saved")
	quit()
