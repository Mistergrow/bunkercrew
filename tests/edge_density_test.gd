extends SceneTree
## Black-box footprint/height progression, stable camera populations and real
## reduced meshes. Sprite footprints measure width, not conservative bounds or
## opaque atlas pixels; native image review complements these geometric checks.
const CATALOG := preload("res://scripts/living_ecology_catalog.gd")
const OUTSKIRTS := preload("res://scripts/vegetation_outskirts.gd")
const STRATA := preload("res://scripts/terrain_strata.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const HABITATS := ["flooded_power_station","iron_canyon","frozen_rail_yard"]
const DISTANCE_BANDS := [Vector2(50,350),Vector2(350,650),Vector2(950,1250)]
# Ground footprints can already close completely in the transition. These
# fixed upper-thicket lines ask whether the added cover fills vertical space,
# while respecting the shorter native snow/thorn silhouettes.
const CANOPY_HEIGHTS := {"flooded_power_station":80.0,"iron_canyon":60.0,"frozen_rail_yard":45.0}
var checks := 0
var failures := 0

class World extends Node2D:
	var scenario_bunker: Node

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _band(occupied: Vector2,side: int,distance: Vector2) -> Vector2:
	return Vector2(occupied.x-distance.y,occupied.x-distance.x) if side<0 else Vector2(occupied.y+distance.x,occupied.y+distance.y)

func _union_coverage(intervals: Array[Vector2],band: Vector2) -> float:
	intervals.sort_custom(func(a: Vector2,b: Vector2) -> bool: return a.x<b.x)
	var covered := 0.0
	var end := band.x
	for interval: Vector2 in intervals:
		covered+=maxf(0.0,interval.y-maxf(end,interval.x))
		end = maxf(end,interval.y)
	return covered/(band.y-band.x)

func _metrics(entries: Array,band: Vector2,canopy_height: float) -> Dictionary:
	var intervals: Array[Vector2] = []
	var canopy: Array[Vector2] = []
	var height_sum := 0.0
	var count := 0
	var regions := CATALOG.asset_regions()
	for entry: Dictionary in entries:
		if not bool(entry.get("structural",entry.get("reduced_visible",false))): continue
		var position: Vector2 = entry.position
		var size: Vector2 = entry.size
		if position.x>=band.x and position.x<band.y:
			height_sum+=size.y
			count+=1
		var region: Dictionary = regions[entry.species]
		var rect: Rect2 = region.rect
		var anchor: Vector2 = region.root
		var ratio: float = (anchor.x-rect.position.x)/rect.size.x
		if bool(entry.mirror): ratio = 1.0-ratio
		var left := maxf(band.x,position.x-size.x*ratio)
		var right := minf(band.y,position.x+size.x*(1.0-ratio))
		if right>left:
			intervals.append(Vector2(left,right))
			if size.y>=canopy_height: canopy.append(Vector2(left,right))
	return {"coverage":_union_coverage(intervals,band),"upper_coverage":_union_coverage(canopy,band),"height":height_sum/maxi(1,count),"anchors":count}

func _identities(entries: Array,chunk: int) -> Array[String]:
	var result: Array[String] = []
	for entry: Dictionary in entries:
		if int(entry.chunk)!=chunk: continue
		result.append(var_to_str(_identity(entry)))
	result.sort()
	return result

func _base_intervals(outskirts: Node2D) -> Array[Vector2]:
	var intervals: Array[Vector2] = []
	for batch: MeshInstance2D in outskirts._batches:
		if not batch.visible: continue
		for surface in batch.mesh.get_surface_count():
			var arrays: Array = batch.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for index in range(vertices.size()-1):
				var a := vertices[index]
				var b := vertices[index+1]
				if is_equal_approx(a.y,CATALOG.GROUND_Y) and is_equal_approx(b.y,CATALOG.GROUND_Y):
					intervals.append(Vector2(minf(a.x,b.x),maxf(a.x,b.x)))
	return intervals

func _root_drawn(position: Vector2,intervals: Array[Vector2]) -> bool:
	for interval: Vector2 in intervals:
		if position.x>=interval.x and position.x<=interval.y: return true
	return false

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	var occupied := Vector2(CATALOG.GROUND_LEFT,CATALOG.GROUND_RIGHT)
	var slabs: Array[Rect2] = [Rect2(STRATA.FIELD.position.x,CATALOG.GROUND_Y,STRATA.FIELD.size.x,1)]
	for habitat: String in HABITATS:
		# A whole-terrain view provides the same habitat's near, transition and
		# deep outer growth. No seed, slot count or interpolation formula is copied.
		var broad := CATALOG.outskirts_layout(habitat,Vector2i(-17,18),slabs,occupied)
		for side: int in [-1,1]:
			var metrics: Array[Dictionary] = []
			for distance: Vector2 in DISTANCE_BANDS:
				metrics.append(_metrics(broad.plants,_band(occupied,side,distance),float(CANOPY_HEIGHTS[habitat])))
			var label := "%s %s"%[habitat,"west" if side<0 else "east"]
			print("EDGE METRICS %s: %s"%[label,JSON.stringify(metrics)])
			check(metrics.all(func(value: Dictionary) -> bool: return int(value.anchors)>0),label+": all three distance bands have actual planted structural anchors")
			check(float(metrics[1].coverage)>float(metrics[0].coverage)+.1 and float(metrics[2].coverage)>=float(metrics[1].coverage)-.015,label+": actual-width shrub/reed footprints close the outer verge and preserve cover after ground-footprint saturation")
			check(float(metrics[1].upper_coverage)>float(metrics[0].upper_coverage)+.015 and float(metrics[2].upper_coverage)>float(metrics[1].upper_coverage)+.015,label+": actual-width upper-thicket footprints progressively fill higher vertical space")
			check(float(metrics[1].height)>float(metrics[0].height)*1.08 and float(metrics[2].height)>float(metrics[1].height)*1.08,label+": structural silhouettes grow higher through the transition and deep thicket")
		# Complete outer chunks must survive a 36-chunk budget-pressure view.
		# Equal identities against isolated views catch a left-to-right cap that
		# silently removes the eastern edge, without requiring a particular count.
		for chunk: int in [-15,-12,-8,8,14,17]:
			var isolated := CATALOG.outskirts_layout(habitat,Vector2i(chunk,chunk),slabs,occupied)
			for family: String in ["plants","trees"]:
				var expected := _identities(isolated[family],chunk)
				check(not expected.is_empty() and _identities(broad[family],chunk)==expected,"%s %s chunk%d: broad view retains the complete same world population on either side"%[habitat,family,chunk])
		var game := World.new()
		game.scenario_bunker = Node.new()
		game.add_child(game.scenario_bunker)
		root.add_child(game)
		var outskirts := OUTSKIRTS.new()
		outskirts.configure(game,habitat)
		game.add_child(outskirts)
		for side: int in [-1,1]:
			var first_view := Rect2(-5500,60,2000,700) if side<0 else Rect2(4500,60,2000,700)
			var next_view := first_view
			next_view.position.x+=700.0
			outskirts.update_view(first_view,false,2.0,.7)
			var first: Dictionary = outskirts.diagnostics()
			var entries: Array = (outskirts.plants+outskirts.trees).duplicate(true)
			outskirts.update_view(next_view,false,3.0,.9)
			var next: Dictionary = outskirts.diagnostics()
			for chunk in range(maxi(int(first.chunk_first),int(next.chunk_first)),mini(int(first.chunk_last),int(next.chunk_last))+1):
				var expected := _identities(entries,chunk)
				check(not expected.is_empty() and _identities(outskirts.plants+outskirts.trees,chunk)==expected,"%s: overlapping %s camera spans preserve complete chunk%d positions, sizes and wind phases"%[habitat,"west" if side<0 else "east",chunk])
		outskirts.update_view(Rect2(STRATA.FIELD.position.x,60,STRATA.FIELD.size.x,700),false,4.0,.7)
		var full: Dictionary = outskirts.diagnostics()
		var arrangement := var_to_str([outskirts.plants,outskirts.trees])
		var anchors: Array[Dictionary] = []
		for entry: Dictionary in outskirts.plants+outskirts.trees:
			if bool(entry.get("structural",false)): anchors.append(entry)
		check(not anchors.is_empty() and int(full.mesh_batches)<=9 and int(full.materials)==2,habitat+": dense full terrain has structural silhouettes within nine shared meshes and two materials")
		outskirts.update_view(Rect2(STRATA.FIELD.position.x,60,STRATA.FIELD.size.x,700),true,4.0,.7)
		var reduced: Dictionary = outskirts.diagnostics()
		var bases := _base_intervals(outskirts)
		check(int(reduced.rebuilds)==int(full.rebuilds) and var_to_str([outskirts.plants,outskirts.trees])==arrangement,habitat+": F3 changes prepared meshes without moving or rebuilding any outer anchor")
		check(int(reduced.active_plants)<int(full.active_plants),habitat+": F3 still removes optional companion vegetation")
		for anchor: Dictionary in anchors:
			check(bool(anchor.reduced_visible) and _root_drawn(anchor.position,bases),habitat+": F3 keeps each actual structural shrub/reed/tree root in submitted mesh geometry")
		# A visible tall crown still needs its mesh when its root is below the
		# camera. This catches the old 220px vertical cull after height growth.
		var tallest: Dictionary = {}
		for tree: Dictionary in outskirts.trees:
			if tallest.is_empty() or float(tree.size.y)>float(tallest.size.y): tallest = tree
		check(not tallest.is_empty() and float(tallest.size.y)>220.0 and float(tallest.size.y)<=360.0,habitat+": the far canopy has bounded tall structural silhouettes")
		if not tallest.is_empty():
			var crown_view := Rect2(float(tallest.position.x)-30,float(tallest.position.y)-float(tallest.size.y)+8,60,20)
			outskirts.update_view(crown_view,false,5.0,.7)
			check(not outskirts.trees.is_empty() and _identities(outskirts.trees,int(tallest.chunk)).has(var_to_str(_identity(tallest))),habitat+": a visible crown retains its actual tree when the ground root is offscreen")
		check(await CLEANUP.free_scene(game,self),habitat+": dense/reduced/view-shift fixtures release all owning nodes and meshes")
	print("EDGE DENSITY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func _identity(entry: Dictionary) -> Dictionary:
	var identity: Dictionary = {}
	for key: String in ["species","position","size","phase","stiffness","mirror","depth","reduced_visible","bounds","structural","growth"]:
		if entry.has(key): identity[key] = entry[key]
	return identity
