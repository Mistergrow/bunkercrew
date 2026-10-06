extends SceneTree
## Real native props at 2x plus prepared scenes at normal and maximum follow zoom.
const PropPainter := preload("res://scripts/scenario_prop_art.gd")
const Catalog := preload("res://scripts/scenario_prop_catalog.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const KINDS := ["signal","ore_cart","bollard","tape","vines","fan","cable","windsock","pipe","generator","pump","transformer","relay_antenna","crane_hook","cargo_beacon"]
var output := "res://artifacts/prop-style/after/"
class Probe extends Node2D:
	var clock := 0.0
	var kind := "signal"
	func _draw() -> void:
		PropPainter.draw(self,{"position":Vector2.ZERO,"kind":kind,"tint":Color("79939f"),"accent":Color("cba266"),"foliage":Color("89a167"),"phase":.7},clock,1,1)
class Board extends Node2D:
	var clock := 0.0
	var kinds: Array = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("172126"))
		var font := ThemeDB.fallback_font
		draw_string(font,Vector2(24,28),"BUNKERCREW · REQUISITEN · 2×",HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("dbd6bd"))
		for i in kinds.size():
			var at := Vector2(144+288*(i%5),290+280*floori(i/5.0))
			draw_line(at-Vector2(125,0),at+Vector2(125,0),Color("516057"))
			draw_string(font,at+Vector2(-120,24),kinds[i],HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("d6cfb4"))
func _initialize() -> void: run.call_deferred()
func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output="res://"+arg.trim_prefix("--output=")+"/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	LocaleText.set_locale("de",false)
	root.size=Vector2i(1440,900)
	AudioServer.set_bus_mute(0,true)
	var board:=Board.new()
	board.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	board.kinds=KINDS
	root.add_child(board)
	for i in KINDS.size():
		var probe:=Probe.new()
		probe.kind=KINDS[i]
		probe.position=Vector2(144+288*(i%5),290+280*floori(i/5.0))
		probe.scale=Vector2.ONE*2
		board.add_child(probe)
	var video := "--video" in OS.get_cmdline_user_args()
	for frame in (360 if video else 3):
		var clock: float = frame/30.0 if video else [0.0,1.2,2.4][frame]
		board.clock=clock
		board.queue_redraw()
		for probe in board.get_children():
			probe.clock=clock
			probe.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var capture:=root.get_texture().get_image()
		capture.save_png(output+("motion-%03d.png"%frame if video else "props-%.1f.png"%clock))
		if video and frame in [0,36,72]: capture.save_png(output+"props-%.1f.png"%clock)
	board.queue_free()
	await process_frame
	for id in ["frozen_rail_yard","abandoned_harbor","overgrown_steelworks","ash_foundry","storm_dam","basalt_quarry","radar_highlands"]:
		var game=load("res://scenes/main.tscn").instantiate()
		root.add_child(game)
		current_scene=game
		game.start_scenario(1,{"environment":id,"build_type":"bastion","position":"left"})
		game.rounds.set_process(false)
		game.rounds.running=false
		game.set_process(false)
		game.player_camera.set_process(false)
		game.notice_time=0
		for i in 5: await physics_frame
		for zoom in [1.0,2.5]:
			game.camera.position=Vector2(720,450) if zoom==1.0 else Vector2(990,340)
			game.camera.zoom=Vector2.ONE*zoom
			game.camera.force_update_scroll()
			game.players[0].position=Vector2(955,430)
			game.players[0].set_physics_process(false)
			game.scenery._process(0)
			game.scenery.props_layer._process(.1)
			for i in 3: await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output+id+("-normal.png" if zoom==1 else "-close.png"))
		await Cleanup.free_scene(game,self)
	print("PROP STYLE PREVIEW: native board plus seven prepared normal/close scenes")
	quit()
