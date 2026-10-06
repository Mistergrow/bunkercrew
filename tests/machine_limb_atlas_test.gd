extends SceneTree
const LimbArt := preload("res://scripts/machine_limb_art.gd")
const Atlas := preload("res://scripts/machine_limb_atlas.gd")
const Bake := preload("res://tools/bake_machine_limbs.gd")
var checks:=0
var failures:=0
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func same_pixels(a: Image,b: Image) -> bool:
	if a.get_size()!=b.get_size():return false
	for y in a.get_height():
		for x in a.get_width():
			var first:=a.get_pixel(x,y)
			var second:=b.get_pixel(x,y)
			# Godot's alpha-border import can fill RGB in fully invisible pixels.
			if first.a!=second.a or (first.a>0 and first!=second):return false
	return true
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	var metadata=JSON.parse_string(FileAccess.get_file_as_string(Atlas.METADATA))
	for path: String in metadata.source_sha256:
		var compatibility: Dictionary=metadata.get("runtime_loader_compatibility",{})
		if path==compatibility.get("path"):
			# Loader guards do not participate in baking: LimbArt.baking skips
			# atlas lookup. Retain its generation hash and review each revision;
			# the exhaustive comparisons below still verify all original pixels.
			check(compatibility.get("generation_source_sha256")==metadata.source_sha256[path] and FileAccess.get_sha256("res://"+path)==compatibility.get("current_source_sha256"),"Reviewed runtime loader retains original generation provenance: "+path)
		else:
			check(FileAccess.get_sha256("res://"+path)==metadata.source_sha256[path],"Limb provenance matches "+path)
	var image:Image=load(Atlas.PATH).get_image()
	LimbArt.baking=true;LimbArt._plate_cache.clear();LimbArt._joint_cache.clear();LimbArt._foot_cache.clear()
	var changed:=0
	for length in range(8,97,4):
		for width in [6,9,10,12,13]:
			for seed_value in 5:
				for far_side in [false,true]:
					var part:=Atlas.part("plate:%d:%d:%d:%s"%[length,width,seed_value,far_side])
					var expected:=LimbArt._face_texture(length,width,seed_value,far_side).get_image()
					if not same_pixels(expected,image.get_region(Rect2i(part.region))):changed+=1
	check(changed==0,"All 1150 plate variants retain the exact original pixels")
	var viewport:=SubViewport.new();viewport.size=Vector2i(2400,80);viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(viewport)
	viewport.add_child(Bake.Rods.new());viewport.add_child(Bake.Fittings.new())
	for frame in 3:await RenderingServer.frame_post_draw
	var rods:=viewport.get_texture().get_image()
	changed=0
	for length in range(8,97,4):
		for side in 2:
			var part:=Atlas.part("piston:%d:%s"%[length,bool(side)])
			var expected:=rods.get_region(Rect2i(floori(float(length-8)/4)*102,side*12,length+4,10))
			if not same_pixels(expected,image.get_region(Rect2i(part.region))):changed+=1
	check(changed==0,"All 46 hydraulic rod variants match the native renderer")
	changed=0
	for key in LimbArt._joint_cache:
		if not same_pixels(LimbArt._joint_cache[key].get_image(),image.get_region(Rect2i(Atlas.part("joint:"+key).region))):changed+=1
	for key in LimbArt._foot_cache:
		if not same_pixels(LimbArt._foot_cache[key].get_image(),image.get_region(Rect2i(Atlas.part("foot:"+key).region))):changed+=1
	check(changed==0,"All bearings and soles preserve their original pixels")
	check(metadata.regions.size()==1210 and Atlas.parts.values().all(func(part):return part.atlas.get_rid()==Atlas.texture.get_rid()),"All 1210 authored pieces share one renderer texture")
	LimbArt.baking=false;LimbArt._plate_cache.clear();LimbArt._joint_cache.clear();LimbArt._foot_cache.clear()
	viewport.free()
	print("MACHINE LIMB ATLAS: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
