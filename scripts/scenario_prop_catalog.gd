extends RefCounted
## Deterministic scenery placement and raster anchors. Damage lives in a shared
## replicated controller; these entries add no gameplay collision bodies.
const TREE_PATHS := {
	"deciduous":"res://assets/environments/props/deciduous_tree.png",
	"conifer":"res://assets/environments/props/conifer_tree.png",
	"dead":"res://assets/environments/props/dead_tree.png",
	"oak":"res://assets/environments/props/oak_tree.png",
	"birch":"res://assets/environments/props/birch_tree.png",
	"spruce":"res://assets/environments/props/spruce_tree.png",
}
const TREE_REGIONS := {
	"deciduous":Rect2i(98,13,1060,1228),
	"conifer":Rect2i(332,13,612,1228),
	"dead":Rect2i(58,13,1159,1229),
	"oak":Rect2i(17,45,1220,1129),
	"birch":Rect2i(251,13,759,1218),
	"spruce":Rect2i(177,24,909,1179),
}
# Pixel anchors measured on the original 1254px alpha sprites. Everything below
# the trunk flare is buried; the isolated illustration's hanging root tips are
# not an outdoor ground anchor.
const TREE_ROOTS := {"deciduous":Vector2(623,1050),"conifer":Vector2(614,1135),"dead":Vector2(839,1030),"oak":Vector2(704,1172),"birch":Vector2(716,1228),"spruce":Vector2(627,1201)}
const TREE_TRUNKS := {
	"deciduous":[Vector2(623,1050),Vector2(620,910),Vector2(680,775),Vector2(722,647),Vector2(654,458)],
	"conifer":[Vector2(614,1135),Vector2(610,940),Vector2(612,730),Vector2(622,498),Vector2(628,245)],
	"dead":[Vector2(839,1030),Vector2(820,905),Vector2(773,765),Vector2(790,618),Vector2(712,469)],
	"oak":[Vector2(704,1172),Vector2(709,1030),Vector2(712,900),Vector2(660,730),Vector2(650,590)],
	"birch":[Vector2(716,1228),Vector2(712,1080),Vector2(698,940),Vector2(665,785),Vector2(628,618)],
	"spruce":[Vector2(627,1201),Vector2(628,1050),Vector2(648,845),Vector2(664,651),Vector2(655,435)],
}
const TREE_MIX := {
	"storm_dam":["spruce","conifer"],"sulfur_refinery":["dead","dead"],
	"radar_highlands":["conifer","spruce"],"buried_megafactory":["dead","dead"],
	"sector07":["dead","birch"],"ash_foundry":["dead","dead"],"abandoned_harbor":["dead","birch"],
	"basalt_quarry":["dead","dead"],"iron_canyon":["dead","dead"],
	"overgrown_steelworks":["oak","birch","deciduous"],"flooded_power_station":["deciduous","oak","birch"],
	"frozen_rail_yard":["spruce","conifer"],"mountain_pass":["conifer","spruce"],
}
static var _tree_metadata: Dictionary = {}
static var _canopy_cache: Dictionary = {}

static func tree_metadata(kind: String) -> Dictionary:
	if _tree_metadata.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environments/props/tree_metadata.json"))
		if parsed is Dictionary: _tree_metadata = parsed.get("trees",{})
	return _tree_metadata.get(kind,{})

static func canopy_points(kind: String) -> PackedVector2Array:
	if not _canopy_cache.has(kind):
		var points := PackedVector2Array()
		for point: Array in tree_metadata(kind).get("canopy_points",[]):
			points.append(Vector2(float(point[0]),float(point[1])))
		_canopy_cache[kind] = points
	return _canopy_cache[kind]
