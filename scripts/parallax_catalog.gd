extends RefCounted
## Authored depth plates and small, local motion for every selectable location.
const Registry := preload("res://scripts/content_registry.gd")
const ROOT := "res://assets/environments/layers/"
const GAINS := [.36,.18,0.0]
const IMAGE_STYLES := [
	{"detail_strength":0.0,"sample_radius":1.0,"contour_strength":0.0},
	{"detail_strength":.55,"sample_radius":1.75,"contour_strength":.10},
	{"detail_strength":1.0,"sample_radius":2.25,"contour_strength":.22},
]
const PROFILES := {
	"sector07":{"mist":"#8b8092","opacity":.055,"lights":0.0},
	"ash_foundry":{"mist":"#607c98","opacity":.09,"lights":1.0},
	"abandoned_harbor":{"mist":"#7395af","opacity":.08,"lights":.75},
	"basalt_quarry":{"mist":"#b5a3b5","opacity":.055,"lights":0.0},
	"overgrown_steelworks":{"mist":"#98ae96","opacity":.06,"lights":0.0},
	"frozen_rail_yard":{"mist":"#b3c8dd","opacity":.075,"lights":.6},
	"iron_canyon":{"mist":"#c59679","opacity":.065,"lights":0.0},
	"flooded_power_station":{"mist":"#9eafa6","opacity":.08,"lights":.5},
	"mountain_pass":{"mist":"#6e75ad","opacity":.12,"lights":1.0,"plates":["sky","ridges","valley"]},
	"storm_dam":{"mist":"#9fb2bf","opacity":.11,"lights":.75},
	"sulfur_refinery":{"mist":"#baa77d","opacity":.075,"lights":0.0},
	"radar_highlands":{"mist":"#9697c5","opacity":.085,"lights":.8},
	"buried_megafactory":{"mist":"#bc927d","opacity":.075,"lights":0.0},
}
static var _environments: Dictionary = {}

static func _environment(id: String) -> Dictionary:
	if not _environments.has(id): _environments[id] = Registry.data("environments",id)
	return _environments[id]

static func definition(id: String) -> Dictionary:
	if PROFILES.has(id): return PROFILES[id]
	var environment := _environment(id)
	if environment.is_empty(): return {}
	return PROFILES.get(str(environment.get("background_profile","sector07")),{})

static func background_id(id: String) -> String:
	if PROFILES.has(id): return id
	var environment := _environment(id)
	var source_id := str(environment.get("background_profile",""))
	var base := _environment(source_id)
	if not PROFILES.has(source_id) or base.is_empty() or environment.is_empty(): return ""
	return source_id if str(base.get("city_path",base.get("path","")))==str(environment.get("city_path",environment.get("path",""))) else ""

static func sky_mask_path(id: String) -> String:
	var source_id := background_id(id)
	return "res://assets/atmosphere/sky_masks/"+source_id+".png" if not source_id.is_empty() else ""

static func paths(id: String) -> Array[String]:
	var result: Array[String] = []
	var environment := _environment(id)
	var explicit: Variant = environment.get("layer_paths")
	if explicit is Array and explicit.size()==3:
		for path: String in explicit: result.append(path)
		return result
	var source_id := id
	if not PROFILES.has(source_id):
		source_id = str(environment.get("background_profile",""))
		var base := _environment(source_id)
		if base.is_empty() or str(base.get("city_path",base.get("path","")))!=str(environment.get("city_path",environment.get("path",""))): return result
	if not PROFILES.has(source_id): return result
	for plate: String in PROFILES[source_id].get("plates",["sky","distance","landmarks"]):
		result.append(ROOT+source_id+"_v1/"+plate+".png")
	return result

static func available(id: String) -> bool:
	var layers := paths(id)
	return layers.size()==3 and layers.all(func(path: String):return ResourceLoader.exists(path))
