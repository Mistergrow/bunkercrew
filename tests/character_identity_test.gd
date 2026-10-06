extends SceneTree

const IdentityArt := preload("res://scripts/worker_identity_art.gd")
## Identity contracts and every action frame; --capture also checks rendered
## local-player independence and medical articulation with the real renderer.

var checks := 0
var failures := 0
const IDS := ["mara","branko","ivo"]
const CLEANUP := preload("res://tests/scene_cleanup.gd")

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func pixel_difference(a: Image,b: Image,region: Rect2i,alpha_only: bool=false) -> int:
	var changed := 0
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var ca := a.get_pixel(x,y)
			var cb := b.get_pixel(x,y)
			if absf(ca.a-cb.a)>0.5 if alpha_only else ca!=cb:
				changed += 1
	return changed

func _run() -> void:
	InputSetup.install()
	var metadata = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/worker_frames.json"))
	var images: Dictionary = {}
	for id in IDS:
		images[id] = IdentityArt.body(id).get_image()
		check(images[id].get_size()==Vector2i(896,2128),"%s keeps all 19 animation rows"%id)
		check(IdentityArt.arms(id).get_size()==Vector2(896,2128),"%s preserves foreground hand atlas"%id)
		check(IdentityArt.torso(id).get_size()==Vector2(112,112) and IdentityArt.head(id).get_size()==Vector2(112,112),"%s has clean medical torso and head parts"%id)
	for state in metadata.states:
		var descriptor: Dictionary = metadata.states[state]
		for frame in int(descriptor.frames):
			var region := Rect2i(frame*112,int(descriptor.row)*112,112,112)
			for pair in [["mara","branko"],["mara","ivo"],["branko","ivo"]]:
				check(pixel_difference(images[pair[0]],images[pair[1]],region)>220,"%s frame %d visibly distinguishes %s / %s"%[state,frame,pair[0],pair[1]])
	check(pixel_difference(images.branko,images.ivo,Rect2i(0,0,112,112),true)>150,"Branko and Ivo differ in silhouette, not only palette")
	if "--capture" in OS.get_cmdline_user_args():
		if DisplayServer.get_name()=="headless":
			check(false,"Capture requires a graphical display")
		else:
			await _render_checks()
	print("CHARACTER IDENTITY: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)

func _render_checks() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(112,112)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var actor := Worker.new()
	actor.position = Vector2(48,90)
	viewport.add_child(actor)
	actor.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	actor.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual._identity.hide()
	var last_image: Image
	for pose in ["idle","mine","climb","guard","downed"]:
		var rendered: Dictionary = {}
		for id in IDS:
			actor.character_id = id
			visual.pose_name = pose if pose in ["idle","mine","climb"] else "idle"
			visual.pose_frame = 3 if pose=="mine" else 0
			visual.special_pose = "" if pose in ["idle","mine","climb"] else pose
			visual.pose_skeleton = {} if visual.special_pose.is_empty() else WorkerPoseArt.sample(pose,1.0)
			for player in [1,2]:
				actor.player_id = player
				visual.queue_redraw()
				await process_frame
				await RenderingServer.frame_post_draw
				var capture := viewport.get_texture().get_image()
				if player==1:
					last_image = capture
					rendered[id] = capture
				else:
					check(pixel_difference(last_image,capture,Rect2i(0,0,112,112))==0,"%s %s preserves outfit when switching P1 to P2"%[id,pose])
		check(pixel_difference(rendered.mara,rendered.branko,Rect2i(0,0,112,112))>220,"Rendered %s distinguishes Mara and Branko"%pose)
		check(pixel_difference(rendered.branko,rendered.ivo,Rect2i(0,0,112,112))>220,"Rendered %s distinguishes Branko and Ivo"%pose)
	await CLEANUP.free_scene(viewport,self)
