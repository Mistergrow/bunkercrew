extends SceneTree
## Prepared native cinematic paintings only. Controller/gameplay is tested by
## integration suites, never inferred from the sampling of this art gallery.
const CinematicArt := preload("res://scripts/travel_cinematic_art.gd")
const OUTPUT := "res://artifacts/travel-cinematics-20261004/art/"
var view: SubViewport
var canvas: Node2D
var context: Dictionary={}
var elapsed:=0.0
var reduced:=false
var captures: Array[Dictionary]=[]
var checks:=0
var failures:=0
var samples: Dictionary={}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _draw() -> void:
	CinematicArt.draw(canvas,context,elapsed,reduced)

func capture(id: String, story: String, at: float, resolution: Vector2i=Vector2i(1920,1080), low: bool=false, solo: bool=false, environment: String="ash_foundry") -> Image:
	view.size=resolution
	canvas.scale=Vector2(resolution)/CinematicArt.REFERENCE
	context={"id":story,"environment":environment,"duration":8.0,"character_id":"branko","crew_ids":["branko"] if solo else ["mara","branko","ivo","mara"]}
	elapsed=at
	reduced=low
	var before:=context.duplicate(true)
	canvas.queue_redraw()
	for unused in 3: await process_frame
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==resolution and picture.save_png(OUTPUT+id+".png")==OK,"Native exact-resolution capture "+id)
	check(context==before and canvas.get_child_count()==0,"Draw has no context/entity mutations "+id)
	captures.append({"id":id,"file":id+".png","story":story,"elapsed":at,"duration":8.0,"resolution":[resolution.x,resolution.y],"reduced":low,"crew_ids":context.crew_ids,"environment":environment,"prepared_state":true})
	return picture

func changed_pixels(first: Image, second: Image, bounds: Rect2i) -> int:
	var changed:=0
	for y in range(bounds.position.y,bounds.end.y):
		for x in range(bounds.position.x,bounds.end.x):
			if first.get_pixel(x,y)!=second.get_pixel(x,y): changed+=1
	return changed

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	AudioServer.set_bus_mute(0,true)
	view=SubViewport.new()
	view.size=Vector2i(1920,1080)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	canvas=Node2D.new()
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	canvas.draw.connect(_draw)
	view.add_child(canvas)
	for story in ["signal","storm","supply"]:
		await capture(story+"-establish",story,.3)
		await capture(story+"-action",story,1.024 if story=="storm" else 2.7)
		await capture(story+"-resolved",story,5.7)
		await capture(story+"-solo-720p",story,4.8,Vector2i(1280,720),false,true,"mountain_pass")
		await capture(story+"-qhd",story,4.8,Vector2i(2560,1440),false,false,"radar_highlands")
		var early:=await capture(story+"-reduced-before",story,.8,Vector2i(1440,900),true)
		var late:=await capture(story+"-reduced-after",story,5.7,Vector2i(1440,900),true)
		var bounds:=Rect2i(1010,220,155,356) if story=="signal" else Rect2i(1090,405,200,170) if story=="storm" else Rect2i(1040,442,117,139)
		var changes:=changed_pixels(early,late,bounds)
		samples[story]=changes
		check(changes>30,"Main event reaches framebuffer with fixed reduced camera: %s (%d pixels)"%[story,changes])
	check(CinematicArt._backgrounds.size()==3,"Destination texture cache remains bounded by visited environments")
	check(AudioServer.is_bus_mute(0),"Gallery keeps its own Master output muted")
	var report: Dictionary={"checks":checks,"passed":checks-failures,"failures":failures,"captures":captures,"action_pixels":samples,"renderer":RenderingServer.get_video_adapter_name(),"fixture":"Draw-only art gallery with prepared elapsed/duration and real selected side-view identities, original hull, landmarks, depot, trees and depth plates. Fresh world, no game scene, sockets, microphone or profile writes. SubViewport size exact; reference1440x900 composition maps per axis here. Event pixel comparisons use reduced effects and a fixed camera to isolate actual lighting/fire/shutter animation. Production integration and real gameplay are verified separately."}
	FileAccess.open(OUTPUT+"gallery.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	view.queue_free()
	await process_frame
	print("TRAVEL CINEMATIC ART GALLERY: %d/%d passed; %d captures"%[checks-failures,checks,captures.size()])
	quit(0 if failures==0 else 1)
