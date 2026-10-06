extends SceneTree
## Splitting the same world deposit field into mineable cells must not add seams.
const Deposits := preload("res://scripts/mineral_deposits.gd")
var checks := 0
var failures := 0

class Swatches extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,914,514),Color("111b20"))
		Art.text(self,Vector2(36,40),"MINERALISCHE EINLAGERUNGEN / ECHTE ABBAUZELLEN",16,Art.LIGHT)
		Art.text(self,Vector2(36,63),"Vorbereitete 6 × 3 Felder · 1,75× vergrößert · durchgehende Weltkoordinaten",10,Art.MUTED)
		for index in 4:
			Art.text(self,Vector2(50+(index%2)*430,105+floori(index/2.0)*200),["EISENERZ","KALKSTEIN","WOLFRAMERZ","ERDREICH"][index],13,Art.AMBER)

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
	print("MINERAL %s: %s" % ["PASS" if value else "FAIL",label])

func area(points: PackedVector2Array) -> float:
	var sum := 0.0
	for index in points.size():
		var a := points[index]
		var b := points[(index+1)%points.size()]
		sum += a.x*b.y-b.x*a.y
	return absf(sum)*.5

func run() -> void:
	for kind: String in Deposits.PALETTES:
		for origin in [Vector2(-96,-144),Vector2(272,485),Vector2(983,1222)]:
			var bounds := Rect2(origin,Vector2(192,144))
			var whole := Deposits.facets(kind,bounds)
			check(not whole.is_empty() and whole == Deposits.facets(kind,bounds),kind+" world deposits repeat deterministically "+str(origin))
			var whole_area := 0.0
			for facet in whole:
				whole_area += area(facet.points)
			var cell_area := 0.0
			var contained := true
			var triangulable := true
			var maximum_facets := 0
			for row in 3:
				for column in 4:
					var cell := Rect2(origin+Vector2(column,row)*48,Vector2(48,48))
					var pieces := Deposits.facets(kind,cell)
					maximum_facets = maxi(maximum_facets,pieces.size())
					for facet in pieces:
						cell_area += area(facet.points)
						triangulable = triangulable and not Geometry2D.triangulate_polygon(facet.points).is_empty()
						for point: Vector2 in facet.points:
							contained = contained and cell.grow(.01).has_point(point)
			check(contained and triangulable,kind+" shards remain drawable and inside individual removable cells")
			check(absf(whole_area-cell_area)<.02,kind+" cell partition preserves all deposit area without gaps/duplicates (difference %.5f)"%absf(whole_area-cell_area))
			check(maximum_facets<=70,kind+" geometry per48pxcell stays bounded: "+str(maximum_facets))
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless":
		root.size = Vector2i(320,180)
		root.set_flag(Window.FLAG_NO_FOCUS,true)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(2560,1440)
		viewport.size_2d_override = Vector2i(914,514)
		viewport.size_2d_override_stretch = true
		viewport.world_2d = World2D.new()
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var swatches := Swatches.new()
		viewport.add_child(swatches)
		for index in 4:
			var group := Node2D.new()
			group.position = Vector2(50+(index%2)*430,120+floori(index/2.0)*200)
			swatches.add_child(group)
			for row in 3:
				for column in 6:
					var block := MineBlock.new()
					block.kind = ["ore","limestone","tungsten","sand"][index]
					block.position = Vector2(column,row)*48+Vector2(24,24)
					group.add_child(block)
		for unused in 8:
			await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/style-layout"))
		check(viewport.get_texture().get_image().save_png("res://artifacts/style-layout/minerals.png")==OK,"Actual cells render at QHD")
		await preload("res://tests/scene_cleanup.gd").free_scene(viewport,self)
	print("MINERAL DEPOSITS %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
