extends SceneTree
## GPU mask boundaries, integer source-texel motion and solid ice reflections.
const ShaderSource := preload("res://shaders/parallax_valley.gdshader")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/background-surfaces/gpu"
const SOURCE_SIZE := Vector2i(64,48)
const SCALE := 4
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func rendered(viewport: SubViewport) -> Image:
	for frame in 2:
		await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func pixel(image: Image, at: Vector2i) -> Color:
	return image.get_pixel(at.x*SCALE+2,at.y*SCALE+2)

func dominant(color: Color) -> int:
	return 0 if color.r>color.g and color.r>color.b else 1 if color.g>color.b else 2

func same_rgb(first: Color,second: Color) -> bool:
	return absf(first.r-second.r)<0.0041 and absf(first.g-second.g)<0.0041 and absf(first.b-second.b)<0.0041

func _run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or "--no-upnp" not in OS.get_cmdline_user_args():
		push_error("GPU surface proof requires a display, --no-profile-save and --no-upnp")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	RenderingServer.global_shader_parameter_set("beat_pulse",0.0)
	var source := Image.create(SOURCE_SIZE.x,SOURCE_SIZE.y,false,Image.FORMAT_RGBA8)
	var mask := Image.create(SOURCE_SIZE.x,SOURCE_SIZE.y,false,Image.FORMAT_RGBA8)
	mask.fill(Color(0,0,0,1))
	var water := Rect2i(4,24,24,16)
	var flow := Rect2i(34,12,12,22)
	var ice := Rect2i(50,30,10,12)
	var building := Rect2i(15,28,8,6)
	var mild_alpha := Rect2i(7,35,7,3)
	for y in SOURCE_SIZE.y:
		for x in SOURCE_SIZE.x:
			var at := Vector2i(x,y)
			var grain := float((x*7+y*3)%17)/255.0
			source.set_pixel(x,y,Color(.12+grain,.30+grain,.50+grain,1))
			if water.has_point(at): mask.set_pixel(x,y,Color(1,0,0,1))
			if flow.has_point(at): mask.set_pixel(x,y,Color(0,1,0,1))
			if ice.has_point(at):
				mask.set_pixel(x,y,Color(0,0,1,1))
				var palette := [Color(.80,.55,.60,1),Color(.55,.80,.60,1),Color(.55,.60,.80,1)]
				source.set_pixel(x,y,palette[(x+y*2)%3])
			if building.has_point(at):
				# Deliberately blue architecture inside the former water bounds.
				mask.set_pixel(x,y,Color(0,0,0,1))
				source.set_pixel(x,y,Color(.10+grain,.36+grain,.62+grain,1))
			if mild_alpha.has_point(at):
				var painted := source.get_pixel(x,y)
				painted.a=float(251+(x+y)%4)/255.0
				source.set_pixel(x,y,painted)
	mask.set_pixel(10,31,Color(0,0,0,1))
	source.set_pixel(10,31,Color(1,0,1,0))
	source.save_png(OUTPUT+"/source.png")
	mask.save_png(OUTPUT+"/mask.png")
	var viewport := SubViewport.new()
	viewport.size=SOURCE_SIZE*SCALE
	viewport.transparent_bg=true
	viewport.world_2d=World2D.new()
	viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sprite := Sprite2D.new()
	sprite.centered=false
	sprite.scale=Vector2.ONE*SCALE
	sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.texture=ImageTexture.create_from_image(source)
	var surface := ShaderMaterial.new()
	surface.shader=ShaderSource
	surface.set_shader_parameter("surface_mask",ImageTexture.create_from_image(mask))
	surface.set_shader_parameter("surface_enabled",true)
	surface.set_shader_parameter("water_glint",0.0)
	surface.set_shader_parameter("flow_glint",0.0)
	surface.set_shader_parameter("pixel_clarity",0.0)
	surface.set_shader_parameter("detail_strength",0.0)
	surface.set_shader_parameter("contour_strength",0.0)
	surface.set_shader_parameter("light_gain",0.0)
	surface.set_shader_parameter("scene_clock",0.0)
	surface.set_shader_parameter("motion_gain",0.0)
	sprite.material=surface
	viewport.add_child(sprite)
	var stationary := await rendered(viewport)
	stationary.save_png(OUTPUT+"/stationary.png")
	var measurements: Array[Dictionary]=[]
	var total_alpha_changes := 0
	for seconds: float in [0.0,1.25,3.5,7.0]:
		surface.set_shader_parameter("scene_clock",seconds)
		surface.set_shader_parameter("motion_gain",1.0)
		var moving := await rendered(viewport)
		moving.save_png(OUTPUT+"/motion-%.2f.png"%seconds)
		var outside_changes := 0
		var water_changes := 0
		var flow_changes := 0
		var ice_changes := 0
		var ice_anchors := true
		var ice_solid := true
		var water_texels := true
		var flow_texels := true
		var alpha_stable := true
		var mild_alpha_changes := 0
		for y in SOURCE_SIZE.y:
			for x in SOURCE_SIZE.x:
				var at := Vector2i(x,y)
				var kind := mask.get_pixel(x,y)
				var before := pixel(stationary,at)
				var after := pixel(moving,at)
				var changed := not same_rgb(before,after) or not is_equal_approx(before.a,after.a)
				alpha_stable=alpha_stable and is_equal_approx(before.a,after.a)
				if mild_alpha.has_point(at) and not same_rgb(before,after): mild_alpha_changes+=1
				if kind.r==0.0 and kind.g==0.0 and kind.b==0.0:
					if changed: outside_changes+=1
				elif kind.r>0.5:
					if changed: water_changes+=1
					var exact := false
					for offset in range(-3,4):
						var candidate := Vector2i(clampi(x+offset,0,SOURCE_SIZE.x-1),y)
						if candidate==at or mask.get_pixel(candidate.x,candidate.y).r>0.5:
							exact=exact or same_rgb(after,pixel(stationary,candidate))
					# Alpha's compositor scaling is tested separately. Opaque source
					# rows prove palette motion without conflating it with alpha.
					if not Rect2i(mild_alpha.position-Vector2i(3,0),mild_alpha.size+Vector2i(6,0)).has_point(at): water_texels=water_texels and exact
				elif kind.g>0.5:
					if changed: flow_changes+=1
					var exact := false
					for offset in range(-4,5):
						var candidate := Vector2i(x,clampi(y+offset,0,SOURCE_SIZE.y-1))
						if candidate==at or mask.get_pixel(candidate.x,candidate.y).g>0.5:
							exact=exact or same_rgb(after,pixel(stationary,candidate))
					flow_texels=flow_texels and exact
				else:
					if changed: ice_changes+=1
					ice_anchors=ice_anchors and dominant(before)==dominant(after)
					ice_solid=ice_solid and is_equal_approx(after.a,1.0) and absf(before.r-after.r)<0.09 and absf(before.g-after.g)<0.09 and absf(before.b-after.b)<0.09
		check(outside_changes==0,"Buildings, banks and alpha holes remain fixed at %.2f seconds"%seconds)
		check(water_changes>0 and water_texels,"Water shifts existing whole horizontal source texels at %.2f seconds"%seconds)
		check(flow_changes>0 and flow_texels,"Flow shifts existing whole vertical source texels at %.2f seconds"%seconds)
		check(ice_anchors and ice_solid,"Ice retains solid alpha and fixed material coordinates at %.2f seconds"%seconds)
		check(alpha_stable,"Alpha251–254 water preserves its original silhouette at %.2f seconds"%seconds)
		total_alpha_changes+=mild_alpha_changes
		measurements.append({"seconds":seconds,"outside_changes":outside_changes,"water_changes":water_changes,"flow_changes":flow_changes,"ice_changes":ice_changes,"alpha_stable":alpha_stable,"alpha251_254_changes":mild_alpha_changes})
	check(total_alpha_changes>0,"Alpha251–254 water receives actual motion during the complete swell")
	surface.set_shader_parameter("motion_gain",0.0)
	var reduced := await rendered(viewport)
	check(reduced.get_data()==stationary.get_data(),"Reduced effects disables all UV motion and ice glints")
	surface.set_shader_parameter("scene_clock",21.0)
	var later_reduced := await rendered(viewport)
	check(later_reduced.get_data()==reduced.get_data(),"Reduced effects remains static as caller time advances")
	surface.set_shader_parameter("motion_gain",1.0)
	surface.set_shader_parameter("scene_clock",3.5)
	var held := await rendered(viewport)
	for frame in 8: await process_frame
	var later_held := await rendered(viewport)
	check(held.get_data()==later_held.get_data(),"An unchanged caller clock freezes all shader animation")
	var result := {"checks":checks,"failures":failures,"renderer":RenderingServer.get_video_adapter_name(),"prepared":"64x48 synthetic painted blue surface at4x nearest scale; exact RGB effect mask; blue building island inside water, alpha hole, separate verticalflow and colored solidice; light/detail effects disabled; explicit scene time and reduced effects", "source_size":SOURCE_SIZE,"measurements":measurements}
	var report := FileAccess.open(OUTPUT+"/verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify(result,"\t"))
	await Cleanup.free_scene(viewport,self)
	print("BACKGROUND SURFACE GPU: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
