extends SceneTree
## Production ownership, clock determinism, bounded allocations and foreground
## migration. Native shader alpha behavior lives in sky_traffic_gallery.gd.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Layers := preload("res://scripts/parallax_landscape.gd")
const Traffic := preload("res://scripts/sky_traffic.gd")
const Profiles := preload("res://scripts/sky_traffic_catalog.gd")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
	print("SKY TRAFFIC %s: %s" % ["PASS" if ok else "FAIL",label])
func frames(count: int=3) -> void:
	for unused in count: await process_frame

func _layers(id: String) -> void:
	var layers := Layers.new()
	layers.configure(id)
	root.add_child(layers)
	var bounds := Rect2(-320,-800,2240,1260)
	var view := Rect2(-120,-340,1700,950)
	layers.update_view(bounds,view,8.0,false)
	var sky=layers.sky_traffic
	check(sky.light_nodes.size()==int(Profiles.definition(id).count) and sky.light_nodes.size()>=1 and sky.light_nodes.size()<=3,id+" distant population stays intentionally bounded")
	check(layers.layers[0].get_index()<sky.get_index() and sky.get_index()<layers.layers[1].get_index(),id+" light/cloud composition sits behind real distant terrain")
	check(sky.far_clouds.get_index()<sky.light_layer.get_index() and sky.light_layer.get_index()<sky.near_clouds.get_index(),id+" lights sit between the two real cloud planes")
	check(sky.cloud_materials.all(func(surface): return surface.get_shader_parameter("cloud_atlas")==Traffic.CLOUDS) and sky.light_materials.all(func(surface): return surface.get_shader_parameter("cloud_atlas")==Traffic.CLOUDS),id+" exact imported cloud atlas drives both drawing and GPU occlusion")
	var count: int=sky.get_child_count()+sky.light_layer.get_child_count()
	var identities: Array=sky.light_nodes.map(func(light):return light.get_instance_id())
	var positions: Array=sky.light_nodes.map(func(light):return light.position)
	var uniforms: Array=sky.light_materials.map(func(surface):return surface.get_shader_parameter("near_clouds"))
	layers.update_view(bounds,view,8.0,false)
	check(positions==sky.light_nodes.map(func(light):return light.position) and uniforms==sky.light_materials.map(func(surface):return surface.get_shader_parameter("near_clouds")),id+" repeated authoritative clock preserves exact trajectories and occlusion coordinates")
	layers.update_view(bounds,view,32.0,false)
	check(positions!=sky.light_nodes.map(func(light):return light.position) and not sky.is_processing(),id+" owner clock alone moves the points without its own frame callback")
	check(sky.light_materials.all(func(surface):return is_equal_approx(float(surface.get_shader_parameter("cloud_clock")),32.0)),id+" visible cloud geometry and occlusion share the same clock")
	for seconds in range(60): layers.update_view(bounds,view,float(seconds),false)
	check(identities==sky.light_nodes.map(func(light):return light.get_instance_id()) and count==sky.get_child_count()+sky.light_layer.get_child_count(),id+" clock changes allocate no presentation nodes or population")
	layers.update_view(bounds,view,8,true)
	check(not sky.visible,id+" reduced effects disable all added sky lights/clouds")
	layers.update_view(bounds,view,8,false)
	check(sky.visible and positions==sky.light_nodes.map(func(light):return light.position),id+" reduced-effects return restores exact authored scene time")
	check(await Cleanup.free_scene(layers,self),id+" bounded sky scene releases")

func _actual_foreground() -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	await frames(5)
	var menu: Control=game.hud.main_menu_panel
	for index in menu.environments.size():
		if str(menu.environments[index].id)=="ash_foundry": menu.environment_index=index
	menu._show_environment()
	await frames(5)
	var preview=menu.preview
	check(is_instance_valid(preview.distant_sky_lights) and preview.distant_sky_lights.get_index()>preview.panorama.get_index(),"Actual flat main-menu panorama uses masked distant sky depth")
	check(preview.distant_sky_lights.cloud_materials.all(func(surface):return surface.get_shader_parameter("mask_sky")==true),"Menu sky cutouts use the authored v3 silhouette mask")
	game.start_scenario(1,{"environment":"ash_foundry","build_type":"bastion","position":"left"})
	await frames(5)
	game.set_process(false)
	var scenery: ScenarioScenery=game.scenery
	var near_samples := 0
	for index in scenery.particle_count():
		var active: Dictionary=scenery.particle_sample(index)
		scenery.parallax_background.sky_traffic.hide()
		var previous: Dictionary=scenery.particle_sample(index)
		scenery.parallax_background.sky_traffic.show()
		check(active.position==previous.position and active.size==previous.size,"Ground ash trajectory and pixel dimensions remain unchanged #"+str(index))
		if active.position.y<170: check(active.color.a==0 and previous.color.a>=0,"Old upper-sky foreground ash is handed to its cloud depth #"+str(index))
		if active.position.y>=240:
			near_samples+=1
			check(active.color==previous.color,"Real ground-level ash survives the sky handover #"+str(index))
	check(near_samples>0,"Actual bounded ash population retains ground-level samples")
	scenery.profile.kind="snow"
	var snow: Dictionary=scenery.particle_sample(0)
	scenery.parallax_background.sky_traffic.hide()
	check(snow==scenery.particle_sample(0),"Foreground snow never uses the ash migration rule")
	check(not game.network.active and not game.microphone.capturing,"Sky inspection opens neither transport nor microphone")
	check(await Cleanup.free_scene(game,self),"Actual menu/world sky fixture and audio release")

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled=false
	for entry: Dictionary in ScenarioCatalog.environments(true): await _layers(str(entry.id))
	await _actual_foreground()
	print("SKY TRAFFIC: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
