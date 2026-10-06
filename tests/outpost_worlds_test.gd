extends SceneTree
## Real four campaign-only worlds, original panoramas and authored sky masks.
const IDS: Array[String]=["storm_dam","sulfur_refinery","radar_highlands","buried_megafactory"]
const Skyline:=preload("res://scripts/cloud_skyline.gd")
const Props:=preload("res://scripts/scenario_prop_catalog.gd")
const Wind:=preload("res://scripts/world_wind.gd")
const Terrain:=preload("res://scripts/terrain_strata.gd")
const Cleanup:=preload("res://tests/scene_cleanup.gd")
var checks:=0
var failures:=0
var view: SubViewport

func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	else: print("OUTPOST PASS: ",label)

func run() -> void:
	var capture: bool="--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name()!="headless"
	root.size=Vector2i(1600,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	check(ScenarioCatalog.environments().size()==9,"Nine free-start worlds remain within existing selection layout")
	check(ScenarioCatalog.environments(true).size()==13,"Four extra campaign worlds are registered")
	var hashes: Array[String]=[]
	for id in IDS:
		var spec:=ScenarioCatalog.environment(id)
		check(spec.id==id and bool(spec.campaign_only),id+" resolves without default-world fallback")
		check(ScenarioCatalog.validate({"environment":id}).environment==id,id+" is a valid campaign arrival")
		var texture:=ScenarioCatalog.texture(str(spec.path))
		check(texture!=null and texture.get_width()>=2000 and texture.get_height()>=700,id+" has its own full-size panorama")
		var digest:=FileAccess.get_sha256(str(spec.path))
		check(not digest in hashes,id+" original panorama is distinct")
		hashes.append(digest)
		check(ScenarioScenery.PROFILES.has(id) and Props.PROFILES.has(id) and Wind.PROFILES.has(id) and Terrain.PROFILES.has(id),id+" has atmosphere, vegetation, wind and geological profiles")
		var mask:=Skyline.texture(id)
		check(mask!=null and mask.get_size()==texture.get_size(),id+" has a source-sized cloud occlusion mask")
		var outline:=Skyline.points(id)
		var ordered:=outline.size()>20
		for index in range(1,outline.size()): ordered=ordered and outline[index].x>outline[index-1].x
		check(ordered,id+" skyline anchors advance monotonically")
		var game=load("res://scenes/main.tscn").instantiate()
		view.add_child(game)
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.running=false
		for unused in 5:
			await physics_frame
			await process_frame
		check(game.scenery.environment_id==id and game.scenery.panorama.texture==texture,id+" actually renders the requested world")
		check(game.weather.environment_id==id,id+" configures its actual weather")
		check(game.scenery.cloud_layers.size()==3 and game.scenery.cloud_speed(0)<game.scenery.cloud_speed(1) and game.scenery.cloud_speed(1)<game.scenery.cloud_speed(2),id+" has three independently moving cloud depths")
		check(not game.scenery.props_layer.entries.is_empty(),id+" places matching ground vegetation and props")
		if id=="storm_dam":
			check(game.scenery._has_surface and not spec.waterfall_regions.is_empty(),"Dam activates waterfall and reservoir animation")
			check(not game.scenery.distant_water.enabled,"Raised reservoir does not flood distant ground outside the dam")
			check(game.weather.lightning_enabled,"Dam storm includes enabled lightning")
		game.notice=""
		game.notice_time=0
		game.camera.position=Vector2(720,205)
		game.camera.zoom=Vector2.ONE
		game.camera.reset_smoothing()
		game.camera.force_update_scroll()
		game.camera.set_process(false)
		if capture:
			for unused in 3: await process_frame
			await RenderingServer.frame_post_draw
			var rendered:=view.get_texture().get_image()
			var colored:=0
			for x in range(100,2560,250):
				for y in range(100,1440,200):
					if rendered.get_pixel(x,y).get_luminance()>.015: colored+=1
			check(colored>30,id+" QHD capture contains a rendered world")
			check(rendered.save_png("res://artifacts/expedition/outpost-"+id+".png")==OK,id+" QHD capture saved")
		paused=false
		await Cleanup.free_scene(game,self)
	print("OUTPOST WORLDS: ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
