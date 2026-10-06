class_name LivingEcologyCatalog
extends RefCounted
## Ground ecology is authored by habitat, then laid out deterministically.
## All roots remain on the actual outdoor slab and clear the whole bunker.
const ATLAS_PATH := "res://assets/environments/life/vegetation_v1.png"
const METADATA_PATH := "res://assets/environments/life/vegetation_v1.source.json"
const GROUND_Y := 430.0
const GROUND_LEFT := -410.0
const GROUND_RIGHT := 1850.0
const BUNKER_CLEARANCE := 54.0
const MAX_PLANTS := 192
# Cosmetic growth outside the collision slab uses stable world chunks. It is
# deliberately separate from layout(), whose roots describe reachable ground.
const OUTSKIRT_CHUNK_WIDTH := 512.0
const MAX_OUTSKIRT_CHUNKS := 36
const OUTSKIRT_GROWTH_DISTANCE := 900.0
const MAX_OUTSKIRT_PLANTS_PER_CHUNK := 32
const MAX_OUTSKIRT_TREES_PER_CHUNK := 6
const MAX_OUTSKIRT_PLANTS := MAX_OUTSKIRT_CHUNKS*MAX_OUTSKIRT_PLANTS_PER_CHUNK
const MAX_OUTSKIRT_TREES := MAX_OUTSKIRT_CHUNKS*MAX_OUTSKIRT_TREES_PER_CHUNK
const MAX_OUTSKIRT_HEIGHT := 360.0
const OUTSKIRT_SHRUBS := {
	"storm_dam":["reeds","cattails","leafy_bush"],
	"sulfur_refinery":["dry_bush","thorn_bush"],
	"radar_highlands":["snow_bush","frost_grass"],
	"buried_megafactory":["thorn_bush","bramble","dry_bush"],
	"sector07":["bramble","leafy_bush","dry_bush"],
	"ash_foundry":["dry_bush","thorn_bush","bramble"],
	"abandoned_harbor":["reeds","cattails","leafy_bush"],
	"basalt_quarry":["dry_bush","bramble"],
	"overgrown_steelworks":["leafy_bush","fern","bramble"],
	"frozen_rail_yard":["snow_bush","frost_grass"],
	"iron_canyon":["thorn_bush","dry_bush"],
	"flooded_power_station":["cattails","reeds","leafy_bush","fern"],
	"mountain_pass":["leafy_bush","fern"],
}
const SPECIES := {
	"fern":{"size":Vector2(48,35),"stiffness":.42},
	"leafy_bush":{"size":Vector2(65,45),"stiffness":.77},
	"bramble":{"size":Vector2(61,34),"stiffness":.88},
	"meadow_grass":{"size":Vector2(40,26),"stiffness":.28},
	"reeds":{"size":Vector2(43,50),"stiffness":.35},
	"cattails":{"size":Vector2(43,56),"stiffness":.46},
	"moss_patch":{"size":Vector2(39,9),"stiffness":1.0},
	"ivy":{"size":Vector2(49,29),"stiffness":.72},
	"dry_grass":{"size":Vector2(38,24),"stiffness":.36},
	"dry_bush":{"size":Vector2(51,39),"stiffness":.86},
	"thorn_bush":{"size":Vector2(47,37),"stiffness":.92},
	"lichen":{"size":Vector2(35,10),"stiffness":1.0},
	"frost_grass":{"size":Vector2(35,23),"stiffness":.62},
	"snow_bush":{"size":Vector2(48,34),"stiffness":.9},
	"alpine_tuft":{"size":Vector2(29,18),"stiffness":.5},
	"mushrooms":{"size":Vector2(24,14),"stiffness":1.0},
}
const PROFILES := {
	"storm_dam":{"biome":"windy_reservoir","moisture":.91,"density":1.05,"wind":1.45,"tint":Color("c7d0c4"),"flora":["reeds","cattails","meadow_grass","moss_patch","leafy_bush"],"weights":[5,3,4,2,1]},
	"sulfur_refinery":{"biome":"sulfur_scrub","moisture":.06,"density":.57,"wind":1.0,"tint":Color("d1c19b"),"flora":["dry_grass","dry_bush","thorn_bush","lichen"],"weights":[5,2,2,3]},
	"radar_highlands":{"biome":"cold_upland","moisture":.41,"density":.77,"wind":1.35,"tint":Color("bec6d2"),"flora":["alpine_tuft","frost_grass","snow_bush","lichen","dry_grass"],"weights":[5,3,2,3,1]},
	"buried_megafactory":{"biome":"reclaimed_rubble","moisture":.17,"density":.66,"wind":.9,"tint":Color("c8b1a2"),"flora":["dry_grass","bramble","thorn_bush","lichen","moss_patch"],"weights":[5,2,2,3,1]},
	"sector07":{"biome":"industrial_verge","moisture":.34,"density":.8,"wind":.82,"tint":Color("bdc3a8"),"flora":["meadow_grass","dry_grass","bramble","leafy_bush","moss_patch"],"weights":[5,3,2,2,1]},
	"ash_foundry":{"biome":"ash_scrub","moisture":.09,"density":.62,"wind":1.0,"tint":Color("c0b49c"),"flora":["dry_grass","dry_bush","thorn_bush","lichen","bramble"],"weights":[6,3,2,3,1]},
	"abandoned_harbor":{"biome":"salt_marsh","moisture":.8,"density":.97,"wind":1.2,"tint":Color("bdcec5"),"flora":["reeds","meadow_grass","cattails","leafy_bush","lichen"],"weights":[5,4,2,2,1]},
	"basalt_quarry":{"biome":"rocky_succession","moisture":.26,"density":.68,"wind":.78,"tint":Color("c5c0b3"),"flora":["dry_grass","alpine_tuft","lichen","dry_bush","bramble"],"weights":[4,4,4,2,1]},
	"overgrown_steelworks":{"biome":"temperate_regrowth","moisture":.83,"density":1.35,"wind":.9,"tint":Color("c3cfac"),"flora":["fern","leafy_bush","bramble","meadow_grass","moss_patch","ivy","mushrooms"],"weights":[5,4,3,5,3,3,1]},
	"frozen_rail_yard":{"biome":"frozen_verge","moisture":.48,"density":.79,"wind":.88,"tint":Color("c8d9dc"),"flora":["frost_grass","snow_bush","alpine_tuft","lichen"],"weights":[5,3,3,2]},
	"iron_canyon":{"biome":"arid_canyon","moisture":.02,"density":.55,"wind":1.48,"tint":Color("d6b78f"),"flora":["dry_grass","thorn_bush","dry_bush","lichen"],"weights":[4,4,3,2]},
	"flooded_power_station":{"biome":"freshwater_reclamation","moisture":.99,"density":1.3,"wind":.82,"tint":Color("b6cdb4"),"flora":["reeds","cattails","fern","moss_patch","ivy","leafy_bush","mushrooms"],"weights":[5,4,3,3,2,3,1]},
	"mountain_pass":{"biome":"alpine_woodland","moisture":.64,"density":1.03,"wind":1.6,"tint":Color("bdc9cc"),"flora":["fern","alpine_tuft","meadow_grass","leafy_bush","moss_patch","lichen"],"weights":[3,5,4,2,3,2]},
}
static var _regions: Dictionary = {}

