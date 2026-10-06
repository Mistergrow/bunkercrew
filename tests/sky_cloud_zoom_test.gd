extends SceneTree
## Real scenes and owner updates establish source registration under zoom/pan.
## Native alpha probes use the active near-cloud plane and its actual aircraft.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const SCREEN := Vector2i(1280,720)
const CLOCK := 8.0
const POSES := [
	{"id":"normal085","position":Vector2(720,150),"zoom":.85},
	{"id":"wide060","position":Vector2(720,150),"zoom":.60},
	{"id":"close125","position":Vector2(720,150),"zoom":1.25},
	{"id":"pan-left","position":Vector2(400,150),"zoom":.85},
	{"id":"pan-zoom-right","position":Vector2(1060,100),"zoom":1.15},
	{"id":"sky085","position":Vector2(720,-180),"zoom":.85},
]
var view: SubViewport
var game
var scenery: ScenarioScenery
var depths
var sky
var checks := 0
var failures := 0
var records: Array[Dictionary] = []
var output_directory := "res://artifacts/sky-cloud-zoom-20261005/regression/"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("SKY CLOUD ZOOM %s: %s"%["PASS" if ok else "FAIL",label])

func frames(count: int=3) -> void:
	for unused in count: await process_frame

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)

func key(code: Key) -> void:
	for down in [true,false]:
		var event := InputEventKey.new()
		event.keycode=code
		event.physical_keycode=code
		event.pressed=down
		view.push_input(event,true)
		await process_frame
	await frames()

func setup() -> void:
	AudioServer.set_bus_mute(0,true)
	CrewRoster.persistence_enabled=false
	view=SubViewport.new()
	view.size=SCREEN
	view.world_2d=World2D.new()
	view.transparent_bg=true
	view.gui_embed_subwindows=true
	view.process_mode=Node.PROCESS_MODE_ALWAYS
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)

func world(environment: String,classic: bool=false) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames()
	game.audio.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.campaign.persistence_enabled=false
	if classic: game.start(1)
	else: game.start_scenario(1,{"environment":environment,"build_type":"bastion","position":"center"})
	await frames(5)
	freeze(game)
	game.rounds.running=false
	game.notice_time=0
	game.hud.canvas.hide()
	game.weather.hide()
	scenery=game.scenery
	scenery.set_layered_enabled(true)
	depths=scenery.parallax_background
	sky=depths.sky_traffic
	check(is_instance_valid(sky) and depths.layers[0].name=="WeatherSky" and not scenery.cloud_layer.is_visible_in_tree(),environment+": actual mission uses WeatherSky and its active SkyTraffic, excluding the hidden legacy atlas")

func stage(pose: Dictionary,seconds: float=CLOCK) -> void:
	game.camera.position=pose.position
	game.camera.zoom=Vector2.ONE*float(pose.zoom)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await frames()
	scenery.elapsed=seconds
	# Actual owner recalculates both its camera rectangle and active materials.
	# Zero delta leaves wind, time and unrelated scene motion frozen.
	scenery._process(0.0)
	await frames()

func geometry(pose: Dictionary) -> Dictionary:
	var bounds: Rect2=sky.sky_bounds
	var normalized_cards: Array[Vector4]=[]
	var normalized_lights: Array[Vector2]=[]
	var normalized_light_scales: Array[Vector2]=[]
	for plane: Array in sky.cloud_cards:
		for card: Rect2 in plane:
			var origin: Vector2=(card.position-bounds.position)/bounds.size
			var dimensions: Vector2=card.size/bounds.size
			normalized_cards.append(Vector4(origin.x,origin.y,dimensions.x,dimensions.y))
	for light: Node2D in sky.light_nodes:
		normalized_lights.append((light.position-bounds.position)/bounds.size)
		normalized_light_scales.append(light.scale/bounds.size)
	return {"pose":pose.id,"camera":[game.camera.position.x,game.camera.position.y],"zoom":game.camera.zoom.x,"sky_bounds":bounds,"cards":normalized_cards,"lights":normalized_lights,"light_scales":normalized_light_scales,"visible_lights":sky.light_nodes.filter(func(light):return light.visible).size()}

func same_vectors(first: Array,second: Array) -> bool:
	if first.size()!=second.size(): return false
	for index in first.size():
		if first[index].distance_to(second[index])>0.00001: return false
	return true

