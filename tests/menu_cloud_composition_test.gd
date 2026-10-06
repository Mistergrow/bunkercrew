extends SceneTree
## Pure cloud geometry: catch period-wrap jumps before the rendered gallery.
const Clouds := preload("res://scripts/menu_cloud_composition.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func displaced(before: Array[Dictionary], after: Array[Dictionary], distance: float) -> bool:
	var matched := 0
	for old: Dictionary in before:
		for current: Dictionary in after:
			if old.row != current.row or old.tile != current.tile: continue
			matched += 1
			# Rect2 stores float32 coordinates; allow sub-pixel rounding.
			if absf(current.rect.position.x-old.rect.position.x-distance)>.002: return false
			if old.rect.position.y!=current.rect.position.y or old.rect.size!=current.rect.size: return false
			if old.mirror!=current.mirror or old.alpha!=current.alpha: return false
	return matched>0

func run() -> void:
	var panorama := Rect2(-144,-86,1728,576)
	var view := Rect2(-700,-500,2500,1050)
	var signatures: Dictionary = {}
	for environment: String in Clouds.LAYOUTS:
		var signature := JSON.stringify(Clouds.LAYOUTS[environment])
		check(not signatures.has(signature), "Climate has its own full three-plane composition: " + environment)
		signatures[signature] = true
		for depth in 3:
			var period := Clouds.period(environment, depth)
			var before := Clouds.tiles(environment, depth, view, panorama, period-.05)
			var after := Clouds.tiles(environment, depth, view, panorama, period+.05)
			check(not before.is_empty() and before.size()<=24, "Visible menu plane has a bounded drawing budget: %s/%d" % [environment,depth])
			check(displaced(before,after,.1), "Period crossing preserves altitude, size, silhouette and opacity: %s/%d" % [environment,depth])
			var full_period := Clouds.tiles(environment,depth,view,panorama,period*2.0-.05)
			check(displaced(before,full_period,period), "Same cloud retains its identity after one complete travel period: %s/%d" % [environment,depth])
			var returning := Clouds.tiles(environment,depth,view,panorama,period-.05)
			check(returning==before and displaced(after,returning,-.1), "Reversed drift retraces geometry without swapping clouds: %s/%d" % [environment,depth])
			check(returning==Clouds.tiles(environment,depth,view,panorama,period-.05), "A paused clock and airflow preserve exact geometry")
			var distant := Clouds.tiles(environment, depth, view, panorama, 100000.0)
			var valid := not distant.is_empty() and distant.size()<=24
			for bank: Dictionary in distant:
				valid = valid and bank.rect.has_area() and bank.rect.position.is_finite() and bank.rect.intersects(view) and bank.alpha>0.0 and bank.alpha<=1.0
			check(valid, "Long menu sessions retain finite culled geometry: %s/%d" % [environment,depth])
	for depth in 3:
		check(Clouds.layer("storm_dam",depth).alpha>Clouds.layer("basalt_quarry",depth).alpha*1.5, "Storm coverage differs materially from the open quarry sky")
		for mirrored in [false,true]:
			var uv := Clouds.source_uvs(depth,mirrored)
			var correct := uv.size()==4
			for point in uv: correct = correct and floori(point.y*3.0)==depth and point.x in [0.0,1.0]
			correct = correct and (uv[0].x>uv[1].x)==mirrored
			check(correct,"Every atlas polygon vertex stays inside the selected row, including mirrored copies")
	print("MENU CLOUD COMPOSITION: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