static func profile(environment_id: String) -> Dictionary:
	return PROFILES.get(environment_id,PROFILES.sector07).duplicate(true)

static func habitat(environment_id: String) -> Dictionary:
	return profile(environment_id)

static func species_ids() -> Array[String]:
	var result: Array[String] = []
	for key: String in SPECIES: result.append(key)
	return result

static func asset_regions() -> Dictionary:
	if not _regions.is_empty(): return _regions
	if not FileAccess.file_exists(METADATA_PATH): return {}
	var decoded = JSON.parse_string(FileAccess.get_file_as_string(METADATA_PATH))
	if not decoded is Dictionary: return {}
	var sprites = decoded.get("regions",decoded.get("sprites",{}))
	if not sprites is Dictionary: return {}
	for key: String in SPECIES:
		if not sprites.get(key) is Dictionary: continue
		var value: Dictionary = sprites[key]
		var rect_data = value.get("rect",value.get("region",[]))
		var root_data = value.get("root",value.get("anchor",[]))
		if rect_data.size()!=4 or root_data.size()!=2: continue
		var rect := Rect2(float(rect_data[0]),float(rect_data[1]),float(rect_data[2]),float(rect_data[3]))
		var anchor := Vector2(float(root_data[0]),float(root_data[1]))
		if rect.size.x<=0 or rect.size.y<=0 or anchor.y<=rect.position.y: continue
		_regions[key] = {"rect":rect,"root":anchor}
	return _regions