const PROFILES := {
	"storm_dam":{"tree":"conifer","props":["pipe","pump","cable","crane_hook"],"growth":"reeds","wind":1.5,"tree_tint":"8296a1","metal":"607783","accent":"b8b78b","foliage":"789483"},
	"sulfur_refinery":{"tree":"dead","props":["pipe","transformer","fan","generator"],"growth":"brush","wind":1.1,"tree_tint":"b3a27c","metal":"8c805b","accent":"d8b54f","foliage":"a29356"},
	"radar_highlands":{"tree":"conifer","props":["signal","relay_antenna","windsock","generator"],"growth":"frost_grass","wind":1.35,"tree_tint":"a8aec8","metal":"7d839d","accent":"c9b17a","foliage":"a4afbd"},
	"buried_megafactory":{"tree":"dead","props":["ore_cart","crane_hook","fan","transformer"],"growth":"brush","wind":1.05,"tree_tint":"ac9185","metal":"8f7169","accent":"cda16e","foliage":"99816b"},
	"sector07":{"tree":"dead","props":["fan","generator","cable","transformer"],"growth":"brush","wind":0.85,"tree_tint":"939784","metal":"667064","accent":"c29558","foliage":"77764d"},
	"ash_foundry":{"tree":"dead","props":["windsock","generator","fan","crane_hook"],"growth":"brush","wind":1.1,"tree_tint":"887b68","metal":"566063","accent":"d68a4a","foliage":"766947"},
	"abandoned_harbor":{"tree":"dead","props":["bollard","cargo_beacon","cable","crane_hook"],"growth":"reeds","wind":1.2,"tree_tint":"72918d","metal":"597c7d","accent":"bfaa6b","foliage":"798f6f"},
	"basalt_quarry":{"tree":"dead","props":["ore_cart","crane_hook","tape","generator"],"growth":"brush","wind":0.8,"tree_tint":"a39794","metal":"777785","accent":"d3b15f","foliage":"989071"},
	"overgrown_steelworks":{"tree":"deciduous","props":["vines","transformer","fan","generator"],"growth":"grass","wind":1.0,"tree_tint":"a4b48c","metal":"65755e","accent":"b5a26f","foliage":"89a167"},
	"frozen_rail_yard":{"tree":"conifer","props":["signal","cargo_beacon","cable","generator"],"growth":"frost_grass","wind":0.85,"tree_tint":"b1c8d1","metal":"79939f","accent":"cba266","foliage":"b7c8c4"},
	"iron_canyon":{"tree":"dead","props":["tape","generator","ore_cart","crane_hook"],"growth":"brush","wind":1.55,"tree_tint":"ba9674","metal":"93776d","accent":"d3af69","foliage":"c0a773"},
	"flooded_power_station":{"tree":"deciduous","props":["pipe","pump","cable","transformer"],"growth":"reeds","wind":0.9,"tree_tint":"88ab98","metal":"6d8c7d","accent":"cfb87e","foliage":"8eaa78"},
	"mountain_pass":{"tree":"conifer","props":["windsock","relay_antenna","signal","generator"],"growth":"grass","wind":1.6,"tree_tint":"929ead","metal":"747e94","accent":"bea376","foliage":"89988b"},
}

static func profile(environment_id: String) -> Dictionary:
	return PROFILES.get(environment_id,PROFILES.sector07).duplicate(true)

static func layout(environment_id: String,bunker_left: float,bunker_right: float) -> Array[Dictionary]:
	var spec := profile(environment_id)
	var result: Array[Dictionary] = []
	var slots: Array[float] = []
	# Four positions remain visible in the original 1440 px camera for every
	# bunker choice; tall props never cover an occupied room or its doorway.
	for x in [65.0,225.0,385.0,545.0,705.0,865.0,1025.0,1185.0,1345.0]:
		if x<bunker_left-85.0 or x>bunker_right+85.0:
			slots.append(x)
	for index in slots.size():
		var x := slots[index]
		if index%2==0:
			var species: Array = TREE_MIX.get(environment_id,TREE_MIX.sector07)
			_add(result,"tree",Vector2(x,430),Vector2(112,170+index*9),spec.tree_tint,false,str(species[floori(index/2.0)%species.size()]))
		else:
			_add(result,str(spec.props[floori(index/2.0)%spec.props.size()]),Vector2(x,430),Vector2(90,93),spec.metal)
		var growth_x := x+49.0 if x>bunker_right else x-49.0
		_add(result,str(spec.growth),Vector2(growth_x,430),Vector2(58,44),spec.foliage,true)
		_add(result,"rubble",Vector2(x-24,429),Vector2(55,11),spec.metal,true)
	# Extend the same scene when the camera opens after paid room expansions.
	# These are smaller, shaded silhouettes rather than repeated landmarks.
	for index in 2:
		# The real outdoor floor ends at -410 and 1850. Even distant roots must
		# have ground beneath them when the camera opens after room expansion.
		var x := -305.0 if index==0 else 1730.0
		var species: Array = TREE_MIX.get(environment_id,TREE_MIX.sector07)
		_add(result,"tree",Vector2(x,430),Vector2(100,132+index*13),spec.tree_tint,true,str(species[(index+2)%species.size()]))
		_add(result,str(spec.props[(index+2)%spec.props.size()]),Vector2(x+(-90 if index==0 else 90),430),Vector2(78,82),spec.metal,true)
	for entry in result:
		entry.family = str(tree_metadata(str(entry.tree)).get("family","dead")) if entry.kind=="tree" else "plant"
		entry.accent = Color(spec.accent)
		entry.foliage = Color(spec.foliage)
		var seed_value := int(entry.index)*731+environment_id.hash()+roundi(entry.position.x)*19
		entry.phase = _random(seed_value)*TAU
		entry.wind_rate = .72+_random(seed_value+71)*.66
		entry.stiffness = (.95+_random(seed_value+113)*.65)*(1.4 if entry.family=="dead" else 1.1 if entry.family=="conifer" else 1.0)*float(tree_metadata(str(entry.tree)).get("stiffness",1.0))
		entry.initial_state = "intact"
		if entry.kind=="tree":
			var crop: Rect2i = TREE_REGIONS[entry.tree]
			var anchor: Vector2 = TREE_ROOTS[entry.tree]
			var source_scale: float = entry.size.y/(anchor.y-crop.position.y)
			var mirror := -1.0 if int(entry.index)%4==2 else 1.0
			var sx := mirror*source_scale*(.86 if int(entry.index)%3==0 else 1.0)
			var a := (float(crop.position.x)-anchor.x)*sx
			var b := (float(crop.end.x)-anchor.x)*sx
			# Leave the actual crown plus a motion margin clear of doorways.
			if entry.position.x>bunker_right and entry.position.x+minf(a,b)<bunker_right+40:
				entry.position.x = bunker_right+40-minf(a,b)
			elif entry.position.x<bunker_left and entry.position.x+maxf(a,b)>bunker_left-40:
				entry.position.x = bunker_left-40-maxf(a,b)
		entry.bounds = Rect2(entry.position-Vector2(entry.size.x*.65,entry.size.y+12),Vector2(entry.size.x*1.3,entry.size.y+16))
	_clear_perimeter_sites(result,bunker_left,bunker_right)
	# One existing fire gives the ash world identity. Ruined distant decoration
	# is sparse, while ordinary healthy nearby vegetation remains in every map.
	if environment_id=="ash_foundry":
		for entry in result:
			if entry.kind=="tree" and not entry.optional:
				entry.initial_state = "burning"
				break
	if environment_id in ["sector07","ash_foundry","basalt_quarry","iron_canyon"]:
		for entry in result:
			if entry.kind=="tree" and entry.optional:
				entry.initial_state = "broken"
				break
	if environment_id in ["basalt_quarry","iron_canyon"]:
		for index in range(result.size()-1,-1,-1):
			var entry: Dictionary = result[index]
			if entry.kind=="tree" and not entry.optional:
				entry.initial_state = "broken"
				break
	return result

