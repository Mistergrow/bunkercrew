extends SceneTree
## Deterministic native-art export. Run with the Compatibility renderer.
const Atlas := preload("res://scripts/infantry_art_atlas.gd")
const RoleArt := preload("res://scripts/infantry_role_art.gd")
class Sheet extends Node2D:
	func _draw() -> void:
		for kind in Atlas.ROLES:
			for part in ["head","torso","rear","gun"]:
				for slot in (range(7) if part=="head" else [0]):
					for sway in (range(-1,4) if part in ["head","rear"] else [0]):
						var index := Atlas.tile_index(part,kind,slot,sway)
						draw_set_transform(Vector2(index%Atlas.COLUMNS,floori(float(index)/Atlas.COLUMNS))*Atlas.SIZE+Atlas.origin(part))
						match part:
							"head": RoleArt.face(self,Transform2D.IDENTITY,kind,slot,sway)
							"rear": RoleArt.rear_kit(self,Transform2D.IDENTITY,kind,sway)
							"torso":
								var role := RoleArt.spec(kind)
								var width := 10.0 if role.torso=="branko" else 8.0
								var vertices:=PackedVector2Array()
								var uv:=PackedVector2Array()
								for point in [Vector2(-width,-1),Vector2(-5,-6),Vector2(4,-6),Vector2(width,-1),Vector2(width,15),Vector2(width-2,23),Vector2(-width+2,23),Vector2(-width,13)]:
									vertices.append(point);uv.append((point+Vector2(48,48))/112.0)
								draw_polygon(vertices,PackedColorArray([role.tint]),uv,WorkerIdentityArt.torso(role.torso))
								RoleArt.torso_kit(self,Transform2D.IDENTITY,kind)
							"gun": RoleArt.gun(self,Transform2D.IDENTITY,kind,0,false,0,false)
		draw_set_transform(Vector2.ZERO)

func _initialize() -> void: run.call_deferred()
func run() -> void:
	if DisplayServer.get_name()=="headless": quit(2);return
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1024,1024)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(viewport)
	viewport.add_child(Sheet.new())
	for frame in 3: await RenderingServer.frame_post_draw
	var result := viewport.get_texture().get_image()
	var code := result.save_png(Atlas.PATH)
	if code==OK:
		var metadata_path:=Atlas.PATH.get_basename()+".source.json"
		var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
		var hashes:Dictionary={}
		for path: String in metadata.source_sha256:hashes[path]=FileAccess.get_sha256("res://"+path)
		metadata.source_sha256=hashes
		var output:=FileAccess.open(metadata_path,FileAccess.WRITE)
		output.store_string(JSON.stringify(metadata,"  "))
		output.close()
	print("BAKED INFANTRY ATLAS: ",result.get_size()," result=",code)
	viewport.free()
	quit(0 if code==OK else 1)