func registration(label: String) -> void:
	var bounds: Rect2=depths.layer_rects[0]
	check(sky.sky_bounds.is_equal_approx(bounds),label+": active sky and transparent-cloud geometry use the exact WeatherSky rectangle")
	var foreground: Array[Vector4]=[]
	for card: Rect2 in sky.cloud_cards[1]: foreground.append(Vector4(card.position.x,card.position.y,card.size.x,card.size.y))
	for index in sky.light_nodes.size():
		var light: Node2D=sky.light_nodes[index]
		var surface: ShaderMaterial=sky.light_materials[index]
		check(surface.get_shader_parameter("near_clouds")==foreground,label+": aircraft "+str(index)+" samples the actual visible near-cloud rectangles")
		check(surface.get_shader_parameter("light_origin")==light.position,label+": aircraft "+str(index)+" samples from its actual drawn origin")
		var has_scale: bool=surface.shader.get_shader_uniform_list().any(func(uniform: Dictionary):return uniform.name=="light_scale")
		check(has_scale and surface.get_shader_parameter("light_scale")==light.scale,label+": aircraft "+str(index)+" shader accounts for the actual scaled drawing")
		check(is_equal_approx(float(surface.get_shader_parameter("cloud_clock")),CLOCK),label+": aircraft "+str(index)+" and cloud deformation share the held owner clock")
	check(sky.cloud_materials.all(func(surface: ShaderMaterial):return is_equal_approx(float(surface.get_shader_parameter("cloud_clock")),CLOCK)),label+": both active transparent cloud planes retain the same clock")
	var linked: bool="sky_uv_drift" in depths
	check(linked,label+": painted WeatherSky owns the common source-UV drift")
	if linked:
		var drift: Vector2=depths.sky_uv_drift
		check(depths.image_materials[0].get_shader_parameter("use_sky_drift")==true and depths.image_materials[0].get_shader_parameter("sky_drift")==drift,label+": WeatherSky samples the same explicit UV drift as its owner")
		check((sky.cloud_materials+sky.light_materials).all(func(surface: ShaderMaterial):return surface.get_shader_parameter("sky_drift")==drift),label+": every actual cloud/light material shares WeatherSky's exact drift")

func picture() -> Image:
	for unused in 2: await RenderingServer.frame_post_draw
	var rendered := view.get_texture().get_image()
	rendered.convert(Image.FORMAT_RGBA8)
	return rendered

func isolate_near() -> Array[Dictionary]:
	var saved: Array[Dictionary]=[]
	# ScenarioScenery paints its own opaque sky. self_modulate hides only
	# that parent draw while preserving the original cloud/light descendants.
	saved.append({"node":scenery,"property":"self_modulate","value":scenery.self_modulate})
	var modulation:=scenery.self_modulate
	modulation.a=0.0
	scenery.self_modulate=modulation
	for parent: Node in [game,scenery,depths]:
		for child: Node in parent.get_children():
			if not child is CanvasItem or child in [scenery,depths,sky,game.camera]: continue
			saved.append({"node":child,"property":"visible","value":child.visible})
			child.hide()
	for node: CanvasItem in [sky.far_clouds,sky.light_layer]:
		saved.append({"node":node,"property":"visible","value":node.visible})
		node.hide()
	var pending: Array[Node]=[game]
	while not pending.is_empty():
		var item: Node=pending.pop_back()
		pending.append_array(item.get_children())
		if item is CanvasLayer:
			saved.append({"node":item,"property":"visible","value":item.visible})
			item.hide()
	return saved

func restore_visibility(saved: Array[Dictionary]) -> void:
	for item: Dictionary in saved: item.node.set(item.property,item.value)

func probe_points(mask: Image) -> Dictionary:
	var result: Dictionary={}
	var tint: Color=sky.cloud_materials[1].get_shader_parameter("cloud_tint")
	var inverse: Transform2D=scenery.get_global_transform_with_canvas().affine_inverse()
	for y in range(12,mask.get_height()-12,6):
		for x in range(12,mask.get_width()-12,6):
			var point:=Vector2i(x,y)
			var position: Vector2=inverse*(Vector2(point)+Vector2(.5,.5))
			var containing:=0
			for card: Rect2 in sky.cloud_cards[1]:
				if card.grow(-8).has_point(position): containing+=1
			if containing!=1: continue
			var alpha:=mask.get_pixelv(point).a
			var kind: String="clear" if alpha<.002 else "dense" if alpha>=tint.a*.94 else ""
			if kind.is_empty() or result.has(kind): continue
			var stable:=true
			for offset: Vector2i in [Vector2i(-3,0),Vector2i(3,0),Vector2i(0,-3),Vector2i(0,3)]:
				var neighbor:=mask.get_pixelv(point+offset).a
				if (kind=="clear" and neighbor>.002) or (kind=="dense" and neighbor<tint.a*.85): stable=false
			if stable: result[kind]={"pixel":point,"world":position,"cloud_alpha":alpha}
			if result.size()==2: return result
	return result

