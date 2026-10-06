extends SceneTree
## Prepared real main scene: accepted terminal contacts, then identical paused
## body poses under each local violence setting. No gameplay outcome is staged
## by deleting limbs directly.
var game
var view: SubViewport
var output:="res://artifacts/combat-gore/"
var renderer:="compatibility"
var checks:=0
var failures:=0
func _initialize(): run.call_deferred()
func check(value: bool,label: String):
	checks+=1
	print("GORE PREVIEW ","PASS " if value else "FAIL ",label)
	if not value:
		failures+=1
		push_error(label)
func frames(count: int):
	for index in count: await process_frame
func capture(label: String):
	await frames(2)
	await RenderingServer.frame_post_draw
	var image:=view.get_texture().get_image()
	check(image.get_size()==Vector2i(2560,1440),label+" is native QHD")
	check(image.save_png(output+renderer+"-"+label+".png")==OK,label+" saved")
func run():
	renderer="vulkan" if RenderingServer.get_current_rendering_driver_name()=="vulkan" else "compatibility"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1440,900)
	view=SubViewport.new()
	view.size=Vector2i(2560,1440)
	view.size_2d_override=Vector2i(1600,900)
	view.size_2d_override_stretch=true
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.world_2d=World2D.new()
	root.add_child(view)
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(2,{"environment":"sector07","position":"left","build_type":"workshop"})
	game.rounds.set_process(false)
	game.story.enabled=false
	game.dialogue.reset()
	game.hud.visible=false
	game.set_process(false)
	game.set_physics_process(false)
	game.player_camera.set_process(false)
	game.player_camera.set_physics_process(false)
	game.medic.set_physics_process(false)
	game.turret.set_physics_process(false)
	for player in game.players: player.set_physics_process(false)
	var player=game.players[0]
	player.position=Vector2(1010,430)
	game.players[1].position=Vector2(930,430)
	var soldier=preload("res://scenes/ground_infantry.tscn").instantiate()
	soldier.kind="rifle_guard"
	soldier.position=Vector2(1090,430)
	soldier.game=game
	game.add_child(soldier)
	soldier.set_physics_process(false)
	soldier.moving=false
	soldier.stance=.2
	soldier._pose_parts()
	game.camera.zoom=Vector2.ONE*4.0
	game.camera.position=Vector2(1030,386)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
	await frames(4)
	var Gore=preload("res://scripts/combat_gore.gd")
	var rig: Dictionary=Gore._rig(soldier)
	ImpactBurst.contact(game,soldier,rig[8].tip,Vector2.LEFT,Vector2.RIGHT,1.0,"cannon")
	soldier.take_damage(999)
	var p_rig: Dictionary=Gore._rig(player)
	ImpactBurst.contact(game,player,p_rig[2].tip,Vector2.RIGHT,Vector2.LEFT,1.0,"cannon")
	player.take_damage(999,Vector2.LEFT)
	player.medical.down_elapsed=.95
	player.get_node("PixelVisual")._process(0.0)
	for body in get_nodes_in_group("infantry_remains"):
		body._process(.6)
		body.set_process(false)
	game.combat_gore.set_physics_process(false)
	for step in 11: game.combat_gore._physics_process(1.0/60.0)
	check(game.combat_gore.parts.size()==2,"Both genuine terminal contacts created one native limb")
	check(player.is_downed() and player.gore_mask>0,"Prepared crew state remains medically recoverable")
	paused=true
	await capture("full")
	game.combat_gore.set_level(1)
	await capture("blood")
	game.combat_gore.set_level(0)
	await capture("off")
	check(game.combat_gore.parts.is_empty() and game.combat_gore.particles.is_empty() and game.combat_gore.stains.is_empty(),"Off removes every human effect immediately")
	paused=false
	check(await preload("res://tests/scene_cleanup.gd").free_scene(game,self),"Prepared main scene closes cleanly")
	view.queue_free()
	await process_frame
	print("GORE PREVIEW: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
