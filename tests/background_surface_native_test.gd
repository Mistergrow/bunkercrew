extends SceneTree
## Actual depth-plate masks, dry-pixel safety and prepared gameplay captures.
const Depths := preload("res://scripts/parallax_landscape.gd")
const Surfaces := preload("res://scripts/background_surface_catalog.gd")
const Plates := preload("res://scripts/parallax_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/background-surfaces/native"
var checks := 0
var failures := 0
var records: Array[Dictionary]=[]
var video_segments: Array[Dictionary]=[]

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func frozen(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): frozen(child)

func rendered(viewport: Viewport) -> Image:
	for frame in 2: await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func kind_at(mask: Image,bounds: Vector4,source_size: Vector2i,at: Vector2i) -> Color:
	var uv := (Vector2(at)+Vector2.ONE*0.5)/Vector2(source_size)
	var local := (uv-Vector2(bounds.x,bounds.y))/Vector2(bounds.z,bounds.w)
	if local.x<0.0 or local.y<0.0 or local.x>=1.0 or local.y>=1.0: return Color.BLACK
	return mask.get_pixel(clampi(floori(local.x*mask.get_width()),0,mask.get_width()-1),clampi(floori(local.y*mask.get_height()),0,mask.get_height()-1))

func same(first: Color,second: Color) -> bool:
	return absf(first.r-second.r)<0.001 and absf(first.g-second.g)<0.001 and absf(first.b-second.b)<0.001 and absf(first.a-second.a)<0.001

func active(mask: Image,x: int,y: int) -> bool:
	if x<0 or y<0 or x>=mask.get_width() or y>=mask.get_height(): return false
	var color := mask.get_pixel(x,y)
	return color.r>0.0 or color.g>0.0

func fractional_edges(viewport: SubViewport,sprite: Sprite2D,surface: ShaderMaterial,mask: Image,bounds: Vector4,id: String) -> Dictionary:
	var source_size := Vector2i(sprite.texture.get_size())
	var origin := Vector2i(roundi(bounds.x*source_size.x),roundi(bounds.y*source_size.y))
	var ring: Array[Vector2i]=[]
	for y in range(-1,mask.get_height()+1):
		for x in range(-1,mask.get_width()+1):
			if not active(mask,x,y) and (active(mask,x-1,y) or active(mask,x+1,y) or active(mask,x,y-1) or active(mask,x,y+1)):
				ring.append(origin+Vector2i(x,y))
	sprite.scale=Vector2.ONE*1.35
	viewport.size=Vector2i(ceili(source_size.x*1.35)+2,ceili(source_size.y*1.35)+2)
	surface.set_shader_parameter("ice_glint",0.0)
	var outside_changes := 0
	var sampled_pixels := 0
	var phases: Array[Dictionary]=[]
	for phase: float in [0.3,0.37]:
		sprite.position=Vector2.ONE*phase
		var pixels: Dictionary={}
		for source_at: Vector2i in ring:
			var center := Vector2i(((Vector2(source_at)+Vector2.ONE*.5)*1.35+sprite.position).floor())
			for y in range(center.y-2,center.y+3):
				for x in range(center.x-2,center.x+3):
					if x<0 or y<0 or x>=viewport.size.x or y>=viewport.size.y: continue
					var at := Vector2i(x,y)
					var source_point := (Vector2(at)+Vector2.ONE*.5-sprite.position)/1.35
					if source_point.x<0 or source_point.y<0 or source_point.x>=source_size.x or source_point.y>=source_size.y: continue
					# Exact nearest-mask boundaries can choose either neighbor after
					# GPU float rounding. The second phase covers those edge pixels.
					var fraction := source_point-source_point.floor()
					if minf(minf(fraction.x,fraction.y),minf(1.0-fraction.x,1.0-fraction.y))<0.0002: continue
					var kind := kind_at(mask,bounds,source_size,Vector2i(source_point.floor()))
					if kind.r==0.0 and kind.g==0.0: pixels[at]=true
		surface.set_shader_parameter("motion_gain",0.0)
		surface.set_shader_parameter("scene_clock",0.0)
		var first := await rendered(viewport)
		surface.set_shader_parameter("motion_gain",1.0)
		surface.set_shader_parameter("scene_clock",7.0)
		var later := await rendered(viewport)
		var changed := 0
		for at: Vector2i in pixels:
			if not same(first.get_pixelv(at),later.get_pixelv(at)): changed+=1
		if changed>0:
			first.save_png(OUTPUT+"/"+id+"-fractional-%.2f-before.png"%phase)
			later.save_png(OUTPUT+"/"+id+"-fractional-%.2f-after.png"%phase)
		outside_changes+=changed
		sampled_pixels+=pixels.size()
		phases.append({"position":phase,"ring_pixels":pixels.size(),"dry_changes":changed})
	check(outside_changes==0,id+": dense dry shores remain fixed at fractional1.35x magnification")
	return {"source_ring_texels":ring.size(),"outside_screen_pixels":sampled_pixels,"outside_changes":outside_changes,"scale":1.35,"positions":phases}

func isolated(id: String) -> void:
	var viewport := SubViewport.new()
	viewport.world_2d=World2D.new()
	viewport.transparent_bg=true
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var landscape := Depths.new()
	landscape.configure(id)
	viewport.add_child(landscape)
	var sprite: Sprite2D=landscape.layers[2]
	var size := Vector2i(sprite.texture.get_size())
	viewport.size=size
	landscape.layers[0].hide()
	landscape.layers[1].hide()
	landscape.mist.hide()
	var surface: ShaderMaterial=landscape.image_materials[2]
	surface.set_shader_parameter("light_gain",0.0)
	surface.set_shader_parameter("water_glint",0.0)
	surface.set_shader_parameter("flow_glint",0.0)
	surface.set_shader_parameter("scene_clock",0.0)
	surface.set_shader_parameter("motion_gain",0.0)
	var first := await rendered(viewport)
	var mask := landscape.surface_mask.get_image() if is_instance_valid(landscape.surface_mask) else Image.create(1,1,false,Image.FORMAT_RGB8)
	var bounds: Vector4=landscape.surface_mask_bounds
	var outside: Array[Vector2i]=[]
	var inside: Array[Vector2i]=[]
	for y in range(0,size.y,17):
		for x in range(0,size.x,17):
			var at := Vector2i(x,y)
			var kind := kind_at(mask,bounds,size,at)
			if kind.r==0.0 and kind.g==0.0 and kind.b==0.0: outside.append(at)
	# Sample the whole cropped mask, including narrow spillways that would be
	# missed by a regular full-image grid. Keep a bounded distributed sample.
	var candidates: Array[Vector2i]=[]
	for y in range(0,mask.get_height(),3):
		for x in range(0,mask.get_width(),3):
			var kind := mask.get_pixel(x,y)
			if kind.r>0.1 or kind.g>0.1 or kind.b>0.1:
				var uv := Vector2(bounds.x,bounds.y)+(Vector2(x+0.5,y+0.5)/Vector2(mask.get_size()))*Vector2(bounds.z,bounds.w)
				candidates.append(Vector2i(clampi(floori(uv.x*size.x),0,size.x-1),clampi(floori(uv.y*size.y),0,size.y-1)))
	var stride := maxi(1,ceili(float(candidates.size())/512.0))
	for index in range(0,candidates.size(),stride): inside.append(candidates[index])
	var outside_changes := 0
	var water_changes := 0
	var flow_changes := 0
	var ice_changes := 0
	var ice_anchors := true
	var alpha_stable := true
	for seconds: float in [3.5,7.0]:
		surface.set_shader_parameter("scene_clock",seconds)
		surface.set_shader_parameter("motion_gain",1.0)
		var later := await rendered(viewport)
		for at: Vector2i in outside:
			if not same(first.get_pixelv(at),later.get_pixelv(at)): outside_changes+=1
		for at: Vector2i in inside:
			var kind := kind_at(mask,bounds,size,at)
			var before := first.get_pixelv(at)
			var after := later.get_pixelv(at)
			var changed := not same(before,after)
			if kind.r>0.1 and changed: water_changes+=1
			if kind.g>0.1 and changed: flow_changes+=1
			if kind.b>0.1:
				if changed: ice_changes+=1
				# Ice changes brightness uniformly, preserving source material hue.
				var before_sum := maxf(before.r+before.g+before.b,0.001)
				var after_sum := maxf(after.r+after.g+after.b,0.001)
				ice_anchors=ice_anchors and absf(before.r/before_sum-after.r/after_sum)<0.014 and absf(before.b/before_sum-after.b/after_sum)<0.014
			alpha_stable=alpha_stable and absf(before.a-after.a)<0.001
	check(outside_changes==0,id+": sampled buildings, banks and unmasked texture remain byte-stable")
	check(ice_anchors and alpha_stable,id+": solid surfaces retain texture hue and silhouette alpha")
	var occupied: Dictionary=Surfaces.mask_definition(id).get("occupied_pixels",{})
	if int(occupied.get("water",0))>0: check(water_changes>0,id+": painted water genuinely changes in the native renderer")
	if int(occupied.get("flow",0))>0: check(flow_changes>0,id+": painted falls genuinely change in the native renderer")
	if int(occupied.get("ice",0))>0: check(ice_changes>0,id+": anchored ice has real rendered light changes")
	check(landscape.surface_mask==Surfaces.texture(id) and surface.get_shader_parameter("surface_mask")==landscape.surface_mask,id+": production runtime reuses the authored mask resource")
	check(bounds==Surfaces.bounds(id) and surface.get_shader_parameter("surface_bounds")==bounds,id+": cropped masks retain original plate UV registration")
	surface.set_shader_parameter("motion_gain",0.0)
	var reduced := await rendered(viewport)
	check(reduced.get_data()==first.get_data(),id+": reduced surface effects restore the stationary plate")
	var mask_id := landscape.surface_mask.get_instance_id() if is_instance_valid(landscape.surface_mask) else 0
	var child_count := landscape.get_child_count()
	for tick in 120:
		landscape.update_view(Rect2(Vector2.ZERO,Vector2(size)),Rect2(Vector2.ZERO,Vector2(size)),float(tick)/30.0,false)
	landscape.mist.hide()
	check(landscape.get_child_count()==child_count and (landscape.surface_mask.get_instance_id() if is_instance_valid(landscape.surface_mask) else 0)==mask_id,id+": clock changes allocate no new mask resource or presentation node")
	var fractional := await fractional_edges(viewport,sprite,surface,mask,bounds,id)
	records.append({"id":id,"source_size":size,"mask_size":mask.get_size(),"mask_bounds":bounds,"outside_samples":outside.size()*2,"surface_samples":inside.size()*2,"outside_changes":outside_changes,"water_changes":water_changes,"flow_changes":flow_changes,"ice_changed_pixels":ice_changes,"ice_hue_stable":ice_anchors,"alpha_stable":alpha_stable,"fractional_edges":fractional})
	print("SURFACE ",id,": dry=",outside_changes," fractional_dry=",fractional.outside_changes," ice_changes=",ice_changes)
	await Cleanup.free_scene(viewport,self)

func view(game,at: Vector2,zoom: float,seconds: float,reduced: bool) -> void:
	game.camera.position=at
	game.camera.zoom=Vector2.ONE*zoom
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	game.weather.set_reduced_effects(reduced)
	var scenery: ScenarioScenery=game.scenery
	scenery.elapsed=seconds
	scenery._visible_rect=scenery.get_global_transform_with_canvas().affine_inverse()*scenery.get_viewport_rect()
	scenery.set_layered_enabled(true)
	# Other motion is held for a clear comparison of the painted surfaces.
	var depths= scenery.parallax_background
	depths.mist.hide()
	depths.image_materials[0].set_shader_parameter("scene_clock",8.0)
	depths.image_materials[0].set_shader_parameter("motion_gain",0.0)
	depths.image_materials[2].set_shader_parameter("light_gain",0.0)
	for frame in 2: await process_frame

func capture(name: String) -> void:
	var image := await rendered(root)
	check(image.save_png(OUTPUT+"/"+name+".png")==OK,"Native surface capture saved: "+name)

func movie(game,id: String,previous: ShaderMaterial,current: ShaderMaterial) -> void:
	await view(game,Vector2(720,450),1.0,0.0,false)
	var scenery: ScenarioScenery=game.scenery
	var depths=scenery.parallax_background
	for mode: String in ["before","after"]:
		depths.layers[2].material=previous if mode=="before" else current
		var start := Engine.get_process_frames()
		for frame in 180:
			var seconds := float(frame)/60.0
			scenery.elapsed=seconds
			depths.update_view(scenery.panorama_rect,scenery._visible_rect,seconds,false)
			depths.mist.hide()
			depths.image_materials[0].set_shader_parameter("motion_gain",0.0)
			depths.image_materials[0].set_shader_parameter("scene_clock",8.0)
			previous.set_shader_parameter("scene_clock",current.get_shader_parameter("scene_clock"))
			# A frozen prepared scene may skip drawing on an unchanged30Hz tick.
			# Advance exactly one60Hz process frame and explicitly request paint.
			depths.layers[2].queue_redraw()
			await process_frame
		check(Engine.get_process_frames()-start==180,id+": "+mode+" movie advances exactly180 engine frames")
		video_segments.append({"id":id,"mode":mode,"start_frame":start,"end_frame":Engine.get_process_frames(),"fps":60,"camera":Vector2(720,450),"zoom":1.0,"normal_scene_seconds":3.0})
	depths.layers[2].material=current

func gameplay(id: String) -> void:
	var game=load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
	game.rounds.running=false
	game.notice=""
	game.notice_time=0.0
	# Initialize HUD text/positions before holding its first gameplay frame.
	game.hud.chat_panel._process(0.0)
	game.hud._process(0.0)
	frozen(game)
	var old_shader := Shader.new()
	old_shader.code=FileAccess.get_file_as_string("res://artifacts/background-surfaces/baseline/parallax_valley.gdshader")
	var previous_catalog=load("res://artifacts/background-surfaces/baseline/parallax_catalog.gd")
	var old_definition: Dictionary=previous_catalog.definition(id)
	var depths=game.scenery.parallax_background
	var current_surface: ShaderMaterial=depths.image_materials[2]
	var previous_surface: ShaderMaterial
	for camera: Vector3 in [Vector3(720,-180,0.6),Vector3(720,450,1.0),Vector3(1100,160,2.2)]:
		await view(game,Vector2(camera.x,camera.y),camera.z,7.0,false)
		var old_surface:=current_surface.duplicate() as ShaderMaterial
		old_surface.shader=old_shader
		old_surface.set_shader_parameter("water_bounds",old_definition.water)
		old_surface.set_shader_parameter("water_enabled",old_definition.water.z>old_definition.water.x)
		old_surface.set_shader_parameter("green_water",bool(old_definition.get("green_water",false)))
		old_surface.set_shader_parameter("flow_bounds",old_definition.get("flow",Vector4.ZERO))
		old_surface.set_shader_parameter("light_gain",0.0)
		old_surface.set_shader_parameter("scene_clock",7.0)
		old_surface.set_shader_parameter("motion_gain",1.0)
		previous_surface=old_surface
		depths.layers[2].material=old_surface
		await capture("%s-%.1f-before"%[id,camera.z])
		depths.layers[2].material=current_surface
		for seconds: float in [0.0,7.0]:
			await view(game,Vector2(camera.x,camera.y),camera.z,seconds,false)
			await capture("%s-%.1f-after-t%.0f"%[id,camera.z,seconds])
		await view(game,Vector2(camera.x,camera.y),camera.z,7.0,true)
		await capture("%s-%.1f-reduced"%[id,camera.z])
	if "--video" in OS.get_cmdline_user_args(): await movie(game,id,previous_surface,current_surface)
	game.scenery.set_process(true)
	paused=true
	var before_pause: float=game.scenery.elapsed
	for frame in 5: await process_frame
	check(game.scenery.elapsed==before_pause,id+": actual gameplay pause freezes scene transport")
	paused=false
	game.scenery.set_process(false)
	await Cleanup.free_scene(game,self)

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("Native background surfaces require a display, --no-profile-save and --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.mode=Window.MODE_WINDOWED
	root.size=Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	RenderingServer.global_shader_parameter_set("beat_pulse",0.0)
	var only_id := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only-id="): only_id=argument.trim_prefix("--only-id=")
	if "--skip-mask-proof" not in OS.get_cmdline_user_args():
		for entry: Dictionary in ScenarioCatalog.environments(true):
			if only_id.is_empty() or only_id==str(entry.id): await isolated(str(entry.id))
	if "--only-mask-proof" not in OS.get_cmdline_user_args():
		for id: String in ["mountain_pass","abandoned_harbor","flooded_power_station","radar_highlands","storm_dam"]:
			if only_id.is_empty() or only_id==id: await gameplay(id)
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"mask_proof_skipped":"--skip-mask-proof" in OS.get_cmdline_user_args(),"prepared":"Original gameplay foreground depthplates with production mask texture/bounds; native source samples and dense fractional1.35x dry-edge samples at two phases when mask proof is requested. Actual solo levels with one character, waves and other presentation frozen; 1440x900; camera zoom0.6/1.0/2.2; previous original shader versus new shader at t0/t7 and reduced effects; sky, mist and lamps held; actual gameplay pause. Optional movie advances production background30Hz clock during180 actual60Hz process frames per3second segment; targeted sprite redraw; no music or synthetic surface pixels. A separately preserved completed mask-stage log is authoritative when --skip-mask-proof is supplied.","locations":records,"video_segments":video_segments}
	var report := FileAccess.open(OUTPUT+"/verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"\t"))
	print("BACKGROUND SURFACE NATIVE: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