static func _pick_species(rng: RandomNumberGenerator,data: Dictionary) -> String:
	var sum := 0
	for weight: int in data.weights: sum += weight
	var choice := rng.randi_range(0,maxi(0,sum-1))
	for index in data.flora.size():
		choice -= int(data.weights[index])
		if choice<0: return str(data.flora[index])
	return str(data.flora[0])

static func layout(environment_id: String,bunker_left: float=90.0,bunker_right: float=730.0,reduced: bool=false,ground_left: float=GROUND_LEFT,ground_right: float=GROUND_RIGHT) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 194737 + absi(environment_id.hash())
	var data := profile(environment_id)
	var result: Array[Dictionary] = []
	ground_left = maxf(ground_left,GROUND_LEFT)
	ground_right = minf(ground_right,GROUND_RIGHT)
	var intervals: Array[Vector2] = [Vector2(ground_left+38,minf(ground_right-38,bunker_left-BUNKER_CLEARANCE)),Vector2(maxf(ground_left+38,bunker_right+BUNKER_CLEARANCE),ground_right-38)]
	for interval: Vector2 in intervals:
		if interval.y-interval.x<80: continue
		var clusters := maxi(1,roundi((interval.y-interval.x)/92.0))
		for cluster in clusters:
			var centre := lerpf(interval.x+35,interval.y-35,(float(cluster)+.5)/float(clusters))+rng.randf_range(-15,15)
			var count := clampi(roundi(rng.randf_range(4,8)*float(data.density)),3,11)
			for member in count:
				if result.size()>=MAX_PLANTS: return _reduced_layout(result) if reduced else result
				var species := _pick_species(rng,data)
				var spec: Dictionary = SPECIES[species]
				var size: Vector2 = spec.size*rng.randf_range(.7,1.2)
				# One recognisable bush/reed silhouette anchors each natural patch;
				# lower companions overlap it rather than forming a regular row.
				var depth := posmod(member+cluster,3)
				if depth==0: size *= .9
				if interval.y-interval.x<size.x*2: continue
				var minimum_x := ceilf((interval.x+size.x)*2.0)*.5
				var maximum_x := floorf((interval.y-size.x)*2.0)*.5
				var x := clampf(snappedf(centre+rng.randf_range(-37,37),.5),minimum_x,maximum_x)
				var position := Vector2(x,GROUND_Y)
				var index := result.size()
				result.append({"index":index,"species":species,"position":position,"size":size,"phase":rng.randf_range(0,TAU),"stiffness":float(spec.stiffness),"mirror":rng.randf()<.45,"depth":depth,"optional":member>0,"reduced_visible":member==0 or index%3==0,"cluster":cluster,"bounds":Rect2(position-Vector2(size.x*.5,size.y),size)})
	return _reduced_layout(result) if reduced else result