static func _random(seed_value: int) -> float:
	var value := posmod(seed_value,65521)
	value = posmod(value*25173+13849,65521)
	return float(posmod((value^(value>>7))*17431+7219,65521))/65520.0

static func _add(result: Array[Dictionary],kind: String,at: Vector2,size: Vector2,tint: String,optional: bool=false,tree: String="") -> void:
	var measured := {"windsock":Vector2(132,106),"signal":Vector2(40,114),"fan":Vector2(68,74),"cable":Vector2(98,98),"bollard":Vector2(98,33),"tape":Vector2(94,51),"ore_cart":Vector2(92,52),"vines":Vector2(88,91),"pipe":Vector2(72,62),"reeds":Vector2(58,61),"generator":Vector2(96,93),"pump":Vector2(88,63),"transformer":Vector2(80,91),"relay_antenna":Vector2(64,110),"crane_hook":Vector2(76,110),"cargo_beacon":Vector2(66,78)}
	size = measured.get(kind,size)
	result.append({"index":result.size(),"kind":kind,"position":at,"size":size,"tint":Color(tint),"optional":optional,"tree":tree,"animated":kind!="rubble"})

static func _solid_prop(entry: Dictionary) -> bool:
	return entry.kind not in ["rubble","brush","grass","frost_grass","reeds"]

static func _foot_radius(entry: Dictionary) -> float:
	# Tree crowns may overhang distant scenery; the planted trunk and machinery
	# feet must leave the actual gate/foundation and its working space clear.
	return 22.0 if entry.kind=="tree" else float(entry.size.x)*.5

static func _placement_limits(entry: Dictionary,left: float,right: float) -> Vector2:
	var radius := _foot_radius(entry)
	var limits := Vector2(-410.0+radius,1850.0-radius)
	var low := -radius
	var high := radius
	if entry.kind=="tree":
		var crop: Rect2i = TREE_REGIONS[entry.tree]
		var anchor: Vector2 = TREE_ROOTS[entry.tree]
		var source_scale: float = entry.size.y/(anchor.y-crop.position.y)
		var sx := (-1.0 if int(entry.index)%4==2 else 1.0)*source_scale*(.86 if int(entry.index)%3==0 else 1.0)
		low = minf((float(crop.position.x)-anchor.x)*sx,(float(crop.end.x)-anchor.x)*sx)
		high = maxf((float(crop.position.x)-anchor.x)*sx,(float(crop.end.x)-anchor.x)*sx)
	if entry.position.x<left:
		limits.y = minf(limits.y,left-40.0-maxf(radius,high))
	else:
		limits.x = maxf(limits.x,right+40.0-minf(-radius,low))
	return limits

