extends SceneTree
## Rendered developer UI and prepared, silent 60 Hz dance states. Video captures
## real WorkerVisual rigs; it is not a recording of a live game or audio mixer.
const Lab := preload("res://scripts/music_dev_dashboard.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Rhythm gallery requires native graphical rendering")
		quit(1)
		return
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var directory := "res://artifacts/rhythm-music"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	var lab := Lab.new()
	root.add_child(lab)
	await process_frame
	await process_frame
	# Prepared visual comparison has a controlled beat phase and no playback.
	lab.preview_session.end_session()
	lab.set_process(false)
	lab.preview_clock.elapsed = 2.0
	lab._process(0.0)
	for actor in lab.preview_world.actors:
		actor.get_node("PixelVisual")._process(2.0)
	lab.status.text = LocaleText.text("Vorbereitete, stumme Taktvorschau · echte Spielfiguren")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/dashboard-defaults.png")
	lab.configuration.dance_intensity = 1.5
	for index in Dance.IDS.size():
		var id: String = Dance.IDS[index]
		lab.configuration.dance_profiles[id] = {"style":Dance.STYLES[index],"intensity":1.5}
	lab._sync_controls()
	lab._update_dance()
	for frame in 240:
		lab._process(1.0/60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels := root.get_texture().get_image()
		pixels.save_jpg(directory+"/frames/%04d.jpg"%frame,0.95)
		if frame == 120: pixels.save_png(directory+"/dashboard-styles.png")
	lab.configuration.reduced_motion = true
	lab._sync_controls()
	lab._update_dance()
	lab._process(1.0/60.0)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory+"/dashboard-reduced.png")
	var feedback := FileAccess.open(directory+"/example-feedback.json",FileAccess.WRITE)
	feedback.store_string(lab.export_json())
	var verification := {"renderer":RenderingServer.get_video_adapter_name(),"size":[1440,900],"frames":240,"fps":60,"prepared_states":true,"audible_recording":false,"actual_crew_rigs":6,"styles":Dance.STYLES,"feet":"original planted anchors preserved"}
	var file := FileAccess.open(directory+"/gallery-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(verification,"\t"))
	print("RHYTHM GALLERY: native dashboard captures + 240 prepared frames at 60 Hz")
	await Cleanup.free_scene(lab,self)
	quit()