func alpha_registration(label: String) -> void:
	# Isolate existing production nodes; no synthetic atlas, mask or shader.
	var saved:=isolate_near()
	var mask:=await picture()
	var targets:=probe_points(mask)
	check(targets.size()==2,label+": active near-cloud GPU pixels contain coherent clear and dense samples")
	var measurements: Dictionary={}
	sky.near_clouds.hide()
	sky.light_layer.show()
	for lamp: Node2D in sky.light_nodes: lamp.hide()
	var light: Node2D=sky.light_nodes[0]
	var surface: ShaderMaterial=sky.light_materials[0]
	light.show()
	for kind: String in targets:
		light.position=targets[kind].world
		surface.set_shader_parameter("light_origin",light.position)
		var rendered:=await picture()
		measurements[kind]={"alpha":rendered.get_pixelv(targets[kind].pixel).a,"cloud_alpha":targets[kind].cloud_alpha,"pixel":targets[kind].pixel}
	if measurements.size()==2:
		check(float(measurements.clear.alpha)>.55 and float(measurements.dense.alpha)<.02,label+": actual aircraft remains visible through a GPU cloud gap and vanishes at the same dense contour")
	records.append({"alpha_probe":label,"samples":measurements,"active_plane":sky.near_clouds.get_path(),"active_light":light.get_path()})
	sky.near_clouds.show()
	restore_visibility(saved)
	# Restore the real owner trajectory, shader origins and visibility.
	scenery._process(0.0)
	await frames()

func cloud_phase(seconds: float) -> float:
	scenery.elapsed=seconds
	scenery._process(0.0)
	var first: Rect2=sky.cloud_cards[1][0]
	var next: Rect2=sky.cloud_cards[1][1]
	var period: float=(next.position.x-first.position.x)/sky.sky_bounds.size.x
	var drift: Vector2=depths.sky_uv_drift if "sky_uv_drift" in depths else Vector2.ZERO
	return fposmod((first.position.x-sky.sky_bounds.position.x)/sky.sky_bounds.size.x+drift.x,period)

func wrap_registration() -> void:
	await stage({"id":"left-sky-edge","position":Vector2(1900,150),"zoom":.85})
	var previous:=cloud_phase(0.0)
	var lower: float=-1.0
	var upper: float=-1.0
	for second in range(1,181):
		var phase_at:=cloud_phase(float(second))
		if phase_at<previous-.15:
			lower=float(second-1)
			upper=float(second)
			break
		previous=phase_at
	check(lower>=0.0,"Actual sector07 source-clock sweep crosses a real near-cloud period boundary")
	if lower<0.0: return
	for unused in 18:
		var middle: float=(lower+upper)*.5
		if cloud_phase(middle)>.2: lower=middle
		else: upper=middle
	var boundary: float=(lower+upper)*.5
	var images: Array[Image]=[]
	var states: Array[Dictionary]=[]
	for seconds: float in [boundary-.001,boundary+.001]:
		cloud_phase(seconds)
		var first: Rect2=sky.cloud_cards[1][0]
		var sample:=Vector2(sky.sky_bounds.position.x+1.0,first.get_center().y)
		var overlapping:=0
		for card: Rect2 in sky.cloud_cards[1]:
			if card.has_point(sample): overlapping+=1
		check(sky.cloud_cards[1].size()==4 and overlapping==2,"Actual near-cloud period edge retains both imported overlapping contours at the left sky boundary @"+str(seconds))
		states.append({"clock":seconds,"left_overlap":overlapping,"cards":str(sky.cloud_cards[1])})
		if DisplayServer.get_name()!="headless":
			var hidden:=isolate_near()
			images.append(await picture())
			restore_visibility(hidden)
	if images.size()==2:
		var changed:=0
		var examined:=0
		for y in range(8,view.size.y-8):
			for x in range(0,120):
				if maxf(images[0].get_pixel(x,y).a,images[1].get_pixel(x,y).a)<.002: continue
				examined+=1
				if absf(images[0].get_pixel(x,y).a-images[1].get_pixel(x,y).a)>.015: changed+=1
		check(examined>=100 and float(changed)/maxi(1,examined)<.05,"Actual imported near-cloud alpha has no popped left-edge contour across a two-millisecond source wrap: %d/%d changed"%[changed,examined])
		records.append({"wrap_pixels":{"changed":changed,"examined":examined,"threshold":.015,"maximum_fraction":.05}})
	records.append({"source_wrap":states})
	await stage(POSES[0])

