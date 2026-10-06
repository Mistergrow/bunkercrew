extends SceneTree
## Author-pixel checks for every location and five focused GPU comparisons with
## all other animation held still. Never loads or writes a real player profile.
const OUT := "res://artifacts/v3-effects/menu/"
const FOCUSED := ["ash_foundry","abandoned_harbor","basalt_quarry","overgrown_steelworks","frozen_rail_yard","iron_canyon","flooded_power_station","mountain_pass","storm_dam","sulfur_refinery","radar_highlands","buried_megafactory","sector07"]
var view: SubViewport
var game
var checks := 0
var failures := 0
var records: Array = []
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)
	else: print("PASS ",label)
func frames(count:=3) -> void:
	for frame in count: await process_frame
func shot(label: String) -> Image:
	await frames()
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	picture.convert(Image.FORMAT_RGBA8)
	picture.save_png(OUT+label+".png")
	return picture
func changed(a: Image,b: Image) -> int:
	var first:=a.get_data()
	var second:=b.get_data()
	var count:=0
	for pixel in range(0,first.size(),4):
		if maxi(absi(first[pixel]-second[pixel]),maxi(absi(first[pixel+1]-second[pixel+1]),absi(first[pixel+2]-second[pixel+2])))>1: count+=1
	return count
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	var gpu:=DisplayServer.get_name()!="headless" and "--capture" in OS.get_cmdline_user_args()
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	view=SubViewport.new()
	view.world_2d=World2D.new()
	view.size=Vector2i(1920,1080)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(8)
	var menu=game.hud.main_menu_panel
	menu.set_process(false)
	for environment: Dictionary in ScenarioCatalog.environments(true):
		var original: Dictionary=ScenarioCatalog.environment(environment.id)
		for index in menu.environments.size():
			if menu.environments[index].id==environment.id: menu.environment_index=index
		menu._show_environment()
		menu.decoration.queue_redraw()
		var preview=menu.preview
		preview.set_process(false)
		preview.elapsed=6.0
		preview._redraw_clock=1.0
		preview._process(0.0)
		var details=preview.landmark_effects
		check(not details.definition.is_empty(),environment.id+" has intentional local detail choices")
		check(details.patches.size()<=12 and details.plumes.size()<=3 and details.banks.size()<=2,environment.id+" local detail cost remains bounded")
		for patch: Dictionary in details.patches:
			check(Rect2(0,0,1,1).encloses(patch.uv),environment.id+" source region stays inside original panorama")
			check(patch.sprite.texture==preview.panorama.texture,environment.id+" luminous/flow pixels come from its own panorama")
		for plume in details.plumes:
			check(is_equal_approx(float(plume.material.get_shader_parameter("gust_strength")),float(preview.atmosphere.weather_profile.gust)),environment.id+" localized steam uses the location gust factor")
		check(ScenarioCatalog.environment(environment.id)==original,environment.id+" leaves playable environment data untouched")
		if gpu and environment.id in FOCUSED:
			details.hide()
			var without: Image=await shot(environment.id+"-original")
			details.show()
			details.update_at(0,false,12)
			var first: Image=await shot(environment.id+"-t0")
			details.update_at(8,false,64)
			var second: Image=await shot(environment.id+"-t8")
			var contribution:=changed(without,first)
			var motion:=changed(first,second)
			check(contribution>30,environment.id+" details are actually visible in current menu composition")
			check(motion>20,environment.id+" local animation changes visible pixels with all other clocks fixed")
			records.append({"environment":environment.id,"visible_detail_pixels":contribution,"animated_pixels_8s":motion})
			details.update_at(8,false,64)
			await frames()
			await RenderingServer.frame_post_draw
			check(view.get_texture().get_image().get_data()==second.get_data(),environment.id+" same preview clock produces exactly the same image")
		details.update_at(8,true,64)
		check(details.patches.all(func(patch):return patch.sprite.visible==(int(patch.effect)==1)),environment.id+" reduced mode disables additional light modulation")
		check(details.plumes.all(func(plume):return bool(plume.material.get_shader_parameter("reduced_effects"))),environment.id+" reduced mode reaches all local steam meshes")
	check(paused and not game.started and not game.network.active,"Local detail previews leave gameplay and networking inactive")
	var report:=FileAccess.open(OUT+"verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"gpu":gpu,"other_animation_frozen":true,"records":records},"  "));report.close()
	paused=false
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	view.queue_free()
	await process_frame
	print("MENU LANDMARK DETAILS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
