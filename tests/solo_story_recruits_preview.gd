extends SceneTree
## A native rendered review of side-only outfits, grounded moves and an NPC.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
const Rhythm := preload("res://scripts/worker_rhythm_pose.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const NPC := preload("res://scripts/solo_story_npc.gd")
const OUTPUT := "res://artifacts/solo-story/recruits/"
var view: SubViewport
var figures: Array[Node2D]=[]
var labels: Array[Label]=[]
var checks:=0
var failures:=0

class Figure extends Node2D:
	var identity: String
	var style: String
	var beats:=0.0
	var rear:=false
	func _draw() -> void:
		var pose:=Personality.stance(PoseArt.neutral(),identity) if style.is_empty() else Rhythm.choreography(style,beats,identity)
		pose.back=rear
		PoseArt.draw_identity_pose(self,pose,identity)

class ReviewWorld extends Node2D:
	var players: Array=[]
	func can_affect_world() -> bool: return true

class ReviewDirector extends Node:
	var enabled:=true
	func encounter_hint(_identity: String) -> String: return ""

func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error(label)

func label_at(text: String,point: Vector2,width:=210,size:=18) -> void:
	var label:=Label.new()
	label.text=text
	label.position=point
	label.size=Vector2(width,40)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font",UiArt.FONT)
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",Color("c4c3a7"))
	view.add_child(label)
	labels.append(label)

func figure(identity: String,point: Vector2,magnification: float,style: String="",rear:=false) -> void:
	var drawing:=Figure.new()
	drawing.identity=identity
	drawing.style=style
	drawing.rear=rear
	drawing.position=point
	drawing.scale=Vector2.ONE*magnification
	drawing.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	view.add_child(drawing)
	figures.append(drawing)

func capture(name: String) -> void:
	for tick in 2: await process_frame
	await RenderingServer.frame_post_draw
	var picture:=view.get_texture().get_image()
	check(picture.get_size()==Vector2i(1440,1000) and picture.save_png(OUTPUT+name)==OK,"Native viewport capture exists: "+name)

func run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT+"frames"))
	LocaleText.set_locale("de",false)
	view=SubViewport.new()
	view.size=Vector2i(1440,1000)
	view.world_2d=World2D.new()
	view.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	view.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	root.add_child(view)
	var background:=ColorRect.new()
	background.color=Color("152020")
	background.size=Vector2(1440,1000)
	view.add_child(background)
	label_at("BUNKERCREW · OSKAR / RIKA",Vector2(40,24),1360,27)
	label_at("Native Seitenprofile · eigene Gangarten und zehn XP-Tänze · keine Frontalansicht",Vector2(40,61),1360,16)
	for column in 5:
		var identity: String=["mara","oskar","oskar","rika","rika"][column]
		var rear: bool=column==2 or column==4
		var at:=Vector2(158+column*282,344)
		figure(identity,at,3.3,"",rear)
		label_at(identity.to_upper()+(" · RÜCKEN" if rear else " · SEITE"),at+Vector2(-110,10),220,19)
	for row in 2:
		var identity: String=["oskar","rika"][row]
		for index in 5:
			var style: String=Dance.UNIQUE_STYLES[identity][index]
			var at:=Vector2(158+index*282,624+row*265)
			figure(identity,at,2.7,style)
			label_at(Dance.label(style),at+Vector2(-120,12),240,16)
			label_at("Stufe %d"%Dance.UNLOCK_LEVELS[index],at+Vector2(-110,42),220,13)
	# The actual world NPC runs its own breathing/gesture clock in this viewport.
	var world:=ReviewWorld.new()
	view.add_child(world)
	var director:=ReviewDirector.new()
	world.add_child(director)
	var npc:=NPC.new()
	npc.game=world
	npc.director=director
	npc.character_id="oskar"
	npc.site_id="quarry"
	npc.position=Vector2(1360,982)
	npc.scale=Vector2.ONE*.75
	world.add_child(npc)
	check(not npc.is_class("PhysicsBody2D") and npc.is_in_group("interactables"),"Review includes the real animated physical-NPC script")
	await capture("outfits-and-moves.png")
	for frame in 96:
		for item: Figure in figures:
			item.beats=float(frame)/12.0
			item.queue_redraw()
		await capture("frames/%04d.png"%frame)
		if frame in [9,33,69]: await capture("beat-%02d.png"%frame)
	check(npc.elapsed>0 and not npc.pose.is_empty(),"Real NPC idle clock remains active during native review")
	await preload("res://tests/scene_cleanup.gd").free_scene(view,self)
	print("SOLO RECRUIT NATIVE PREVIEW: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
