extends SceneTree
const Cleanup := preload("res://tests/scene_cleanup.gd")
var checks := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
	print("WIDE SKY %s: %s"%["PASS" if ok else "FAIL",label])

func run() -> void:
	for spec: Dictionary in ScenarioCatalog.environments():
		var game = load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		game.start_scenario(1,{"environment":spec.id,"build_type":"bastion","position":"center"})
		game.rounds.set_process(false)
		var scenery: ScenarioScenery = game.scenery
		scenery.set_process(false)
		var vault: Node2D = scenery.upper_sky
		var fixed := scenery.panorama.transform
		check(vault.get_index()<scenery.cloud_layer.get_index(),"%s opaque sky stays behind moving clouds"%spec.id)
		check(scenery.distant_water.get_index()<scenery.distant_horizon.get_index() and scenery.distant_horizon.get_index()<scenery.panorama.get_index(),"%s extended water and shore stay behind original landmarks"%spec.id)
		for view: Rect2 in [Rect2(-1021,-955,3556,2000),Rect2(-2480,-1340,6400,3600),Rect2(-3500,-2050,8000,4000)]:
			vault.update_view(view)
			check(vault.visible and vault.bounds.position.y<=view.position.y and vault.bounds.position.x<=view.position.x and vault.bounds.end.x>=view.end.x,"%s upper sky covers the wide view"%spec.id)
			check(is_equal_approx(vault.bounds.end.y,430.0),"%s air fills behind new landscape without stretching painted land into sky"%spec.id)
			for depth in 3:
				var clouds := scenery.upper_cloud_tiles(depth,view)
				check(not clouds.is_empty() and clouds.size()<=96,"%s depth%d clouds exist above horizon at bounded cost"%[spec.id,depth])
				var valid := true
				for cloud in clouds:
					valid = valid and cloud.rect.intersects(view) and float(cloud.alpha)>0 and cloud.rect.position.y<-100
				check(valid,"%s depth%d culls offscreen upper clouds"%[spec.id,depth])
		var cloud_view := Rect2(-2000,-1800,5500,1700)
		for depth in 3:
			# Cross a full travel period: rectangles may enter/leave horizontally,
			# but existing cloud heights must not jump when the offset wraps.
			var period: float = [3100.0,2560.0,1980.0][depth]*.78
			scenery.elapsed = (period-depth*529.0)/scenery.cloud_speed(depth)-.005
			var before := scenery.upper_cloud_tiles(depth,cloud_view)
			scenery.elapsed += .01
			var after := scenery.upper_cloud_tiles(depth,cloud_view)
			var continuous := before.size()==after.size()
			for index in mini(before.size(),after.size()):
				continuous = continuous and before[index].rect.position.distance_to(after[index].rect.position)<=1.01
			check(continuous,"%s depth%d upper cloud wrap is continuous"%[spec.id,depth])
		check(scenery.panorama.transform==fixed,"%s broad sky leaves fixed landmarks untouched"%spec.id)
		vault.update_view(Rect2(0,700,1400,900))
		check(not vault.visible,"%s underground view culls upper sky entirely"%spec.id)
		if not await Cleanup.free_scene(game,self): failures += 1
	print("WIDE SKY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