static func _reduced_layout(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if bool(entry.reduced_visible): result.append(entry)
	return result

static func outskirts_growth(x: float,occupied: Vector2) -> float:
	var distance := maxf(maxf(occupied.x-x,x-occupied.y),0.0)
	return smoothstep(0.0,OUTSKIRT_GROWTH_DISTANCE,distance)

static func outskirts_layout(environment_id: String,span: Vector2i,landscape: Array[Rect2],occupied: Vector2) -> Dictionary:
	var plants: Array[Dictionary] = []
	var trees: Array[Dictionary] = []
	var data := profile(environment_id)
	var tree_catalog := preload("res://scripts/scenario_prop_catalog.gd")
	var tree_mix: Array = tree_catalog.TREE_MIX.get(environment_id,tree_catalog.TREE_MIX.sector07)
	var shrubs: Array = OUTSKIRT_SHRUBS.get(environment_id,OUTSKIRT_SHRUBS.sector07)
	var harsh := float(data.moisture)<.3
	var tree_slots := 4 if harsh else 5 if environment_id in ["sector07","abandoned_harbor"] else 6
	var last := mini(span.y,span.x+MAX_OUTSKIRT_CHUNKS-1)
	for chunk in range(span.x,last+1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 763931+absi((environment_id+":"+str(chunk)).hash())
		var chunk_left := float(chunk)*OUTSKIRT_CHUNK_WIDTH
		var chunk_right := chunk_left+OUTSKIRT_CHUNK_WIDTH
		var chunk_plants := 0
		var chunk_trees := 0
		for slab: Rect2 in landscape:
			if slab.end.x<=chunk_left or slab.position.x>=chunk_right: continue
			# Fixed potential slots belong to this world chunk. Denser distant
			# patches overlap, while the first shrubs form a broken natural verge.
			# The short cover is accompanied by recognisable thicket silhouettes;
			# simply adding more moss or grass would still leave a thin flat lip.
			for patch in 8:
				var center := chunk_left+(float(patch)+.5)*64.0+rng.randf_range(-11,11)
				var growth := outskirts_growth(center,occupied)
				if patch%2==1 and growth<.2+float(patch)*.055: continue
				var count := 2+roundi(growth*2.0)
				for member in range(count):
					if chunk_plants>=MAX_OUTSKIRT_PLANTS_PER_CHUNK: break
					var structural := member==0 or member==1 and growth>.5
					var species := str(shrubs[posmod(patch+member,shrubs.size())]) if structural else _pick_species(rng,data)
					var spec: Dictionary = SPECIES[species]
					var scale := lerpf(.86,2.05,growth) if structural else lerpf(.76,1.32,growth)
					var size: Vector2 = spec.size*scale*rng.randf_range(.84,1.12)
					var candidate := center+rng.randf_range(-40,40)*(0.25 if member==0 else 1.0)
					var x := _outskirt_position(candidate,size.x,chunk_left,chunk_right,slab,occupied)
					if not is_finite(x): continue
					var position := Vector2(x,slab.position.y)
					var depth := 1 if member==0 else 0 if structural else 2
					plants.append({"species":species,"position":position,"size":size,"phase":rng.randf_range(0,TAU),"stiffness":float(spec.stiffness),"mirror":rng.randf()<.45,"depth":depth,"reduced_visible":structural or member==2 and patch%3==0,"structural":structural,"growth":growth,"chunk":chunk,"bounds":Rect2(position-Vector2(size.x,size.y),Vector2(size.x*2,size.y))})
					chunk_plants += 1
			# Two irregular crown bands grow into overlapping groups. Tree roots
			# belong to stable chunk slots; their crowns may cross chunk borders.
			# Only the real painted slab and occupied land constrain whole bounds.
			# Arid habitats retain dead wood and thorn scrub rather than a forest.
			for tree_index in MAX_OUTSKIRT_TREES_PER_CHUNK:
				if chunk_trees>=tree_slots: break
				var depth := floori(float(tree_index)/3.0)
				var column := posmod(tree_index,3)
				var candidate := chunk_left+(float(column)+(.28 if depth==0 else .69))*OUTSKIRT_CHUNK_WIDTH/3.0+rng.randf_range(-24,24)
				var growth := outskirts_growth(candidate,occupied)
				var threshold: float = [0.0,.34,.68,.12,.45,.79][tree_index]
				if growth<threshold: continue
				var kind := str(tree_mix[rng.randi_range(0,tree_mix.size()-1)])
				var crop: Rect2i = tree_catalog.TREE_REGIONS[kind]
				var anchor: Vector2 = tree_catalog.TREE_ROOTS[kind]
				var height := lerpf(138.0 if depth==0 else 110.0,270.0 if harsh else 328.0 if depth==0 else 282.0,growth)*rng.randf_range(.86,1.09)
				height = minf(height,MAX_OUTSKIRT_HEIGHT)
				var size := Vector2(float(crop.size.x)*height/(anchor.y-crop.position.y),height)
				var x := _outskirt_position(candidate,size.x,chunk_left,chunk_right,slab,occupied)
				if not is_finite(x): continue
				var position := Vector2(x,slab.position.y)
				trees.append({"species":kind,"position":position,"size":size,"phase":rng.randf_range(0,TAU),"stiffness":.94 if kind=="dead" else .72,"mirror":rng.randf()<.5,"depth":depth,"reduced_visible":depth==0 or column!=1,"structural":depth==0,"growth":growth,"chunk":chunk,"bounds":Rect2(position-Vector2(size.x,size.y),Vector2(size.x*2,size.y))})
				chunk_trees += 1
	return {"plants":plants,"trees":trees}

static func _outskirt_position(candidate: float,radius: float,chunk_left: float,chunk_right: float,slab: Rect2,occupied: Vector2) -> float:
	var left := maxf(chunk_left+1.0,slab.position.x+radius+.5)
	var right := minf(chunk_right-1.0,slab.end.x-radius-.5)
	if candidate<occupied.x:
		right = minf(right,occupied.x-radius-.5)
	elif candidate>occupied.y:
		left = maxf(left,occupied.y+radius+.5)
	else:
		return INF
	left = ceilf(left*2.0)*.5
	right = floorf(right*2.0)*.5
	if right<left: return INF
	return snappedf(clampf(candidate,left,right),.5)
