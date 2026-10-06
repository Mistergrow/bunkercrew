extends SceneTree
## Real GPU pixel transitions: fractional movement, bounded detail, alpha edges.
const SHADER := preload("res://shaders/background_sampling.gdshader")
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func frame_image(viewport: SubViewport) -> Image:
	for frame in 2:await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():quit(2);return
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(128,96);viewport.world_2d=World2D.new()
	viewport.transparent_bg=true;viewport.disable_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var source:=Image.create(16,16,false,Image.FORMAT_RGBA8)
	source.fill(Color(.25,.25,.25,1))
	for x in range(8,16):
		for y in 16:source.set_pixel(x,y,Color(.75,.75,.75,1))
	var sprite:=Sprite2D.new()
	sprite.centered=false;sprite.scale=Vector2.ONE*4
	sprite.texture=ImageTexture.create_from_image(source)
	var surface:=ShaderMaterial.new();surface.shader=SHADER
	sprite.material=surface;viewport.add_child(sprite)
	var measurements:={}
	for mode in ["point","crisp"]:
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST if mode=="point" else CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		surface.set_shader_parameter("pixel_clarity",0.0 if mode=="point" else 1.0)
		surface.set_shader_parameter("detail_strength",0.0 if mode=="point" else 1.0)
		surface.set_shader_parameter("sample_radius",2.25)
		surface.set_shader_parameter("contour_strength",0.0 if mode=="point" else .22)
		var samples: Array[float]=[]
		for index in 17:
			sprite.position=Vector2(16+float(index)/16,16)
			var rendered:=await frame_image(viewport)
			samples.append(rendered.get_pixel(48,32).r)
			if mode=="crisp":
				var bounded:=true
				for x in range(40,56):
					var value:=rendered.get_pixel(x,32).r
					bounded=bounded and value>=.247 and value<=.754
				check(bounded,"Sharpened edge stays inside its local grey palette at subpixel offset %d"%index)
		var largest:=0.0
		for index in range(1,samples.size()):largest=maxf(largest,absf(samples[index]-samples[index-1]))
		measurements[mode]={"samples":samples,"largest_change":largest}
	check(float(measurements.crisp.largest_change)<float(measurements.point.largest_change)*.5,"Fractional motion has smaller pixel jumps than point sampling")
	check(absf(float(measurements.crisp.samples[0])-float(measurements.crisp.samples[-1]))>.4,"Edge actually traverses the sampled screen pixel")
	source.fill(Color(1,0,1,0))
	for x in range(8,16):
		for y in 16:source.set_pixel(x,y,Color(.2,.4,.6,1))
	sprite.texture=ImageTexture.create_from_image(source);sprite.position=Vector2(16.3,16)
	surface.set_shader_parameter("detail_strength",0.0)
	surface.set_shader_parameter("contour_strength",0.0)
	var unsharpened: Image=await frame_image(viewport)
	surface.set_shader_parameter("detail_strength",1.0)
	surface.set_shader_parameter("contour_strength",.22)
	var sharpened: Image=await frame_image(viewport)
	check(unsharpened.get_data()==sharpened.get_data(),"Hidden alpha colors create no sharpening halo around a transparent silhouette")
	var output:=FileAccess.open("res://artifacts/all-level-layers/sharpness/verification.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared":"Isolated GPU shader, 4x texture magnification, seventeen 1/16-screen-pixel offsets, opaque grey transition and a transparent magenta/blue silhouette.","measurements":measurements},"  "));output.close()
	await Cleanup.free_scene(viewport,self)
	print("BACKGROUND SAMPLING: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