func culling_registration(label: String) -> void:
	await stage(POSES[1])
	var bounds: Rect2=sky.sky_bounds
	var light: Node2D=sky.light_nodes[0]
	var half: Vector2=Vector2(14,9)*light.scale
	var drift: Vector2=depths.sky_uv_drift if "sky_uv_drift" in depths else Vector2.ZERO
	var partial:=Rect2(light.position+Vector2(half.x*.9,-half.y*.5),Vector2(8,half.y))
	sky.update_view(bounds,partial,CLOCK,false,drift)
	check(light.visible,label+": real scaled aircraft quad stays eligible when its origin lies outside a partially intersecting view")
	var outside:=Rect2(light.position+Vector2(half.x+1,-half.y*.5),Vector2(8,half.y))
	sky.update_view(bounds,outside,CLOCK,false,drift)
	check(not light.visible,label+": real aircraft is culled only after its complete scaled quad leaves the view")
	await stage(POSES[0])

func menu_registration(environment: String) -> void:
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	await frames(5)
	game.audio.persistence_enabled=false
	game.combat_events.persistence_enabled=false
	game.campaign.persistence_enabled=false
	var menu: Control=game.hud.main_menu_panel
	for index in menu.environments.size():
		if str(menu.environments[index].id)==environment: menu.environment_index=index
	menu._show_environment()
	await frames()
	freeze(game)
	var preview: ScenarioScenery=menu.preview
	preview.elapsed=CLOCK
	preview._process(1.0)
	var traffic=preview.distant_sky_lights
	check(is_instance_valid(traffic) and traffic.cloud_materials.all(func(surface: ShaderMaterial):return surface.get_shader_parameter("mask_sky")==true),environment+": actual menu preserves its authored flat-panorama skyline mask")
	var bounds: Rect2=traffic.sky_bounds
	var foreground: Array[Vector4]=[]
	for card: Rect2 in traffic.cloud_cards[1]:foreground.append(Vector4(card.position.x,card.position.y,card.size.x,card.size.y))
	check(traffic.light_materials.all(func(surface: ShaderMaterial):return surface.get_shader_parameter("near_clouds")==foreground and surface.get_shader_parameter("sky_bounds")==Vector4(bounds.position.x,bounds.position.y,bounds.size.x,bounds.size.y)),environment+": actual menu aircraft masks remain registered to visible cloud quads and panorama bounds")
	await key(KEY_F3)
	preview.elapsed=CLOCK
	preview._process(1.0)
	check(game.weather.reduced_effects and not traffic.visible,environment+": actual menu F3 separately hides added cloud and light planes")
	await key(KEY_F3)
	check(not game.started and game.players.is_empty() and not game.network.active and not game.microphone.capturing,environment+": actual menu mask inspection constructs no world, workers, transport or microphone")
	check(await Cleanup.free_scene(game,self),environment+": actual menu panorama and masked sky retire")
	game=null

func route_registration() -> void:
	await world("ash_foundry")
	game.rounds.wave=20
	check(game.expedition.on_victory() and game.campaign.select_destination("harbor") and game.campaign.select_stop("harbor:fuel"),"Actual mission victory prepares a real harbor supply journey")
	check(not game.campaign.begin_journey().is_empty(),"Actual travel fuel/state commit creates the journey")
	game.expedition._start_road()
	await frames()
	freeze(game)
	var roads: Array=game.get_children().filter(func(node: Node):return node.get_script()!=null and node.get_script().resource_path=="res://scripts/expedition_road_art.gd")
	check(roads.size()==1,"Actual road owns one ExpeditionDepth RouteHorizon")
	if roads.size()!=1:
		await Cleanup.free_scene(game,self)
		return
	var road=roads[0]
	road._sync_travel_view()
	var route=road.depth
	game.camera.position=Vector2(2000,100)
	game.camera.zoom=Vector2.ONE*.85
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	route._update_view()
	for parent: Node in [game,road,route]:
		for child: Node in parent.get_children():
			if child is CanvasItem and child not in [road,route,route.layers[0],game.camera]: child.hide()
	var truck=game.expedition.vehicle
	truck.animation_time=0.0
	route._process(0.0)
	var beginning: Image=await picture() if DisplayServer.get_name()!="headless" else null
	truck.animation_time=16.0
	route._process(0.0)
	check(route.layers[0].name=="RouteHorizon" and route.layers[0].material.get_shader_parameter("scene_clock")==16.0 and route.layers[0].material.get_shader_parameter("motion_gain")==1.0,"Actual RouteHorizon retains its own truck clock and active sky motion without a WeatherSky mask owner")
	if beginning!=null:
		var later:=await picture()
		check(beginning.get_data()!=later.get_data(),"Actual isolated RouteHorizon native pixels still animate after the shared WeatherSky shader change")
	await key(KEY_F3)
	truck.animation_time=0.0
	route._process(0.0)
	var reduced: Image=await picture() if DisplayServer.get_name()!="headless" else null
	truck.animation_time=16.0
	route._process(0.0)
	check(game.weather.reduced_effects and route.layers[0].material.get_shader_parameter("motion_gain")==0.0,"Actual travel F3 freezes the RouteHorizon shader separately")
	if reduced!=null:
		var reduced_later:=await picture()
		check(reduced.get_data()==reduced_later.get_data(),"Actual isolated RouteHorizon native pixels stay fixed across different clocks in F3")
	check(await Cleanup.free_scene(game,self),"Actual journey, vehicle and RouteHorizon release")
	game=null

