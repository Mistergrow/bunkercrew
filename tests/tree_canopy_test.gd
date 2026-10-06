extends SceneTree
## Original bitmap masks and the actual bent tree shader must agree about
## foliage origins. No rendered videos or performance benchmark is produced.
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const WORLDS := {"dead":"ash_foundry","deciduous":"flooded_power_station","conifer":"mountain_pass","oak":"overgrown_steelworks","birch":"overgrown_steelworks","spruce":"frozen_rail_yard"}
const OUTPUT := "res://artifacts/scenery-props/canopy/"
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	print("TREE CANOPY %s: %s" % ["PASS" if ok else "FAIL",label])
	if not ok:
		failures += 1
		push_error(label)

func frames(count: int=3) -> void:
	for index in count:
		await process_frame
		await physics_frame

func source_valid(image: Image,point: Vector2,family: String) -> bool:
	var color := image.get_pixelv(Vector2i(point))
	if color.a<220.0/255.0: return false
	if family=="dead": return true
	var hue := color.h*360.0
	if family=="broadleaf":
		return hue>=42 and hue<=165 and color.s>=.15 and color.g>=color.r*.86 and color.g>=color.b*1.10 and color.v>=.10
	return hue>=60 and hue<=195 and color.s>=.10 and color.g>=color.r and color.g>=color.b*.94 and color.v>=.075

func render_check(props,entry: Dictionary) -> void:
	var original: MeshInstance2D = props._tree_by_index[int(entry.index)]
	var view := SubViewport.new()
	view.size = Vector2i(512,320)
	view.transparent_bg = true
	view.world_2d = World2D.new()
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var offset := Vector2(256,280)-Vector2(entry.position)
	root.add_child(view)
	view.canvas_transform = Transform2D(0,offset)
	var tree := MeshInstance2D.new()
	tree.mesh = original.mesh
	tree.texture = original.texture
	tree.material = original.material.duplicate()
	tree.position = original.position
	tree.scale = original.scale
	tree.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(tree)
	var material := tree.material as ShaderMaterial
	var supported := 0
	var total := 0
	for time: float in [0.0,.83,2.71,4.19]:
		material.set_shader_parameter("wind_clock",time)
		await RenderingServer.frame_post_draw
		var image := view.get_texture().get_image()
		for index in entry.emit_points.size():
			var at: Vector2 = props.canopy_point(entry,index,time)+offset
			var opaque := false
			# Point rasterization and nearest texture lookup can select either
			# adjacent pixel. A 3x3 footprint permits that single-pixel rounding.
			for dx in range(-1,2):
				for dy in range(-1,2):
					var pixel := Vector2i(at.floor())+Vector2i(dx,dy)
					if Rect2i(Vector2i.ZERO,view.size).has_point(pixel) and image.get_pixelv(pixel).a>.45: opaque = true
			if opaque: supported += 1
			total += 1
		if time==0.0 or time==2.71: image.save_png(OUTPUT+str(entry.tree)+"-bent-%.2fs.png" % time)
	check(supported>=total*.97,"%s mapped canopy follows real shader alpha at four times: %d/%d origins on foliage/bark" % [entry.tree,supported,total])
	view.queue_free()
	await process_frame

func run() -> void:
	root.size = Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var rendered := DisplayServer.get_name()!="headless"
	for kind: String in WORLDS:
		var data := Catalog.tree_metadata(kind)
		var points := Catalog.canopy_points(kind)
		var image: Image = load(Catalog.TREE_PATHS[kind]).get_image()
		if image.is_compressed(): image.decompress()
		var valid := true
		var trunk_clear := true
		var cells: Dictionary = {}
		var bounds := Rect2(points[0],Vector2.ZERO)
		for index in points.size():
			var point := points[index]
			valid = valid and source_valid(image,point,str(data.family))
			bounds = bounds.expand(point)
			cells[str(data.canopy_cells[index])] = true
			for segment in data.trunk.size()-1:
				var from := Vector2(data.trunk[segment][0],data.trunk[segment][1])
				var to := Vector2(data.trunk[segment+1][0],data.trunk[segment+1][1])
				trunk_clear = trunk_clear and point.distance_to(Geometry2D.get_closest_point_to_segment(point,from,to))>float(data.trunk_radius)*(1-segment*.15)
			trunk_clear = trunk_clear and point.y<float(data.root[1])*(.84 if data.family=="dead" else .88)
		check(points.size()>=80 and points.size()<=200 and valid,"%s metadata contains %d opaque family-matched original pixels" % [kind,points.size()])
		check(trunk_clear,"%s emitters exclude measured trunk corridor and lower root area" % kind)
		check(cells.size()>=120 and bounds.size.x>float(data.canopy_bounds[2])*.8 and bounds.size.y>float(data.canopy_bounds[3])*.8,"%s broad crown coverage across %d occupied cells" % [kind,cells.size()])
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene = game
		game.start_scenario(1,{"environment":WORLDS[kind],"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.rounds.running = false
		await frames()
		var props = game.scenery.props_layer
		var found: Dictionary = {}
		for entry: Dictionary in props.entries:
			if entry.kind=="tree" and entry.tree==kind and not entry.optional: found = entry; break
		check(not found.is_empty() and bool(found.get("displayed",false)),"%s species appears in its actual normal-camera scenario" % kind)
		if found.is_empty():
			await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
			continue
		check(found.family==data.family and found.emit_points.size()==points.size(),"%s actual scene caches full emission metadata and reaction family" % kind)
		game.process_mode = Node.PROCESS_MODE_DISABLED
		if rendered: await render_check(props,found)
		await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	check(Catalog.TREE_ROOTS.deciduous==Vector2(623,1050) and Catalog.TREE_ROOTS.conifer==Vector2(614,1135) and Catalog.TREE_ROOTS.dead==Vector2(839,1030),"Existing three source root anchors remain unchanged")
	check(not Catalog.layout("unknown_environment",90,730).is_empty(),"Unknown environment retains a valid deterministic fallback")
	print("TREE CANOPY: %d/%d checks passed%s" % [checks-failures,checks," (GPU projection included)" if rendered else ""])
	quit(1 if failures else 0)
