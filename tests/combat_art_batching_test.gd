extends SceneTree
const Atlas := preload("res://scripts/infantry_art_atlas.gd")
const Bake := preload("res://tools/bake_infantry_art.gd")
const Quads := preload("res://scripts/canvas_quads.gd")
const WetMaterials := preload("res://scripts/actor_wet_materials.gd")
var checks := 0
var failures := 0

class Cached extends Node2D:
	func _draw() -> void:
		for kind in Atlas.ROLES:
			for part in ["head","torso","rear","gun"]:
				for slot in (range(7) if part=="head" else [0]):
					for sway in (range(-1,4) if part in ["head","rear"] else [0]):
						var index := Atlas.tile_index(part,kind,slot,sway)
						var at := Vector2(index%Atlas.COLUMNS,floori(float(index)/Atlas.COLUMNS))*Atlas.SIZE+Atlas.origin(part)
						Atlas.draw_part(self,Transform2D(0,at),part,kind,slot,sway)

## The v2 atlas file itself, for Atlas.draw_part to reproduce tile by tile.
class Authored extends Node2D:
	func _draw() -> void:
		draw_texture(load(Atlas.PATH),Vector2.ZERO)

class Rectangles extends Node2D:
	var original := false
	func _draw() -> void:
		for index in 100:
			var at := Vector2(index%10*45+30,floori(float(index)/10)*45+30)
			var patch_transform := Transform2D(index*.16,at)
			var points := PackedVector2Array()
			for point in [Vector2(-13,-4),Vector2(13,-4),Vector2(13,4),Vector2(-13,4)]: points.append((patch_transform*point).round())
			if original: draw_colored_polygon(points,Color(.44,.49,.35))
			else: Quads.patch(self,patch_transform,Vector2(-13,-4),Vector2(26,8),Color(.44,.49,.35))

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1;push_error(label)
func view(node: Node2D, size: Vector2i) -> SubViewport:
	var result := SubViewport.new()
	result.size=size
	result.transparent_bg=true
	result.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	result.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(result)
	result.add_child(node)
	return result
func run() -> void:
	if DisplayServer.get_name()=="headless":
		# Exit code 2 is "not run", never a pass: the comparison needs real pixels.
		printerr("COMBAT ART BATCHING: not run, the headless display has no renderer")
		quit(2);return
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(Atlas.LEGACY_PATH.get_basename()+".source.json"))
	for path: String in metadata.source_sha256:
		check(FileAccess.get_sha256("res://"+path)==metadata.source_sha256[path],"Legacy atlas provenance matches "+path)
	var authored = JSON.parse_string(FileAccess.get_file_as_string(Atlas.PATH.get_basename()+".source.json"))
	check(FileAccess.get_sha256(Atlas.PATH)==authored.sha256,"Hand-pixelled v2 atlas matches its provenance")
	for path: String in authored.source_sha256:
		check(FileAccess.get_sha256("res://"+path)==authored.source_sha256[path],"v2 atlas provenance matches "+path)
	var source := view(Bake.Sheet.new(),Vector2i(1024,1024))
	var cached := view(Cached.new(),Vector2i(1024,1024))
	var sheet := view(Authored.new(),Vector2i(1024,1024))
	for frame in 4:await RenderingServer.frame_post_draw
	# v1 file on the CPU (as baked) against the live procedural drawing; the
	# v2 file drawn whole against Atlas.draw_part tile by tile.
	var legacy := Image.load_from_file(ProjectSettings.globalize_path(Atlas.LEGACY_PATH))
	legacy.convert(Image.FORMAT_RGBA8)
	var pairs := [[source,legacy,.005,"All 252 v1 parts still match the procedural source drawing"],[cached,sheet,0.0,"Atlas.draw_part places all 252 hand-pixelled v2 parts exactly"]]
	for pair: Array in pairs:
		var actual: Image = pair[0].get_texture().get_image()
		var expected: Image = pair[1] if pair[1] is Image else pair[1].get_texture().get_image()
		var changed := 0
		var visible := 0
		for y in 1024:
			for x in 1024:
				var a := actual.get_pixel(x,y)
				var b := expected.get_pixel(x,y)
				if b.a>.01: visible+=1
				if absf(a.r-b.r)+absf(a.g-b.g)+absf(a.b-b.b)+absf(a.a-b.a)>.02:changed+=1
		check(visible>15000 and changed<=visible*float(pair[2]),"%s (changed %d / visible %d on %s)"%[pair[3],changed,visible,RenderingServer.get_video_adapter_name()])
		if pair[0]==cached:
			DirAccess.make_dir_recursive_absolute("res://artifacts/combat-performance")
			actual.save_png("res://artifacts/combat-performance/infantry-atlas-check.png")
	source.free();cached.free();sheet.free()
	var original := Rectangles.new()
	original.original=true
	var reference := view(original,Vector2i(500,500))
	var optimized := view(Rectangles.new(),Vector2i(500,500))
	for frame in 4: await RenderingServer.frame_post_draw
	check(reference.get_texture().get_image().get_data()==optimized.get_texture().get_image().get_data(),"Batched rotated pixel patches retain the exact old polygon pixels")
	var material := WetMaterials.get_material(true,-10000,false,0)
	original.material=material
	optimized.get_child(0).material=material
	original.set_instance_shader_parameter("wetness",0.0)
	optimized.get_child(0).set_instance_shader_parameter("wetness",.9)
	for frame in 4:await RenderingServer.frame_post_draw
	var dry := reference.get_texture().get_image().get_pixel(30,30)
	var wet := optimized.get_texture().get_image().get_pixel(30,30)
	check(wet.g<dry.g*.97 and is_equal_approx(wet.a,dry.a),"Shared material retains independent saturation and unchanged sprite alpha")
	reference.free();optimized.free()
	print("COMBAT ART BATCHING: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
