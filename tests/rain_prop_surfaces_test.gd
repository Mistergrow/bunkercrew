extends SceneTree
## Weather-only geometry must follow visible artwork, including transparent
## margins and live weapon transforms, without adding gameplay obstacles.
var checks := 0
var failures := 0
func _initialize(): run.call_deferred()
func check(value: bool, label: String):
	checks += 1
	print("RAIN PROPS ","PASS " if value else "FAIL ",label)
	if not value: failures += 1
func contact(segments: Array[Dictionary], from: Vector2, to: Vector2, owner: Node) -> Dictionary:
	var closest := {}
	var distance := INF
	for segment in segments:
		if segment.collider!=owner: continue
		var point: Variant = Geometry2D.segment_intersects_segment(from,to,segment.from,segment.to)
		if point!=null and from.distance_squared_to(point)<distance:
			distance = from.distance_squared_to(point)
			closest = segment.duplicate()
			closest.position = point
	return closest
func run():
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.start(1)
	game.rounds.set_process(false)
	game.dressing.set_process(false)
	var helper := WeatherPropSurfaces.new()
	helper.game = game
	helper.weather = game.weather
	game.add_child(helper)
	var barrel = game.dressing.get_node("RoofBarrel")
	var sprite: Sprite2D = barrel.artwork
	var image := sprite.texture.get_image()
	if image.is_compressed(): image.decompress()
	var middle := floori(image.get_width()/2.0)
	var first := -1
	for y in image.get_height():
		if image.get_pixel(middle,y).a>=WeatherPropSurfaces.ALPHA_THRESHOLD:
			first=y
			break
	var drawn_top := sprite.to_global(Vector2(0,first-image.get_height()*0.5))
	var segments := helper.rain_segments()
	var hit := contact(segments,drawn_top-Vector2(0,50),drawn_top+Vector2(0,70),barrel)
	check(not hit.is_empty() and hit.position.distance_to(drawn_top)<2,"Rain contacts the real barrel pixels instead of transparent atlas margin")
	check(not hit.is_empty() and hit.normal.y<-.5 and hit.material=="metal","Barrel contact supplies an upward metallic surface")
	var before: Vector2 = hit.position
	barrel.position += Vector2(17,-3)
	helper.invalidate()
	hit = contact(helper.rain_segments(),drawn_top+Vector2(17,-53),drawn_top+Vector2(17,67),barrel)
	check(not hit.is_empty() and hit.position.distance_to(before+Vector2(17,-3))<0.1,"Parallax prop movement carries its rain outline with it")
	barrel.hide()
	helper.invalidate()
	check(helper.rain_segments().all(func(segment): return segment.collider!=barrel),"Hidden decorations do not create invisible rain cover")
	barrel.show()
	var gun: RoofTurret = game.turret
	gun.barrel.rotation = -.6
	helper.invalidate()
	var first_contour := helper.rain_segments().filter(func(segment):return segment.collider==gun)
	gun.barrel.rotation = .3
	gun.recoil = 5.0
	helper.invalidate()
	var second_contour := helper.rain_segments().filter(func(segment):return segment.collider==gun)
	check(not first_contour.is_empty() and first_contour!=second_contour,"Gun contour follows actual aiming and recoil transforms")
	check(second_contour.all(func(segment):return segment.material=="metal" and segment.weather_prop and is_equal_approx(segment.normal.length(),1.0)),"Gun contacts retain normalized metallic surface normals")
	check(helper.get_child_count()==0,"Weather helper adds no gameplay collision bodies")
	var supply = get_nodes_in_group("supplies").filter(func(node):return node.kind=="ammo")[0]
	hit = contact(helper.rain_segments(),supply.global_position-Vector2(0,90),supply.global_position,supply)
	check(not hit.is_empty() and is_equal_approx(hit.position.y,supply.global_position.y-38),"Ammunition crate top receives rain even without gameplay collision")
	check(helper._contours.size()<=18,"Texture silhouettes are cached once per unique atlas region")
	game.weather.set_process(false)
	game.weather.elapsed=0.0
	helper.invalidate()
	var flag := contact(helper.rain_segments(),Vector2(137,150),Vector2(137,220),game.weather)
	game.weather.elapsed=0.3
	helper.invalidate()
	var moved_flag := contact(helper.rain_segments(),Vector2(137,150),Vector2(137,220),game.weather)
	check(not flag.is_empty() and flag.material=="cloth" and flag.position!=moved_flag.position,"Wind-driven cloth carries its weather contact with the waving flag")
	await preload("res://tests/scene_cleanup.gd").free_scene(game,self)
	print("RAIN PROPS: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
