extends SceneTree
## Optional painted limb data falls back without an index/type error.
const Atlas := preload("res://scripts/machine_limb_atlas.gd")
const OUTPUT := "res://artifacts/code-hardening/graphics"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var saved_regions: Dictionary=Atlas.regions
	var saved_parts: Dictionary=Atlas.parts
	var saved_texture: Texture2D=Atlas.texture
	var saved_loaded: bool=Atlas.loaded
	Atlas.loaded=false
	Atlas.parts={}
	Atlas.texture=null
	var metadata: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Atlas.METADATA))
	for key: String in metadata.regions:
		var part: AtlasTexture=Atlas.part(key)
		check(part!=null and part.atlas==Atlas.texture,"Original region remains available: "+key)
	check(metadata.regions.size()==1210,"All authored limb variants were checked")
	check(Atlas.part("missing") == null,"Unknown optional piece uses the existing drawing fallback")
	Atlas.loaded=true
	Atlas.parts={}
	var malformed: Array=[null,4,"bad",{},[],[0,0],[0,0,4,4,7],[0,0,"4",4],[0,0,0,4],[-1,0,4,4],[0,0,-4,4],[0.5,0,4,4],[0,0,NAN,4],[0,0,INF,4],[Atlas.texture.get_width(),0,4,4],[0,Atlas.texture.get_height(),4,4],[9223372036854775807,0,9223372036854775807,4]]
	for value: Variant in malformed:
		Atlas.regions={"invalid":value}
		check(Atlas.part("invalid")==null,"Malformed optional region falls back: "+str(value))
	check(Atlas.parts.is_empty(),"Invalid pieces never enter the renderer cache")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var fixture:=OUTPUT+"/limb-catalog-fixture.json"
	for text: String in ["{broken","null","[]","{\"regions\":[]}","{\"regions\":null}","{\"regions\":4}","{\"regions\":\"bad\"}","{\"regions\":{\"part\":[0,0,4,4]}}"]:
		var file:=FileAccess.open(fixture,FileAccess.WRITE)
		file.store_string(text)
		file.close()
		var result: Dictionary=Atlas._read_regions(fixture)
		check(result.size()==1 if text.contains("\"part\"") else result.is_empty(),"Malformed document syntax and containers safely fall back: "+text)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(fixture))
	check(Atlas._read_regions(fixture).is_empty(),"Missing metadata has a safe drawing fallback")
	Atlas.regions=saved_regions
	Atlas.parts=saved_parts
	Atlas.texture=saved_texture
	Atlas.loaded=saved_loaded
	print("MACHINE LIMB CATALOG: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
