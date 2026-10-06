extends SceneTree
## Matched prepared states at normal world-pixel size, not a playthrough.
## Uses actual WorkerVisual, native identity parts, walls, machines and SAN rig.
const Cleanup := preload("res://tests/scene_cleanup.gd")
const Dance := preload("res://scripts/worker_dance_catalog.gd")
const Defaults := preload("res://scripts/audio_defaults.gd")
const MedicRhythm := preload("res://scripts/medic_rhythm_pose.gd")
const MedicDance := preload("res://scripts/medic_dance_catalog.gd")
const IDS := ["mara","branko","ivo","nora","levin","selma","oskar","rika"]
const WORK := ["form","reinforce","pour","repair","deposit","collect"]
const WORK_LABELS := ["SCHALUNG","BEWEHRUNG","BETON GIESSEN","WAND REPARIEREN","OFEN BELADEN","STAHL ABHOLEN"]
var frames_dir := ""
var output := ""
var kind := "work"
var phase := "final"
var size := Vector2i(1440,900)
var checks := 0
var failures := 0
var captures: Array[Dictionary] = []

class MusicFixture extends Node:
	var state: Dictionary = {}
	func rhythm_frame() -> Dictionary:
		return state

class AudioFixture extends Node:
	var live_music: MusicFixture

class RoundFixture extends Node:
	var wave := 16
	var phase := "salvage"

class UpgradeFixture extends Node:
	func has_upgrade(_id: String) -> bool:
		return true
	func carry_capacity() -> int:
		return Balance.CARRY_CAPACITY

class RobotPreview extends Node2D:
	var rig = MedicRhythm.new()
	func _draw() -> void:
		rig.draw(self,MedicalCatalog.MAX_CHARGES,1.0)

