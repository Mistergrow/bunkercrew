extends SceneTree
## Pixel comparisons on the real Compatibility renderer, using authored test
## swatches to separate material changes from lighting, weather and gameplay.
var checks := 0
var failures := 0
var viewport: SubViewport
var art: Sprite2D

func _initialize() -> void: call_deferred("run")

func check(ok: bool,label: String) -> void:
	checks += 1
	print("SHADER %s: %s"%["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func frame() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	result.convert(Image.FORMAT_RGBA8)
	return result

func changes(a: Image,b: Image,rect: Rect2i,channels := 3) -> int:
	var count := 0
	var first := a.get_data()
	var second := b.get_data()
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var at := (y*a.get_width()+x)*4
			for channel in channels:
				if first[at+channel]!=second[at+channel]:
					count += 1
					break
	return count

func make_art() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(160,96)
	viewport.transparent_bg = true
	viewport.world_2d = World2D.new()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	art = Sprite2D.new()
	art.centered = false
	art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(art)
	var image := Image.create(160,96,false,Image.FORMAT_RGBA8)
	var palette := [Color("a24c27"),Color("626c71"),Color("f4f5f3"),Color("3d7773")]
	for y in 96:
		for x in 160:
			var color: Color = palette[floori(x/40.0)]
			color *= 1.0 if x%4<2 else .85
			color.a = 0.0 if x%23<3 else (.5 if y>=72 else 1.0)
			image.set_pixel(x,y,color)
	art.texture = ImageTexture.create_from_image(image)

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Shader regression requires a graphical renderer")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/shaders"))
	make_art()
	var full := Rect2i(Vector2i.ZERO,viewport.size)
	var original := await frame()
	var wet := ShaderMaterial.new()
	wet.shader = preload("res://shaders/actor_wet.gdshader")
	art.material = wet
	wet.set_shader_parameter("wet_clock",3.0)
	var dry := await frame()
	check(changes(original,dry,full,4)==0,"Dry material preserves every original RGBA pixel")
	art.set_instance_shader_parameter("wetness",1.0)
	wet.set_shader_parameter("metal",1.0)
	wet.set_shader_parameter("art_top",24.0)
	wet.set_shader_parameter("opaque_only",true)
	var soaked := await frame()
	check(changes(original,soaked,Rect2i(0,0,160,24),4)==0,"Art boundary keeps labels above the actor unchanged")
	check(changes(original,soaked,Rect2i(0,72,160,24),4)==0,"Translucent aiming markers remain unchanged with opaque-only wet shading")
	var alpha_same := true
	for y in 96:
		for x in 160:
			if original.get_pixel(x,y).a!=soaked.get_pixel(x,y).a: alpha_same = false
	check(alpha_same,"Wet material preserves all sprite alpha and silhouette pixels")
	check(changes(original,soaked,Rect2i(40,24,40,48))>1000,"Exposed steel receives visible material darkening")
	wet.set_shader_parameter("wet_clock",8.0)
	var later := await frame()
	check(changes(soaked,later,Rect2i(40,24,40,48))>60,"Wet steel flecks and rivulets animate on local art pixels")
	original.save_png("res://artifacts/shaders/material-dry.png")
	soaked.save_png("res://artifacts/shaders/material-wet.png")
	var water := ShaderMaterial.new()
	water.shader = preload("res://shaders/scenario_sky.gdshader")
	water.set_shader_parameter("sky_cutoff",.12)
	water.set_shader_parameter("water_bounds",Vector4(.1,.5,.8,.4))
	water.set_shader_parameter("edge_fade",.001)
	water.set_shader_parameter("sky_clock",1.0)
	art.material = water
	var calm := await frame()
	water.set_shader_parameter("sky_clock",4.6)
	var wave := await frame()
	check(changes(calm,wave,Rect2i(0,15,160,33))==0,"Water animation keeps solid architecture above the authored water unchanged")
	check(changes(calm,wave,Rect2i(0,48,15,48))==0 and changes(calm,wave,Rect2i(145,48,15,48))==0,"Water animation cannot leak past either shore")
	check(changes(calm,wave,Rect2i(18,50,124,34))>500,"Authored water reflections visibly move")
	water.set_shader_parameter("water_glint",0.0)
	var no_glint := await frame()
	check(changes(wave,no_glint,Rect2i(18,50,124,34))>100,"Bounded ripple crests add restrained reflected highlights")
	var cloud := ShaderMaterial.new()
	cloud.shader = preload("res://shaders/scenario_cloud.gdshader")
	cloud.set_shader_parameter("cloud_tint",Color(1,1,1,.6))
	art.material = cloud
	var full_cloud := await frame()
	art.modulate.a = .5
	var faded_cloud := await frame()
	check(absf(faded_cloud.get_pixel(60,30).a-full_cloud.get_pixel(60,30).a*.5)<.01,"Cloud material respects CanvasItem opacity for fade and depth control")
	check(faded_cloud.get_pixel(0,30).a==0.0,"Cloud overlap preserves transparent seam edges")
	await preload("res://tests/scene_cleanup.gd").free_scene(viewport,self)
	print("SHADER MATERIALS: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
