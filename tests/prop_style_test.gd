extends SceneTree
## Actual fixture animation, planted supports, cosmetic damage and near-zoom cover.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const Fixture := preload("res://scripts/scenery_fixture_art.gd")
const Layout := preload("res://scripts/background_layout.gd")
const PropPainter := preload("res://scripts/scenario_prop_art.gd")
const Damage := preload("res://scripts/scenery_damage.gd")
const MOVING := ["signal","ore_cart","bollard","generator","pump","transformer","relay_antenna","crane_hook","cargo_beacon"]
var checks := 0
var failures := 0
class Probe extends Node2D:
	var clock := 0.0
	var kind := "signal"
	func _draw() -> void:
		PropPainter.draw(self,{"kind":kind,"position":Vector2.ZERO,"tint":Color("79939f"),"accent":Color("cba266"),"phase":.7},clock,1,1)
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(label)
func image_of(view: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image
func difference(a: Image,b: Image,rect: Rect2i) -> int:
	var changes:=0
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var ac:=a.get_pixel(x,y)
			var bc:=b.get_pixel(x,y)
			if maxf(absf(ac.r-bc.r),maxf(absf(ac.g-bc.g),maxf(absf(ac.b-bc.b),absf(ac.a-bc.a))))>.025: changes+=1
	return changes
func render_fixture(kind: String) -> void:
	var view:=SubViewport.new()
	view.size=Vector2i(220,160)
	view.transparent_bg=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var probe:=Probe.new()
	probe.kind=kind
	probe.position=Vector2(110,140)
	probe.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var material:=ShaderMaterial.new()
	material.shader=preload("res://shaders/perimeter_pixel.gdshader")
	probe.material=material
	view.add_child(probe)
	var first:=await image_of(view)
	var movement:=0
	var stable:=true
	for time in [1.2,2.4,4.8,8.0]:
		probe.clock=time
		probe.queue_redraw()
		var later:=await image_of(view)
		movement=maxi(movement,difference(first,later,Rect2i(45,20,130,113)))
		stable=stable and difference(first,later,Rect2i(45,134,130,6))==0
	check(movement>=4,kind+" visibly animates using the actual shader and renderer (%d changed pixels)"%movement)
	check(stable,kind+" keeps base and floor contact at fixed pixels")
	var underground:=0
	for y in range(140,160):
		for x in range(220):
			if first.get_pixel(x,y).a>.1: underground+=1
	check(underground==0,kind+" has no painted pixels below its floor anchor")
	view.queue_free()
	await process_frame
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	root.size=Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	var found: Dictionary={}
	for environment in ScenarioCatalog.environments(true):
		for placement in ["left","center","right"]:
			var game=load("res://scenes/main.tscn").instantiate()
			root.add_child(game)
			current_scene=game
			game.start_scenario(1,{"environment":environment.id,"position":placement,"build_type":"bastion"})
			game.rounds.set_process(false)
			game.rounds.running=false
			game.set_process(false)
			game.player_camera.set_process(false)
			for i in 3: await physics_frame
			var props=game.scenery.props_layer
			var new_count:=0
			for entry in props.entries:
				if not entry.kind in Fixture.KINDS: continue
				new_count+=1
				found[entry.kind]=true
				check(entry.animated and entry.position.y==430.0,entry.kind+" is animated and stands on the actual outdoor floor")
				check(not props.reactions.state_for(entry.index).is_empty(),entry.kind+" has a registered cosmetic damage state")
				var shape:=Damage._shape(entry)
				check(not shape.rects.is_empty() and not shape.bounds.size.is_zero_approx(),entry.kind+" has finite damage geometry")
				var radius: float=entry.size.x*.5
				var clear: bool=entry.position.x+radius<props.bunker_left or entry.position.x-radius>props.bunker_right
				for site in game.perimeter.sites: clear=clear and absf(site.global_position.x-entry.position.x)>=56+radius
				check(clear,entry.kind+" leaves actual entrances and all active construction sites clear")
			check(new_count>=1,environment.id+"/"+placement+" includes new climate-appropriate fixtures")
			check(Damage.valid_states(props.reactions.states,props.entries),environment.id+" current fixture states are valid for replica snapshots")
			var before: float=props.elapsed
			paused=true
			props._process(.5)
			check(props.elapsed==before,"Pause freezes fixture animation")
			paused=false
			game.weather.reduced_effects=true
			props._process(.4)
			check(is_equal_approx(props.elapsed-before,.1) and is_equal_approx(props._motion_scale,.24),"F3 reduces actual fixture clock and wind motion")
			check(await Cleanup.free_scene(game,self),"Fixture scenario teardown releases its nodes and playback")
	check(found.size()==Fixture.KINDS.size(),"All six new fixture types appear in actual scenes")
	for screen in [Vector2(960,600),Vector2(1440,900),Vector2(2560,1440),Vector2(3440,1440),Vector2(900,1440)]:
		for center in [Vector2(160,335),Vector2(720,200),Vector2(1710,335),Vector2(720,760)]:
			for zoom in [.25,.45,1.0,1.25,2.0,2.5]:
				var view:=Rect2(center-screen/zoom*.5,screen/zoom).grow(64)
				var frame:=Layout.frame(view,1672.0/941.0,zoom)
				var above:=Rect2(view.position,Vector2(view.size.x,maxf(0,430-view.position.y)))
				check(above.size.y==0 or frame.encloses(above),"Adaptive near-zoom background covers all above-ground view edges")
	var close_view:=Rect2(Vector2(990,340)-Vector2(1440,900)/2.5*.5,Vector2(1440,900)/2.5).grow(64)
	var close:=Layout.frame(close_view,1672.0/941.0,2.5)
	check(close.size.x*2.5/1672.0<1.4,"Maximum follow zoom limits background source magnification to under 1.4x at 1440x900")
	var normal_view:=Rect2(Vector2.ZERO,Vector2(1440,900)).grow(64)
	var normal:=Layout.frame(normal_view,1672.0/941.0)
	check(normal.size.x*1.16/1672.0<1.35,"Normal camera reveals source detail including parallax overscan, instead of doubling background texels")
	var live_game=load("res://scenes/main.tscn").instantiate()
	root.add_child(live_game)
	current_scene=live_game
	live_game.start_scenario(1,{"environment":"frozen_rail_yard","position":"left","build_type":"bastion"})
	live_game.rounds.set_process(false)
	live_game.rounds.running=false
	live_game.players[0].set_physics_process(false)
	for i in 3: await physics_frame
	for target in [.45,2.5,1.25,.45,2.5]:
		live_game.player_camera.set_zoom(target)
		live_game.players[0].position=Vector2(955 if target>1 else 1450,430)
		for i in 4:
			await process_frame
			if DisplayServer.get_name()!="headless": await RenderingServer.frame_post_draw
			var view: Rect2=live_game.scenery.get_global_transform_with_canvas().affine_inverse()*root.get_visible_rect()
			var above:=Rect2(view.position,Vector2(view.size.x,maxf(0,430-view.position.y)))
			check(above.size.y==0 or live_game.scenery.panorama_rect.encloses(above),"Live follow-camera changes stay covered in the actual displayed frame")
	check(live_game.scenery.panorama.texture_filter==CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS and live_game.scenery.props_layer.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Only distant panorama filtering changes; foreground props keep their pixel filter")
	check(await Cleanup.free_scene(live_game,self),"Live zoom fixture releases its resources")
	if DisplayServer.get_name()!="headless":
		for kind in MOVING: await render_fixture(kind)
	print("PROP STYLE: %d/%d checks passed%s"%[checks-failures,checks," (rendered animation included)" if DisplayServer.get_name()!="headless" else ""])
	quit(1 if failures else 0)