static func _clear_perimeter_sites(entries: Array[Dictionary],left: float,right: float) -> void:
	var centers: Array[float] = []
	var midpoint: float = (left+right)*.5
	for side in [-1.0,1.0]:
		if (side<0 and midpoint<719) or (side>0 and midpoint>721): continue
		var edge: float = left if side<0 else right
		for site: Dictionary in preload("res://scripts/perimeter_catalog.gd").SITES:
			centers.append(edge+side*float(site.distance))
	var fixed: Array[Dictionary] = []
	var displaced: Array[Dictionary] = []
	for entry in entries:
		if not _solid_prop(entry): continue
		var limits := _placement_limits(entry,left,right)
		var intersects: bool = entry.position.x<limits.x or entry.position.x>limits.y
		for center in centers:
			intersects = intersects or absf(entry.position.x-center)<56.0+_foot_radius(entry)
		if intersects: displaced.append(entry)
		else: fixed.append(entry)
	# Give wide bases their valid slots first. Small tree feet can fit remaining
	# gaps; iteration stays deterministic and never pushes a chain off the floor.
	displaced.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		var ar := _foot_radius(a)
		var br := _foot_radius(b)
		return int(a.index)<int(b.index) if is_equal_approx(ar,br) else ar>br)
	for entry in displaced:
		var moving: Array[Dictionary] = [entry]
		var locked: Array[Dictionary] = fixed.duplicate()
		var solution := _place_group(moving,locked,centers,left,right)
		if solution.is_empty():
			# A distant wide base may need a few pixels from its neighbouring tree.
			# Unlock the nearest same-side prop only when preserving it is impossible.
			var neighbours: Array[Dictionary] = []
			for other in fixed:
				if (other.position.x<left)==(entry.position.x<left): neighbours.append(other)
			neighbours.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
				var da := absf(float(a.position.x)-float(entry.position.x))
				var db := absf(float(b.position.x)-float(entry.position.x))
				return int(a.index)<int(b.index) if is_equal_approx(da,db) else da<db)
			for other in neighbours:
				locked.erase(other)
				moving.append(other)
				moving.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
					return _foot_radius(a)>_foot_radius(b) if not is_equal_approx(_foot_radius(a),_foot_radius(b)) else int(a.index)<int(b.index))
				solution = _place_group(moving,locked,centers,left,right)
				if not solution.is_empty(): break
		assert(not solution.is_empty(),"No supported scenery position for entry %d" % int(entry.index))
		if solution.is_empty(): continue
		for moved in moving:
			moved.position.x = solution[int(moved.index)]
			moved.bounds = Rect2(moved.position-Vector2(moved.size.x*.65,moved.size.y+12),Vector2(moved.size.x*1.3,moved.size.y+16))
		fixed.append(entry)

static func _place_group(moving: Array[Dictionary],fixed: Array[Dictionary],centers: Array[float],left: float,right: float,offset: int = 0) -> Dictionary:
	if offset>=moving.size(): return {"complete":true}
	var entry: Dictionary = moving[offset]
	var limits := _placement_limits(entry,left,right)
	var original: float = entry.position.x
	var radius := _foot_radius(entry)
	var candidates: Array[float] = [clampf(original,limits.x,limits.y),limits.x,limits.y]
	# Free interval ends come from the world, construction footprints and other
	# props. Finite candidates replace the old unbounded outward-pushing loop.
	for other in moving+fixed:
		candidates.append(float(other.position.x))
		if int(other.index)==int(entry.index): continue
		var space := radius+_foot_radius(other)+12.0
		candidates.append(other.position.x-space-1.0)
		candidates.append(other.position.x+space+1.0)
	for center in centers:
		candidates.append(center-56.0-radius-1.0)
		candidates.append(center+56.0+radius+1.0)
	candidates.sort_custom(func(a: float,b: float) -> bool:
		var da := absf(a-original)
		var db := absf(b-original)
		return a<b if is_equal_approx(da,db) else da<db)
	var tried: Dictionary = {}
	for candidate in candidates:
		if candidate<limits.x or candidate>limits.y or tried.has(candidate): continue
		tried[candidate] = true
		var valid := true
		for center in centers:
			if absf(candidate-center)<56.0+radius: valid = false; break
		if not valid: continue
		for other in fixed:
			if absf(candidate-other.position.x)<radius+_foot_radius(other)+12.0: valid = false; break
		if not valid: continue
		var placed := entry.duplicate()
		placed.position = Vector2(candidate,entry.position.y)
		var next_fixed: Array[Dictionary] = fixed.duplicate()
		next_fixed.append(placed)
		var remainder := _place_group(moving,next_fixed,centers,left,right,offset+1)
		if not remainder.is_empty():
			remainder[int(entry.index)] = candidate
			return remainder
	return {}
