extends SceneTree
## Texture, biome, anchoring and culling checks; no gameplay or network starts.
const Horizon := preload("res://scripts/distant_horizon.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
class SceneryFixture extends Node2D:
	var environment_id := "sector07"
	var data: Dictionary = {}
	var panorama_rect := Rect2(-144,-64,1728,576)
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func _run() -> void:
	var scenery := SceneryFixture.new()
	root.add_child(scenery)
	var horizon := Horizon.new()
	scenery.add_child(horizon)
	var atlas := load(Horizon.ATLAS_PATH) as Texture2D
	check(atlas!=null and atlas.get_size()==Vector2(1774,887),"Original RGBA landscape atlas is imported at its authored size")
	var picture := atlas.get_image()
	if picture.is_compressed(): picture.decompress()
	check(picture.get_pixel(100,20).a<.05,"Sky above the terrain remains transparent")
	for region: Rect2 in Horizon.ATLAS_REGIONS:
		check(Rect2(Vector2.ZERO,atlas.get_size()).encloses(region),"Atlas source stays inside the image")
		var shades: Dictionary = {}
		var continuous := true
		for x in range(0,int(region.size.x),9):
			var pixel := picture.get_pixel(x,int(region.end.y)-3)
			continuous = continuous and pixel.a>.5
			shades[pixel.to_html(false)] = true
		check(continuous,"Terrain strip connects to its full-width baseline")
		check(shades.size()>24,"Each landscape strip retains detailed shaded pixels")
	var palettes: Dictionary = {}
	var wide := Rect2(-2480,-1280,6400,3600)
	for entry: Dictionary in ScenarioCatalog.environments():
		scenery.environment_id = str(entry.id)
		scenery.data = entry
		horizon.configure(scenery)
		horizon.update_view(wide,.25)
		check(horizon.layers.size()==3,entry.id+" has three textured distance layers")
		palettes[horizon.profile.shadow] = true
		var water: Array = entry.get("water_regions",[])
		var expected_base := roundf(-64.0+float(water[0][1])*576.0) if not water.is_empty() else Horizon.LAND_BASE
		check(is_equal_approx(horizon.baseline,expected_base),entry.id+" landscape joins the land or exact water surface")
		var count := 0
		for depth in 3:
			var span := horizon.visible_blocks(depth,wide)
			count += span.y-span.x+1
			var block := horizon.block_rect(depth,-2)
			check(is_equal_approx(block.end.y,expected_base),entry.id+" terrain feet share their surface baseline")
			horizon.update_view(Rect2(-400,-300,3200,1800),.45)
			check(horizon.block_rect(depth,-2)==block,entry.id+" atlas landmarks remain fixed when camera pans and zooms")
			var culled := horizon.visible_blocks(depth,Rect2(-2500,600,6500,900))
			check(culled.y<culled.x,entry.id+" view fully below the ground submits no distant landscape")
			var huge := horizon.visible_blocks(depth,Rect2(-100000,-2000,200000,4000))
			check(huge.y-huge.x+1<=Horizon.MAX_BLOCKS_PER_DEPTH,entry.id+" extreme view bounds have a hard draw budget")
		check(count<=24,entry.id+" widest supported view stays below 24 texture blocks")
	check(palettes.size()==9,"All nine environments have distinct depth palettes")
	await Cleanup.free_scene(scenery,self)
	print("DISTANT HORIZON: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
