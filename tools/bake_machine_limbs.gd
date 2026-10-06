extends SceneTree
const LimbArt := preload("res://scripts/machine_limb_art.gd")
const Atlas := preload("res://scripts/machine_limb_atlas.gd")
var target := Image.create(2048,2048,false,Image.FORMAT_RGBA8)
var regions: Dictionary = {}
var cursor := Vector2i(2,2)
var row_height := 0
class Rods extends Node2D:
	func _draw() -> void:
		for length in range(8,97,4):
			for side in 2:
				var at := Vector2(2+floori(float(length-8)/4)*102,5+side*12)
				LimbArt.piston(self,at,at+Vector2(length,0),bool(side))

class Fittings extends Node2D:
	func _draw() -> void:
		for radius in [3.5,4.0,4.5,5.0,6.5]:
			for far_side in [false,true]: LimbArt.joint(self,Vector2(30,60),radius,far_side)
		for heavy in [false,true]:
			for far_side in [false,true]: LimbArt.foot(self,Vector2(60,60),heavy,far_side)

func store_part(key: String, source: Image) -> void:
	if cursor.x+source.get_width()+2>2048:
		cursor.x=2;cursor.y+=row_height+2;row_height=0
	assert(cursor.y+source.get_height()+2<=2048)
	target.blit_rect(source,Rect2i(Vector2i.ZERO,source.get_size()),cursor)
	regions[key]=[cursor.x,cursor.y,source.get_width(),source.get_height()]
	cursor.x+=source.get_width()+2
	row_height=maxi(row_height,source.get_height())

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless":quit(2);return
	LimbArt.baking=true
	for length in range(8,97,4):
		for width in [6,9,10,12,13]:
			for seed_value in 5:
				for far_side in [false,true]:
					store_part("plate:%d:%d:%d:%s"%[length,width,seed_value,far_side],LimbArt._face_texture(length,width,seed_value,far_side).get_image())
	var viewport := SubViewport.new()
	viewport.size=Vector2i(2400,80)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(Rods.new())
	viewport.add_child(Fittings.new())
	for frame in 3:await RenderingServer.frame_post_draw
	var rods := viewport.get_texture().get_image()
	for radius in [3.5,4.0,4.5,5.0,6.5]:
		for far_side in [false,true]:
			store_part("joint:%s:%s"%[radius,far_side],LimbArt._joint_cache["%s:%s"%[radius,far_side]].get_image())
	for heavy in [false,true]:
		for far_side in [false,true]:
			store_part("foot:%s:%s"%[heavy,far_side],LimbArt._foot_cache["%s:%s"%[heavy,far_side]].get_image())
	for length in range(8,97,4):
		for side in 2:
			store_part("piston:%d:%s"%[length,bool(side)],rods.get_region(Rect2i(floori(float(length-8)/4)*102,side*12,length+4,10)))
	target=target.get_region(Rect2i(0,0,2048,1024))
	target.save_png(Atlas.PATH)
	var hashes := {}
	for path in ["tools/bake_machine_limbs.gd","scripts/machine_limb_art.gd","scripts/machine_limb_atlas.gd"]: hashes[path]=FileAccess.get_sha256("res://"+path)
	var file:=FileAccess.open(Atlas.METADATA,FileAccess.WRITE)
	file.store_string(JSON.stringify({"generator":"tools/bake_machine_limbs.gd","method":"Original native GDScript limb pixels and renderer-baked rods, packed without image resampling. Runtime uses the same continuously articulated endpoints; rod texture length follows the same 4px buckets as plates.","license":"Same as original project-generated native art.","size":[2048,1024],"source_sha256":hashes,"regions":regions},"  "))
	file.close()
	viewport.free()
	print("BAKED MACHINE LIMBS: ",regions.size()," regions, height ",cursor.y+row_height)
	quit()
