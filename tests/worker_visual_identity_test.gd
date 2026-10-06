extends SceneTree
## All-eight identity routing and actual native WorkerVisual renders in atlas,
## articulated, carrying, rear-view and medical poses. No profile mutations.
const Identity := preload("res://scripts/worker_identity_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Locomotion := preload("res://scripts/worker_locomotion.gd")
const Cleanup := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
const POSES := ["atlas_idle","atlas_mine","atlas_climb","idle","walk","carry_walk","climb","aid_bandage","guard","downed"]
const POSE_HASH := "1d38b305b6f797680096cee069eaab11463e23a394004562e318d988187a5e03"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func different(a: Image,b: Image,alpha_only: bool=false) -> int:
	var count := 0
	for y in 112:
		for x in 112:
			var left := a.get_pixel(x,y)
			var right := b.get_pixel(x,y)
			if absf(left.a-right.a)>.5 if alpha_only else left!=right: count += 1
	return count

func run() -> void:
	InputSetup.install()
	AudioServer.set_bus_mute(0,true)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_visuals.json"))
	var poses: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/workers/character_motion_frames.json"))
	check(FileAccess.get_sha256("res://assets/workers/character_motion_frames.json")==POSE_HASH,"All 880 authored joint records retain the established cargo/tool/weapon/ladder contract")
	check(catalog.identities.size()==8 and catalog.motion_profiles.size()==8,"Eight identities and motion profiles survive regeneration")
	var heads: Dictionary = {}
	var coats: Dictionary = {}
	for id: String in IDS:
		var textures: Array[Texture2D] = [Identity.body(id),Identity.arms(id),Identity.torso(id),Identity.head(id),Identity.torso(id,true),Identity.head(id,true)]
		var suffixes := ["body","arms","torso","head","back_torso","back_head"]
		for index in textures.size():
			check(textures[index].resource_path=="res://assets/workers/%s_%s.png"%[id,suffixes[index]],"%s routes own %s rather than another character"%[id,suffixes[index]])
			check(textures[index].get_size()==(Vector2(896,2128) if index<2 else Vector2(112,112)),"%s %s retains rig dimensions"%[id,suffixes[index]])
		heads[id]=Identity.head(id).get_image()
		coats[id]=Identity.torso(id).get_image()
		check(catalog.identities[id].visual_signature.size()==3,"%s has head, outfit and equipment provenance"%id)
		check(poses[id].size()==19,"%s keeps every action row"%id)
		var colors := Identity.palette(id,{"ink":Color("151b1e"),"cloth":Color.WHITE})
		check(colors.cloth==Color(catalog.identities[id].palette.cloth),"%s articulated limbs use its authored uniform palette"%id)
	for left in IDS.size():
		for right in range(left+1,IDS.size()):
			check(different(heads[IDS[left]],heads[IDS[right]],true)>=80,"Native %s/%s heads differ in shape"%[IDS[left],IDS[right]])
			check(different(coats[IDS[left]],coats[IDS[right]],true)>=100,"Native %s/%s equipment/coats differ in shape"%[IDS[left],IDS[right]])
	check(Identity.head("missing")==Identity.head("mara"),"Unknown identities preserve the existing safe artwork fallback")
	if "--capture" in OS.get_cmdline_user_args():
		check(DisplayServer.get_name()!="headless","Actual appearance tests require a renderer")
		if DisplayServer.get_name()!="headless": await render_checks()
	print("WORKER VISUAL IDENTITY: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)

func prepare(actor: Worker,visual: WorkerVisual,kind: String) -> void:
	actor.inventory={}
	actor.velocity=Vector2.ZERO
	actor.climbing=false
	visual.special_pose=""
	visual.locomotion_pose={}
	visual.mining_pose={}
	visual.pose_skeleton={}
	visual.pose_frame=0
	visual.pose_name="idle"
	if kind.begins_with("atlas_"):
		visual.pose_name=kind.trim_prefix("atlas_")
		visual.pose_frame=3 if kind=="atlas_mine" else 0
	elif kind in ["aid_bandage","guard","downed"]:
		visual.special_pose=kind
		visual.pose_skeleton=WorkerPoseArt.sample(kind,.45,0,Vector2(24,-20),actor.character_id)
	else:
		if kind=="carry_walk": actor.inventory={"ore":3}
		if kind=="climb":
			actor.climbing=true
			actor._ladder=Rect2(actor.position+Vector2(-14,-280),Vector2(28,300))
		actor.velocity=Vector2(130,0) if kind.ends_with("walk") else Vector2.ZERO
		var pose := Locomotion.new().advance(actor,kind,.6,false,visual)
		if kind=="idle": pose=Personality.stance(pose,actor.character_id)
		if pose.has("cargo"): pose.cargo_kind="ore"
		visual.locomotion_pose=pose
		visual.pose_skeleton=pose
		visual.pose_name=kind
	visual.queue_redraw()

func render_checks() -> void:
	var view := SubViewport.new()
	view.size=Vector2i(112,112)
	view.transparent_bg=true
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var actor := Worker.new()
	actor.position=Vector2(48,90)
	view.add_child(actor)
	actor.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name="PixelVisual"
	actor.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	visual._identity.hide()
	visual.get_node("GroundShadow").hide()
	for kind: String in POSES:
		var rendered: Dictionary = {}
		for id: String in IDS:
			actor.character_id=id
			prepare(actor,visual,kind)
			actor.player_id=1
			for unused in 2: await process_frame
			await RenderingServer.frame_post_draw
			var first := view.get_texture().get_image()
			rendered[id]=first
			actor.player_id=4
			visual.queue_redraw()
			await process_frame
			await RenderingServer.frame_post_draw
			check(different(first,view.get_texture().get_image())==0,"%s %s keeps appearance independent of local P1/P4 slot"%[id,kind])
		for left in IDS.size():
			for right in range(left+1,IDS.size()):
				check(different(rendered[IDS[left]],rendered[IDS[right]])>180,"Actual %s render distinguishes %s/%s"%[kind,IDS[left],IDS[right]])
	await Cleanup.free_scene(view,self)
