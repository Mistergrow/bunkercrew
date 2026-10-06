extends SceneTree
## Arranged isolated pose inspection. The separate visual-state test and root's
## main-scene health gallery cover actual treatment input and gameplay outcomes.

class Gallery extends Node2D:
	var actors: Array = []
	var elapsed := 0.0
	var labels := ["HELM RICHTEN","STEIN IM STIEFEL","UHR / NACHDENKEN","GÄHNEN / STRECKEN","BLUTUNG / SCHONHALTUNG","BEINBRUCH / HINKEN","VERBAND ANLEGEN","BEIN SCHIENEN","BEWUSSTLOS","AUFHELFEN","WIEDERBELEBUNG","SELBST AUFSTEHEN"]
	var descriptions := ["Hand erreicht die Helmkante","Ein Fuß bleibt fest am Boden","Blick zur Uhr, Hand ans Kinn","Getrennte Arm- und Kopfbewegung","Kleine, begrenzte Blutstropfen","Verkürzte Belastung eines Beins","Helfer kniet am Patienten","Schiene als sichtbares Werkzeug","Einknicken → Bodenlage","Zwei Hände, Körpergewicht nach vorn","Rhythmische Kompression","Ellbogen → Knie → eigener Stand"]
	func _process(delta: float):
		elapsed += delta
		for index in actors.size():
			var pair: Array = actors[index]
			var worker: Worker = pair[0]
			var visual: WorkerVisual = worker.get_node("PixelVisual")
			if index<4:
				var gesture: String = WorkerIdleClock.GESTURES[index]
				visual.idle_clock.begin(gesture)
				visual.idle_clock.elapsed = fmod(elapsed+index*0.24,WorkerIdleClock.DURATIONS[gesture])
			elif index==5:
				worker.velocity.x = 65
			elif index in [6,7,9,10]:
				worker.medical.aid_progress = fmod(elapsed/(5.0 if index==9 else (8.0 if index==10 else 2.4)),1.0)
			elif index==8:
				worker.medical.down_elapsed = fmod(elapsed,4.0)
			elif index==11:
				worker.medical.recovery_kind = "revive"
				worker.medical.recovery_time = MedicalCatalog.RECOVERY_TIME*(1.0-fmod(elapsed/3.2,1.0))
			visual._process(delta)
			if pair.size()>1:
				var patient: Worker = pair[1]
				patient.get_node("PixelVisual")._process(delta)
		queue_redraw()
	func _draw():
		draw_rect(Rect2(0,0,1440,900),Color("111b20"))
		Art.text(self,Vector2(25,39),"LETZTE SCHICHT / PAUSEN & ERSTE HILFE",26,Art.LIGHT)
		Art.text(self,Vector2(27,65),"Originale Helm-, Gesichts- und Jackenpixel · neue Gelenkposen · dieselbe Arbeitskleidung und Palette",13,Art.MUTED)
		for index in 12:
			var x := 18+(index%4)*356
			var y := 91+floori(float(index)/4)*241
			draw_rect(Rect2(x,y,336,231),Color("4a5448"))
			draw_rect(Rect2(x+2,y+2,332,227),Color("202a28"))
			draw_rect(Rect2(x+3,y+3,330,43),Color("16221f"))
			Art.text(self,Vector2(x+12,y+24),labels[index],15,Art.LIGHT)
			Art.text(self,Vector2(x+12,y+41),descriptions[index],10,Art.MUTED)
			draw_rect(Rect2(x+9,y+205,318,5),Color("78816a"))
			draw_rect(Rect2(x+9,y+210,318,2),Color("101a1b"))
			for tick in 11:
				draw_rect(Rect2(x+14+tick*28,y+213,13,2),Color("3c4840"))
			Art.text(self,Vector2(x+12,y+225),"POSE %02d / NATIVE PIXEL" % (index+1),9,Color("91a38b"))
		Art.text(self,Vector2(25,846),"INSPEKTIONSGALERIE: arrangierte Zustände und wiederholte Posen; echter Godot-Renderer, kein Kampfdurchlauf.",12,Art.MUTED)
		Art.text(self,Vector2(25,871),"Im Spiel: Gesten erst nach 6–12 s Ruhe. Bewegung, Waffen, Arbeit, Hilfe und nahe Gegner brechen sie sofort ab.",12,Art.LIGHT)

func _initialize(): call_deferred("run")
func make_worker(parent: Node2D,position: Vector2,id: int) -> Worker:
	var worker := Worker.new()
	worker.position = position
	worker.player_id = id
	worker.character_id = "mara" if id==1 else "ivo"
	parent.add_child(worker)
	worker.set_physics_process(false)
	var visual := WorkerVisual.new()
	visual.name = "PixelVisual"
	worker.add_child(visual)
	visual.set_process(false)
	visual.set_physics_process(false)
	return worker
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Worker gallery needs a rendering display")
		quit(1)
		return
	InputSetup.install()
	ThemeDB.fallback_font = preload("res://assets/mono.ttf")
	root.size = Vector2i(1440,900)
	var gallery := Gallery.new()
	root.add_child(gallery)
	for index in 12:
		var mount := Node2D.new()
		mount.position = Vector2(186+(index%4)*356,294+floori(float(index)/4)*241)
		mount.scale = Vector2.ONE*1.8
		gallery.add_child(mount)
		var worker := make_worker(mount,Vector2.ZERO,1 if index%2==0 else 2)
		var pair: Array = [worker]
		if index==4:
			worker.hp=40
			worker.medical.bleeding=2
		elif index==5:
			worker.medical.fractured=true
			worker.hp=50
		elif index in [6,7,9,10]:
			worker.position.x=-23
			var patient := make_worker(mount,Vector2(19,0),2 if worker.player_id==1 else 1)
			patient.hp=45
			patient.medical.bleeding=1
			worker.medical.aid_target=patient
			worker.medical.aid_kind={6:"bandage",7:"splint",9:"revive",10:"resuscitate"}[index]
			patient.medical.fractured=index==7
			if index in [9,10]:
				patient.hp=0
				patient.medical.state="downed" if index==9 else "critical"
				patient.medical.down_elapsed=2
				patient.medical.critical_remaining=30 if index==9 else 0
			pair.append(patient)
		elif index==8:
			worker.hp=0
			worker.medical.state="downed"
			worker.medical.down_elapsed=2
		elif index==11:
			worker.hp=35
			worker.medical.recovery_kind="revive"
			worker.medical.recovery_time=1.1
			worker.medical.bandaged=true
		worker.progression.armor_tier=1 if index in [2,5,8,10] else 0
		gallery.actors.append(pair)
	var directory := "res://artifacts/worker-medical-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 180:
		await physics_frame
		await physics_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.save_png(directory+"/%03d.png"%frame)
		if frame==58: screenshot.save_png("res://artifacts/worker-medical-gallery.png")
	print("WORKER MEDICAL GALLERY: 12 runtime pose cards,180 rendered frames; arranged visual fixture")
	gallery.queue_free()
	await process_frame
	await process_frame
	quit()