class Board extends Node2D:
	var audio: AudioFixture
	var rounds: Node
	var upgrades: Node
	var actors: Array[Worker] = []
	var carried: Array[Worker] = []
	var walls: Array[DefenseWall] = []
	var stations: Array[ProductionStation] = []
	var robots: Array[RobotPreview] = []
	var driver: SceneTree
	var elapsed := 0.0
	var slot := 0
	var styles: Array[String] = []
	func _draw() -> void:
		draw_rect(Rect2(0,0,1800,1000),Color("10191c"))
		Art.text(self,Vector2(32,46),"BUNKERCREW · "+("ARBEIT UND BEWEGUNG" if driver.kind=="work" else "ACHT FIGUREN · TANZ UND LAST"),25,Art.LIGHT)
		Art.text(self,Vector2(32,77),"Vorbereitete echte Spiel-Rigs · 1 Weltpixel = 1 Detailpixel bei 1440 × 900 · "+str(driver.phase),13,Art.MUTED)
		for floor_y in [350,650] if driver.kind=="work" else [350,590,805]:
			draw_rect(Rect2(20,floor_y,1380,7),Color("626e5c"))
			draw_rect(Rect2(20,floor_y+7,1380,15),Color("29352f"))
			for bolt in range(45,1400,62):
				draw_rect(Rect2(bolt,floor_y+10,3,2),Color("737867"))
		for index in IDS.size():
			var at := 78.0+float(index)*170.0
			var data := CharacterCatalog.data(IDS[index])
			Art.text(self,Vector2(at-24,180),str(data.title),17,Color(data.accent))
			if driver.kind=="work":
				Art.text(self,Vector2(at-26,470),WORK_LABELS[slot],11,Color(data.accent))
			else:
				Art.text(self,Vector2(at-28,405),LocaleText.text(Dance.label(styles[index])),10,Color(data.accent))
		if driver.kind=="work":
			Art.text(self,Vector2(32,140),"Oben: vollständige Geh-/Renn-/Krabbel-/Sprung-/Tragebewegung",15,Art.LIGHT)
			Art.text(self,Vector2(32,436),"Unten: reale Zielzustände und Arbeitsfortschritt · keine Material- oder Zeitänderung",15,Art.LIGHT)
		else:
			Art.text(self,Vector2(32,140),"Fünf persönliche Moves pro Figur, danach drei gemeinsame · 120 BPM · echtes Kick-Ereignis",15,Art.LIGHT)
			Art.text(self,Vector2(32,476),"Hände voll: nur Kopfnicken; beide Lastgriffe bleiben genau gehalten",15,Art.LIGHT)
			Art.text(self,Vector2(32,690),"SAN-1: die vorhandenen fünf freigeschalteten Servo- und Kettenbewegungen",15,Art.LIGHT)
			for index in robots.size():
				Art.text(self,Vector2(88+index*270,752),MedicDance.LABELS[(slot+index)%5],13,Art.MUTED)
		Art.text(self,Vector2(32,876),"Native stumme Bewegungsvorschau · unveränderte Spielfiguren/Regeln · keine Profil-Speicherung",12,Art.MUTED)
	func _actor(id: String,y: float,index: int) -> Worker:
		var actor := Worker.new()
		actor.game = self
		actor.character_id = id
		actor.position = Vector2(78+index*170,y)
		add_child(actor)
		actor.set_physics_process(false)
		var visual := WorkerVisual.new()
		visual.name = "PixelVisual"
		actor.add_child(visual)
		visual.set_process(false)
		visual.set_physics_process(false)
		visual.idle_clock.wait_remaining = 1000
		return actor
	func setup() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		audio = AudioFixture.new()
		audio.live_music = MusicFixture.new()
		audio.add_child(audio.live_music)
		add_child(audio)
		rounds = RoundFixture.new()
		upgrades = UpgradeFixture.new()
		add_child(rounds)
		add_child(upgrades)
		set_meta("dance_preview",true)
		for index in IDS.size():
			actors.append(_actor(IDS[index],350,index))
			carried.append(_actor(IDS[index],650 if driver.kind=="work" else 590,index))
			if driver.kind=="work":
				var wall := DefenseWall.new()
				wall.game = self
				wall.position = Vector2(136+index*170,650)
				add_child(wall)
				wall.set_process(false)
				walls.append(wall)
				var station := ProductionStation.new()
				station.kind = "furnace"
				station.game = self
				station.position = Vector2(136+index*170,650)
				add_child(station)
				station.set_process(false)
				for child in station.get_children():
					child.set_process(false)
					child.set_physics_process(false)
				stations.append(station)
		if driver.kind=="dance":
			for index in 5:
				var robot := RobotPreview.new()
				robot.position = Vector2(125+index*270,805)
				add_child(robot)
				robots.append(robot)
	func advance(seconds: float,delta: float) -> void:
		elapsed = seconds
		if driver.kind=="work":
			slot = mini(5,int(seconds/1.5))
			var progress := fposmod(seconds,0.75)/0.75
			for index in actors.size():
				var actor := actors[index]
				var visual: WorkerVisual = actor.get_node("PixelVisual")
				actor.velocity = Vector2.ZERO
				actor._airborne = false
				actor._landing_time = 0.0
				actor.climbing = false
				actor.inventory.clear()
				visual.crouched = false
				visual.ceiling_height = 128
				var stage := int(seconds/1.5)
				if stage<3: actor.velocity.x = 80.0 if stage==0 else 190.0
				elif stage==3:
					actor.velocity.x = 95
					visual.crouched = true
					visual.ceiling_height = 43
				elif stage==4:
					actor.velocity.x = 105
					actor.inventory = {"ore":1}
				elif progress<0.82:
					actor._airborne = true
					actor.velocity.y = -240.0+progress*640.0
				else: actor._landing_time = (1.0-progress)*0.15/0.18
				actor.position.x+=actor.velocity.x*delta
				visual.position.x = 78+index*170-actor.position.x
				visual.position.y = -maxf(0.0,240*progress*0.75-320*pow(progress*0.75,2.0)) if actor._airborne else 0.0
				visual._process(delta)
				var worker := carried[index]
				var work_visual: WorkerVisual = worker.get_node("PixelVisual")
				worker._interacting = true
				worker.inventory = {"concrete":6} if slot in [2,3] else {"steel":6,"concrete":6}
				worker.selected_kind = "concrete"
				var wall := walls[index]
				wall.visible = slot<4
				wall.state = DefenseWall.State.EMPTY if slot==0 else DefenseWall.State.FORM if slot in [1,2] else DefenseWall.State.HARD
				wall.max_hp = 250
				wall.hp = 100 if slot==3 else 250
				wall.work = progress
				worker.focus = wall
				var station := stations[index]
				station.visible = slot>=4
				if slot>=4:
					station.transfer[worker.get_instance_id()] = progress*Balance.TRANSFER_TIME
					station.output_amount = 2 if slot==5 else 0
					worker.inventory = {"ore":2,"concrete":2}
					worker.focus = station
				work_visual._process(delta)
		else:
			slot = mini(7,int(seconds/4.0))
			styles.clear()
			var beats := 8.0+seconds*2.0
			var profiles := {}
			for id: String in IDS:
				var style: String = Dance.UNIQUE_STYLES[id][slot] if slot<5 else Dance.SHARED_STYLES[slot-5]
				styles.append(style)
				profiles[id] = {"style":style,"intensity":1.0}
			audio.live_music.state = {"active":true,"phase":fposmod(beats,1.0),"bar":floori(beats/4.0),"beat":floori(beats)%4,"audible_seconds":beats*.5,"last_kick_seconds":floorf(beats)*.5,"last_kick_strength":1.0,"kick_count":floori(beats)+1,"bpm":120.0,"beat_period_seconds":.5,"motion_gain":1.0,"dance_intensity":Defaults.DANCE_INTENSITY,"dance_profiles":profiles,"genre":"minimal_techno"}
			for index in actors.size():
				var actor := actors[index]
				actor.get_node("PixelVisual")._process(delta)
				var worker := carried[index]
				worker.inventory = {"concrete":worker.capacity()}
				worker.selected_kind = "concrete"
				worker.get_node("PixelVisual")._process(delta)
			for index in robots.size():
				var robot := robots[index]
				robot.rig.weight = Defaults.DANCE_INTENSITY
				robot.rig.pose = MedicRhythm.choreography(MedicDance.STYLES[(slot+index)%5],beats,fposmod(beats,1.0)*.5,.5,1.0,Defaults.DANCE_INTENSITY)
				robot.queue_redraw()
		queue_redraw()

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--frames="): frames_dir = argument.trim_prefix("--frames=")
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--kind="): kind = argument.trim_prefix("--kind=")
		elif argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		elif argument.begins_with("--width="): size.x = int(argument.trim_prefix("--width="))
		elif argument.begins_with("--height="): size.y = int(argument.trim_prefix("--height="))
	if DisplayServer.get_name()=="headless" or "--no-profile-save" not in OS.get_cmdline_user_args() or frames_dir.is_empty() or output.is_empty():
		push_error("Native work gallery needs graphical display, isolated frames/output and --no-profile-save")
		quit(2)
		return
	AudioServer.set_bus_mute(0,true)
	InputSetup.install()
	LocaleText.set_locale("de",false)
	root.mode = Window.MODE_WINDOWED
	root.size = size
	root.content_scale_size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(frames_dir)
	DirAccess.make_dir_recursive_absolute(output)
	var board := Board.new()
	board.driver = self
	root.add_child(board)
	board.setup()
	if kind=="dance":
		for frame in 120:
			board.advance(float(frame)/30.0,1.0/30.0)
	var duration := 9.0 if kind=="work" else 32.0
	for frame in int(duration*30):
		var seconds := float(frame)/30.0
		board.advance(seconds,1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var picture := root.get_texture().get_image()
		check(picture.get_size()==size,"Native frame dimensions")
		check(picture.save_jpg(frames_dir+"/%04d.jpg"%frame,0.97)==OK,"Motion frame written")
		var interval := 45 if kind=="work" else 120
		if frame%interval in [4,14,24]:
			var name := "%s-%s-%dx%d-%04d.png"%[phase,kind,size.x,size.y,frame]
			check(picture.save_png(output+"/"+name)==OK,"Original native PNG written")
			captures.append({"path":name,"frame":frame,"seconds":seconds,"slot":board.slot})
	check(await Cleanup.free_scene(board,self),"Native work and dance preview frees all original rigs")
	var report := {"checks":checks,"failures":failures,"phase":phase,"kind":kind,"size":size,"fps":30,"frames":int(duration*30),"captures":captures,"fixture":"Prepared real worker renderers and authoritative wall/machine values. Movement roots recentered only for side-by-side review; no gameplay run claimed. Heard-kick test events at120BPM use original WorkerRhythmPose; SAN uses original five draw-only choreographies. All sprites displayed at normal1x world scale. Muted, no progress saving."}
	var file := FileAccess.open(output+"/%s-%s-%dx%d.json"%[phase,kind,size.x,size.y],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("WORKER POLISH MOTION: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
