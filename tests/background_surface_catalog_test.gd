extends SceneTree
## Malformed or mismatched mask metadata must leave the source plate static.
const Surfaces := preload("res://scripts/background_surface_catalog.gd")
const Plates := preload("res://scripts/parallax_catalog.gd")
const OUTPUT := "res://artifacts/code-hardening/graphics"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func read_fixture(text: String) -> Dictionary:
	var path := OUTPUT+"/catalog-fixture.json"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	var result := Surfaces._read_environments(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for id: String in Plates.PROFILES:
		check(Surfaces.available(id),id+": valid reviewed mask remains available")
		check(Surfaces.texture(id) is Texture2D,id+": valid mask texture loads")
		check(Surfaces.enabled(id)==not Surfaces.definition(id).regions.is_empty(),id+": dry and liquid maps retain their authored effect state")
	for contents: String in ["", "{", "null", "[]", "{}", "{\"environments\":null}", "{\"environments\":[]}", "{\"environments\":3}"]:
		check(read_fixture(contents).is_empty(),"Invalid JSON/document shape fails closed: "+contents)
	var filtered := read_fixture("{\"environments\":{\"valid\":{\"regions\":[]},\"number\":3,\"list\":[],\"null\":null}}")
	check(filtered.size()==1 and filtered.has("valid"),"Only dictionary environment entries survive parsing")
	check(Surfaces._read_environments(OUTPUT+"/missing-mask-catalog.json").is_empty(),"Missing prepared catalog fails closed")
	var definitions := Surfaces._definitions.duplicate(true)
	var masks := Surfaces._masks.duplicate(true)
	var textures := Surfaces._textures.duplicate()
	var id := "abandoned_harbor"
	var original: Dictionary=masks[id].duplicate(true)
	for malformed in [null, [], [0.0], [0.0,0.0,1.0], [0.0,0.0,1.0,1.0,0.0], [0.0,"shore",1.0,1.0], [0.0,0.0,0.0,1.0], [0.0,0.0,1.0,-1.0], [-0.1,0.0,1.0,1.0], [0.9,0.0,0.2,1.0], [0.0,0.0,NAN,1.0], [0.0,0.0,1.0,INF], [9223372036854775807,0,9223372036854775807,1]]:
		Surfaces._masks[id]=original.duplicate(true)
		Surfaces._masks[id]["bounds"]=malformed
		check(Surfaces.bounds(id)==Vector4(0,0,1,1),"Malformed bounds have a safe public fallback")
		check(not Surfaces.available(id) and not Surfaces.enabled(id) and Surfaces.texture(id)==null,"Malformed cropped-mask bounds never animate the whole source plate")
	for malformed in [null, [], 42, "water"]:
		Surfaces._definitions[id]=malformed
		check(Surfaces.definition(id).is_empty() and not Surfaces.available(id),"Invalid source entry never triggers a typed-return error")
	Surfaces._definitions=definitions.duplicate(true)
	for malformed in [null, [], 42, "water"]:
		Surfaces._masks[id]=malformed
		check(Surfaces.mask_definition(id).is_empty() and not Surfaces.available(id),"Invalid mask entry never triggers a typed-return error")
	for key: String in ["source_path","source_sha256","original_dimensions"]:
		Surfaces._masks[id]=original.duplicate(true)
		Surfaces._masks[id][key]="different-source"
		check(not Surfaces.available(id),"Mismatched "+key+" disables stale mask coordinates")
	Surfaces._masks.erase(id)
	check(not Surfaces.available(id) and not Surfaces.enabled(id),"Existing cropped PNG without its UV catalog stays disabled")
	Surfaces._masks=masks.duplicate(true)
	for malformed in [null, 42, "water"]:
		Surfaces._definitions[id]=definitions[id].duplicate(true)
		Surfaces._definitions[id]["regions"]=malformed
		check(not Surfaces.enabled(id),"Invalid region collection cannot enable the mask")
	Surfaces._definitions=definitions
	Surfaces._masks=masks
	Surfaces._textures=textures
	check(not Surfaces.available("../abandoned_harbor") and not Surfaces.available("missing-map"),"Invalid or unknown mask IDs are rejected")
	check(Surfaces.available(id) and Surfaces.enabled(id),"Valid production asset remains available after every malformed-data case")
	print("BACKGROUND SURFACE CATALOG: %d/%d passed"%[checks-failures,checks])
	var report := FileAccess.open(OUTPUT+"/surface-catalog-verification.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"prepared":"All13 production mask resources and their paired source metadata; malformed JSON and environment entries, missing metadata, invalid crop bounds, source mismatch; no profile changes or renderer required."},"\t"))
	report.close()
	quit(1 if failures else 0)