func exercise(environment: String,classic: bool=false) -> void:
	var label: String="classic_sector07" if classic else environment
	await world(environment,classic)
	await stage(POSES[0])
	var reference:=geometry(POSES[0])
	var identities: Array=sky.light_nodes.map(func(light: Node2D):return light.get_instance_id())
	for pose: Dictionary in POSES:
		await stage(pose)
		var sample:=geometry(pose)
		check(same_vectors(reference.cards,sample.cards),label+" "+str(pose.id)+": frozen cloud origins and sizes retain WeatherSky source coordinates through zoom and pan")
		check(same_vectors(reference.lights,sample.lights),label+" "+str(pose.id)+": frozen aircraft path retains WeatherSky source coordinates through zoom and pan")
		check(same_vectors(reference.light_scales,sample.light_scales),label+" "+str(pose.id)+": aircraft drawing retains its source-pixel size through zoom and pan")
		registration(label+" "+str(pose.id))
		records.append({"world":label,"geometry":sample})
		if DisplayServer.get_name()!="headless" and pose.id in ["normal085","pan-zoom-right"]:
			await alpha_registration(label+" "+str(pose.id))
	await key(KEY_F3)
	await stage(POSES[2])
	check(game.weather.reduced_effects and not sky.is_visible_in_tree(),label+": actual F3 hides every added transparent cloud and sky light during a simultaneous zoom")
	check(depths.materials.all(func(surface: ShaderMaterial):return float(surface.get_shader_parameter("motion_gain"))==0.0),label+": F3 independently freezes the active painted WeatherSky motion")
	await key(KEY_F3)
	await stage(POSES[0])
	var restored:=geometry(POSES[0])
	check(not game.weather.reduced_effects and sky.is_visible_in_tree() and same_vectors(reference.cards,restored.cards) and same_vectors(reference.lights,restored.lights),label+": standard effects restore exact source registration at the held scene clock")
	check(identities==sky.light_nodes.map(func(light: Node2D):return light.get_instance_id()),label+": zoom, pan and F3 do not allocate or replace aircraft nodes")
	await culling_registration(label)
	if label=="sector07": await wrap_registration()
	check(not game.network.active and not game.microphone.capturing,label+": real scene inspection opens no match transport or microphone")
	check(await Cleanup.free_scene(game,self),label+": real scene releases workers, sky resources and native audio")
	game=null

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2);return
	setup()
	var environments: Array=ScenarioCatalog.environments(true)
	check(environments.size()==13,"all thirteen selectable and campaign environments are represented")
	for entry: Dictionary in environments: await exercise(str(entry.id))
	await exercise("sector07",true)
	for environment: String in ["sector07","ash_foundry"]: await menu_registration(environment)
	await route_registration()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	FileAccess.open(output_directory+"report.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"native_alpha_probes":DisplayServer.get_name()!="headless","worlds":records,"prepared":"Actual solo scenes for all13 environments plus actual classic start. 1280x720 native SubViewport, actual Camera2D zoom and pan, scene clock8 and wind held; real owner _process(0) recalculates active WeatherSky/SkyTraffic. Actual F3 key routing separately checks reduced effects. GPU probes isolate the original near-cloud node and original aircraft/materials, sample their actual rendered gap/dense alpha, and restore owner trajectories; no fabricated atlas. Muted isolated profile with persistence disabled, no transport or microphone."},"  "))
	view.queue_free()
	await frames()
	print("SKY CLOUD ZOOM: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
