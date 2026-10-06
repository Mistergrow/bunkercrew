extends SceneTree
## Real main scene, prepared mount/aim/reload states; this is a presentation
## fixture, not an ordinary progression playthrough. --movie records 12 seconds.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const OUTPUT := "res://artifacts/mounted-workers/"
class Caption extends Control:
	var title := "Bedienpose · vorbereitete Spielsituation"
	var detail := "Originalfiguren · feste Füße · artikulierte Arme"
	func _draw() -> void:
		UiArt.panel(self,Rect2(25,660,780,65))
		UiArt.text(self,Vector2(42,686),title,17,UiArt.AMBER)
		UiArt.text(self,Vector2(42,710),detail,12,UiArt.IVORY)
var game
var view: Viewport
var render_view: SubViewport
var guns: Array=[]
var caption: Caption
var movie := false
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:
		failures+=1
		push_error(label)
	print("MOUNTED PREVIEW %s: %s"%["PASS" if value else "FAIL",label])
func frames(count: int=3) -> void:
	for unused in count: await process_frame
func pose(index: int,pitch: float,side: float=1,recoil: float=0,progress: float=-1) -> void:
	var gun=guns[index]
	gun.aim_angle=pitch if side>0 else -PI-pitch
	gun.recoil=recoil
	gun.reload_timer=gun.reload_duration()*(1-progress) if progress>=0 else 0
	gun.pose_barrel()
	gun.barrel.queue_redraw()
	gun.queue_redraw()
	var worker=game.players[index]
	worker.facing=gun.facing_direction()
	worker.global_position=gun.operator_position()
	worker.get_node("PixelVisual")._process(0)
func camera(detail: bool) -> void:
	game.camera.position=(guns[0].global_position+guns[1].global_position)*.5+Vector2(-25,-25) if detail else Vector2(720,270)
	game.camera.zoom=Vector2.ONE*(1.9 if detail else 1.0)
	game.camera.reset_smoothing()
	game.camera.force_update_scroll()
func capture(label: String) -> void:
	caption.queue_redraw()
	await frames()
	await RenderingServer.frame_post_draw
	var picture:=render_view.get_texture().get_image()
	check(picture.get_size()==Vector2i(2560,1440) and picture.save_png(OUTPUT+label+".png")==OK,label+" native QHD saved")
func run() -> void:
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args():
		quit(2)
		return
	movie="--movie" in OS.get_cmdline_user_args()
	root.size=Vector2i(1440,900)
	root.content_scale_size=Vector2i(1440,900)
	view=root
	if not movie:
		render_view=SubViewport.new()
		render_view.size=Vector2i(2560,1440)
		render_view.size_2d_override=Vector2i(1600,900)
		render_view.size_2d_override_stretch=true
		render_view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
		render_view.world_2d=World2D.new()
		root.add_child(render_view)
		view=render_view
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	game=load("res://scenes/main.tscn").instantiate()
	view.add_child(game)
	game.start_scenario(2,{"environment":"sector07","position":"center","build_type":"bastion"})
	game.combat_events.persistence_enabled=false
	game.set_process(false)
	game.rounds.running=false
	game.rounds.set_process(false)
	game.dialogue.reset()
	game.dialogue.set_process(false)
	game.audio.set_music_volume(0)
	game.audio.set_voice_volume(0)
	game.audio.set_sfx_volume(.70 if movie else 0.0)
	game.notice_time=0
	game.flak_station.unlock()
	game.flak_station._complete()
	game.notice_time=0
	guns=[game.turret,game.flak_station.turret]
	for index in 2:
		var worker=game.players[index]
		worker.set_physics_process(false)
		worker.get_node("PixelVisual").set_physics_process(false)
		guns[index].set_physics_process(false)
		guns[index].enter(worker)
		guns[index].ammo=10
		guns[index].reserve=50
	var layer:=CanvasLayer.new()
	layer.layer=90
	caption=Caption.new()
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.add_child(caption)
	game.add_child(layer)
	await frames(5)
	if movie:
		await record_movie()
	else:
		camera(false)
		pose(0,-.5)
		pose(1,-.85,-1)
		caption.title="Dachgeschütz + Flak · normale Spielgröße"
		await capture("qhd-gameplay-overview")
		camera(true)
		for identity in ["mara","branko","ivo"]:
			game.started=false
			for worker in game.players: check(worker.configure_character(identity),"Prepared "+identity+" identity applied")
			game.started=true
			caption.title=identity.capitalize()+" · Zielen und fest verankerte Füße · Detailansicht"
			pose(0,-.1)
			pose(1,-1.15,-1)
			await capture(identity+"-aim")
			caption.title=identity.capitalize()+" · Nachladen und Rückstoß · Detailansicht"
			pose(0,-.6,1,0,.52)
			pose(1,-.8,-1,7)
			await capture(identity+"-reload-recoil")
	for gun in guns: gun.exit()
	await Cleanup.free_scene(game,self)
	print("Mounted preview: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
func record_movie() -> void:
	camera(true)
	var fired:=0
	var reloads:=0
	for frame in 360:
		var segment:=floori(float(frame)/120.0)
		var local_frame:=frame%120
		var identity: String=["mara","branko","ivo"][segment]
		if local_frame==0:
			game.started=false
			for worker in game.players: check(worker.configure_character(identity),"Prepared "+identity+" identity applied")
			game.started=true
			for gun in guns:
				gun.reload_timer=0
				gun.ammo=10
				gun.reserve=50
		var time:=local_frame/30.0
		var pitch: float=lerpf(.25,-1.1,smoothstep(0,1.7,time))
		for index in 2:
			var gun=guns[index]
			var side: float=1 if (index+segment)%2==0 else -1
			gun.aim_angle=pitch if side>0 else -PI-pitch
			# Feed a real mouse-motion event to the fixture viewport for P1;
			# this does not move the physical desktop cursor.
			if index==0:
				var motion:=InputEventMouseMotion.new()
				motion.position=view.get_canvas_transform()*(gun.global_position+gun.PIVOT+Vector2.from_angle(gun.aim_angle)*300)
				view.push_input(motion,true)
			gun._physics_process(1.0/30.0)
			if local_frame in [54,65]:
				gun.cooldown=0
				if gun.fire(): fired+=1
			if local_frame==77 and gun.start_reload(): reloads+=1
		caption.title=identity.capitalize()+" · Dachgeschütz + Flak · Detailansicht"
		caption.detail="Zielen / Kopf und Hände folgen" if local_frame<54 else ("Feuern / Rückstoß wird abgefangen" if local_frame<77 else "Nachladen / eine Hand hält, die andere führt Munition zu")
		caption.queue_redraw()
		await process_frame
	check(fired==12,"Twelve real shots drive recoil during the prepared animation")
	check(reloads==6,"Six real reloads drive the hand cycle and weapon sounds")
