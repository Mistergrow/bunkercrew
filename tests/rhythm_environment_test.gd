extends SceneTree
## The music pulse changes existing shader pixels without redraw or extra calls.
const Layers := preload("res://scripts/parallax_landscape.gd")
const Catalog := preload("res://scripts/parallax_catalog.gd")
const Effects := preload("res://scripts/station_shader_effects.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")

class Fixture extends Node2D:
	func sound(_kind): pass
	func fx(_position,_color,_count): pass

var checks := 0
var failures := 0
var viewport: SubViewport

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func capture() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func _compare(before: Image,after: Image) -> Dictionary:
	var a := before.get_data()
	var b := after.get_data()
	var alpha_same := true
	var changed := 0
	for offset in range(0,a.size(),4):
		if a[offset+3] != b[offset+3]: alpha_same = false
		if a[offset] != b[offset] or a[offset+1] != b[offset+1] or a[offset+2] != b[offset+2]: changed+=1
	return {"alpha_same":alpha_same,"changed":changed}

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Environment shader validation requires real rendering")
		quit(1)
		return
	viewport=SubViewport.new()
	viewport.size=Vector2i(500,310)
	viewport.world_2d=World2D.new()
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/rhythm-music/environment"))
	var level_results: Dictionary = {}
	for id: String in Catalog.PROFILES:
		var scene := Layers.new()
		scene.configure(id)
		viewport.add_child(scene)
		scene.update_view(Rect2(0,0,500,310),Rect2(0,0,500,310),8.0,false)
		var fixture_draws := [0]
		for sprite in scene.layers:
			sprite.draw.connect(func(): fixture_draws[0]+=1)
		RenderingServer.global_shader_parameter_set("beat_pulse",0.0)
		var fixture_before := await capture()
		var draw_count: int=fixture_draws[0]
		var fixture_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		RenderingServer.global_shader_parameter_set("beat_pulse",1.0)
		var fixture_after := await capture()
		var fixture_comparison := _compare(fixture_before,fixture_after)
		check(fixture_comparison.alpha_same,id+" pulse preserves every skyline alpha pixel")
		check(fixture_draws[0]==draw_count,id+" pulse never invalidates canvas drawing")
		check(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)==fixture_calls,id+" pulse adds zero draw calls")
		fixture_before.save_png("res://artifacts/rhythm-music/environment/"+id+"-quiet.png")
		fixture_after.save_png("res://artifacts/rhythm-music/environment/"+id+"-beat.png")
		level_results[id]={"changed_pixels":fixture_comparison.changed,"draw_calls":fixture_calls,"alpha_unchanged":fixture_comparison.alpha_same}
		await Cleanup.free_scene(scene,self)
	check(level_results.ash_foundry.changed_pixels>10,"Ash foundry's existing warm emitters visibly follow the beat")
	var fixture := Fixture.new()
	viewport.add_child(fixture)
	var station = load("res://scenes/station.tscn").instantiate()
	station.kind="furnace"
	station.game=fixture
	station.position=Vector2(250,270)
	fixture.add_child(station)
	station.set_process(false)
	station.working=true
	station.elapsed=2.4
	var effects = station.get_node("MaterialEffects")
	await capture()
	effects.set_process(false)
	effects._refresh()
	RenderingServer.global_shader_parameter_set("beat_pulse",0.0)
	var before := await capture()
	var draws := [0]
	station.draw.connect(func(): draws[0]+=1)
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	RenderingServer.global_shader_parameter_set("beat_pulse",1.0)
	var after := await capture()
	var comparison := _compare(before,after)
	check(comparison.alpha_same and comparison.changed>30,"Furnace pulse lights existing surface without changing its silhouette")
	check(draws[0]==0,"Furnace pulse needs no new procedural drawing")
	check(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)==calls,"Furnace pulse adds zero draw calls")
	before.save_png("res://artifacts/rhythm-music/environment/furnace-quiet.png")
	after.save_png("res://artifacts/rhythm-music/environment/furnace-beat.png")
	RenderingServer.global_shader_parameter_set("beat_pulse",0.0)
	var file := FileAccess.open("res://artifacts/rhythm-music/environment-verification.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"levels":level_results},"\t"))
	await Cleanup.free_scene(viewport,self)
	print("RHYTHM ENVIRONMENT: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
