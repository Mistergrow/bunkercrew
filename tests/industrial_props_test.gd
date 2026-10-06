extends SceneTree
## Actual atlas joints, climate pressure, damage shape and rendered source alpha.
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const PropPainter := preload("res://scripts/scenario_prop_art.gd")
const Industrial := preload("res://scripts/industrial_prop_art.gd")
const Damage := preload("res://scripts/scenery_damage.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/frontline-weather/"
var checks := 0
var failures := 0

class Probe extends Node2D:
	var entry: Dictionary
	var clock := 0.0
	var strength := 1.0
	func _draw() -> void: PropPainter.draw(self,entry,clock,1.0,strength)

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks += 1
	print("INDUSTRIAL PROPS %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok: failures += 1; push_error(label)
func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child in node.get_children(): freeze(child)
func entry_for(props,kind: String) -> Dictionary:
	for entry: Dictionary in props.entries:
		if entry.kind==kind: return entry
	return {}
func difference(a: Image,b: Image,rect: Rect2i) -> int:
	var changes := 0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var c := a.get_pixel(x,y)
			var d := b.get_pixel(x,y)
			if maxf(absf(c.a-d.a),maxf(absf(c.r-d.r),maxf(absf(c.g-d.g),absf(c.b-d.b))))>.035: changes += 1
	return changes
func opaque_near(image: Image,point: Vector2) -> bool:
	for dx in range(-2,3):
		for dy in range(-2,3):
			var p := Vector2i(point.round())+Vector2i(dx,dy)
			if Rect2i(Vector2i.ZERO,image.get_size()).has_point(p) and image.get_pixelv(p).a>.5: return true
	return false
func image_of(view: Viewport) -> Image:
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image

func isolated(entry: Dictionary) -> void:
	var view := SubViewport.new()
	view.size = Vector2i(280,190)
	view.transparent_bg = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var probe := Probe.new()
	probe.position = Vector2(100,160)
	probe.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	probe.entry = entry.duplicate()
	probe.entry.position = Vector2.ZERO
	probe.entry.broken = false
	probe.entry.burning = false
	probe.entry.charred = false
	probe.entry.phase = .7
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/perimeter_pixel.gdshader")
	probe.material = material
	view.add_child(probe)
	var first := await image_of(view)
	probe.clock = 2.0
	probe.queue_redraw()
	var second := await image_of(view)
	first.save_png(OUTPUT+entry.kind+"-alpha-gust-0s.png")
	second.save_png(OUTPUT+entry.kind+"-alpha-gust-2s.png")
	var visible := 0
	var underground := 0
	var fringe := 0
	for y in view.size.y:
		for x in view.size.x:
			var color := first.get_pixel(x,y)
			if color.a>.01:
				visible += 1
				if y>=160: underground += 1
				if x<35 or x>195 or y<40: fringe += 1
	check(visible>120 and underground==0 and fringe==0,"%s textured silhouette has %d native pixels, no image card and no pixels below its ground anchor" % [entry.kind,visible])
	var base_changes := difference(first,second,Rect2i(45,151,145,9))
	check(base_changes==0,"%s rigid feet remain at identical pixels during animation" % entry.kind)
	if entry.kind=="windsock":
		check(opaque_near(first,Vector2(131,70)),"Actual windsock mouth meets the painted mast hanging ring")
		probe.strength = .06
		probe.clock = 0
		probe.queue_redraw()
		var calm := await image_of(view)
		probe.clock = 2.0
		probe.queue_redraw()
		var calm_later := await image_of(view)
		calm.save_png(OUTPUT+"windsock-alpha-calm-0s.png")
		calm_later.save_png(OUTPUT+"windsock-alpha-calm-2s.png")
		var gust_changes := difference(first,second,Rect2i(122,51,80,60))
		var calm_changes := difference(calm,calm_later,Rect2i(122,51,80,60))
		check(gust_changes>25 and gust_changes>calm_changes*2,"Cloth moves clearly in a gust and is quiet in a lull (%d versus %d changed pixels)" % [gust_changes,calm_changes])
	elif entry.kind=="cable":
		var attached := true
		for x: float in [-42.5,-27.5,27.5,42.5]: attached = attached and opaque_near(first,Vector2(100+x,65))
		check(attached,"Both cables terminate on the painted insulators, with four fixed attachment points")
	elif entry.kind=="pipe":
		check(opaque_near(first,Vector2(124,117)),"Pipe water originates at the painted outlet")
	view.queue_free()
	await process_frame

func run() -> void:
	root.size = Vector2i(2560,1440)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rendered := DisplayServer.get_name()!="headless"
	var attachment_fixed := true
	var pressure_stable := true
	for tick in 100:
		var time := tick*.1
		var gust := PropPainter.wind(time,.7,1)
		var joints := Industrial.windsock_points(time,.7,gust,1,1)
		attachment_fixed = attachment_fixed and joints[0]==Vector2(31,-90)
		pressure_stable = pressure_stable and joints[-1].x==85.0
	check(attachment_fixed and pressure_stable,"A sustained gust keeps cloth inflated and its mouth pinned through ten seconds of flutter")
	var calm := Industrial.windsock_points(0,.7,.02,1,.06)
	check(calm[-1].x<57 and calm[-1].y> -70,"Calm cloth hangs downward beside its mast instead of remaining inflated")
	for id: String in ["flooded_power_station","ash_foundry","mountain_pass"]:
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.running = false
		game.rounds.set_process(false)
		for frame in 6: await physics_frame
		freeze(game)
		game.notice_time = 0
		game.camera.position_smoothing_enabled = false
		game.camera.position = Vector2(760,450)
		game.camera.zoom = Vector2.ONE
		game.camera.force_update_scroll()
		var props = game.scenery.props_layer
		var kinds: Array = ["pipe","cable"] if id=="flooded_power_station" else ["windsock"]
		for kind: String in kinds:
			var entry := entry_for(props,kind)
			check(not entry.is_empty(),id+" installs its actual "+kind+" from the native world catalog")
			if entry.is_empty(): continue
			var shape: Dictionary = Damage._shape(entry,2.0,1.0,1.0)
			if kind=="windsock":
				var joints := Industrial.windsock_points(2.0,float(entry.phase),PropPainter.wind(2.0,float(entry.phase),1.0),1.0,1.0)
				var match_geometry: bool = shape.segments.size()==8
				for joint in 8: match_geometry = match_geometry and Vector2(shape.segments[joint].from)==joints[joint] and Vector2(shape.segments[joint].to)==joints[joint+1]
				check(match_geometry,"Actual windsock damage segments follow the same eight rendered cloth joints")
			if rendered and (id=="flooded_power_station" or id=="mountain_pass"): await isolated(entry)
		if rendered:
			for state: String in ["calm","gust"]:
				game.weather.elapsed = 50.0 if state=="calm" else 3.0
				props.elapsed = 2.0
				props._material_tick = -1
				props._process(.05)
				var image := await image_of(root)
				check(image.get_size()==Vector2i(2560,1440),id+" "+state+" uses a true QHD viewport")
				image.save_png(OUTPUT+id+"-props-"+state+".png")
		if not await Cleanup.free_scene(game,self): failures += 1
	print("INDUSTRIAL PROPS: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
