extends SceneTree
## Validate editor-reusable art regions and the independently animated dressing.

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var regions: Array[Rect2] = []
	check(LevelProp.SPRITE_RESOURCES.size() == 16, "All sixteen source props have separate texture resources")
	for path: String in LevelProp.SPRITE_RESOURCES:
		var texture = load(path)
		check(texture is AtlasTexture and texture.atlas != null, path + " loads as a complete atlas texture")
		if not texture is AtlasTexture or texture.atlas == null:
			continue
		var region: Rect2 = texture.region
		var bounds := Rect2(Vector2.ZERO, texture.atlas.get_size())
		check(region.has_area() and bounds.encloses(region), path + " lies inside its source image")
		check(not regions.has(region) and texture.filter_clip, path + " has its own clipped sprite region")
		regions.append(region)
	var dressing = load("res://scripts/level_dressing.gd").new()
	root.add_child(dressing)
	await process_frame
	check(dressing.manifest.size() == 28 and get_nodes_in_group("level_props").size() == 28, "Level creates twenty-eight independent prop nodes")
	var all_visible := true
	var no_collision := true
	var animated: Array[Node] = []
	for prop in get_nodes_in_group("level_props"):
		all_visible = all_visible and prop.artwork != null and prop.artwork.texture != null
		no_collision = no_collision and prop.find_children("*", "CollisionObject2D", true, false).is_empty()
		no_collision = no_collision and prop.find_children("*", "CollisionShape2D", true, false).is_empty()
		if prop.is_processing():
			animated.append(prop)
	check(all_visible, "Every placed prop has its own visible artwork node")
	check(no_collision, "Background props cannot obstruct worker routes")
	check(animated.size() == 13, "Thirteen fixtures animate independently")
	await create_timer(0.1).timeout
	var advanced := true
	for prop in animated:
		advanced = advanced and prop._clock > 0.0
		if prop.moving_part != null:
			advanced = advanced and not is_zero_approx(prop.moving_part.rotation)
		if prop.cable != null:
			advanced = advanced and prop.cable.points.size() == 4
	check(advanced, "Rotors, cables and indicator clocks advance during processing")
	var replacement := GradientTexture2D.new()
	replacement.width = 20
	replacement.height = 40
	var custom = load("res://scenes/level_prop.tscn").instantiate()
	custom.sprite_override = replacement
	custom.display_size = Vector2(80, 80)
	root.add_child(custom)
	check(custom.artwork.texture == replacement and custom._bounds.size == Vector2(40, 80), "An individual replacement texture preserves aspect ratio and desired size")
	print("LEVEL PROPS: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
