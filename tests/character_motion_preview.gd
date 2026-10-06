extends SceneTree
## Prepared presentation fixture, not a playthrough. Actual WorkerVisual chooses
## and advances each pose from identical worker states at deterministic 30 Hz.
## --gestures captures the two exclusive idle gestures; default covers movement.

const Personality := preload("res://scripts/worker_personality.gd")
const CLEANUP := preload("res://tests/scene_cleanup.gd")
const IDS := ["mara","branko","ivo"]
const MOTION_LABELS := ["BEREIT","GEHEN","SPRUNG","FALLEN","LANDUNG","LAST HALTEN","LAST TRAGEN","ABBAU","ARBEITEN"]
const GESTURE_LABELS := {
	"radio_check":"FUNKGERÄT PRÜFEN","strap_check":"SCHULTERGURT RICHTEN",
	"shoulder_roll":"SCHULTERN LOCKERN","beard_check":"BART RICHTEN",
	"goggles_check":"BRILLE RICHTEN","tool_check":"WERKZEUG PRÜFEN",
}
const MOTION_STARTS := [0.0,1.0,4.0,4.45,4.9,5.05,5.6,8.0,11.0]

class Gallery extends Node2D:
	var actors: Array[Worker] = []
	var elapsed := 0.0
	var gestures := false
	var stage := -1
	var stage_title := ""
	var current_labels: Array[String] = ["","",""]
	var duration := 12.0

	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("111a1d"))
		Art.text(self,Vector2(30,45),"JEDE FIGUR HAT IHRE EIGENE BEWEGUNG",25,Art.LIGHT)
		Art.text(self,Vector2(32,73),"Vorbereitete Szene mit echten Spielfiguren · normale Spielgröße und 2× Detailansicht · normales Animationstempo",12,Art.MUTED)
		for column in 3:
			var x := 28+column*464
			var entry: Dictionary = CharacterCatalog.data(IDS[column])
			var accent := Color(entry.accent)
			draw_rect(Rect2(x,102,448,692),Color("1b2628"))
			draw_rect(Rect2(x,102,448,4),accent)
			Art.text(self,Vector2(x+22,143),entry.title,25,accent)
			Art.text(self,Vector2(x+22,169),["Ruhig und zielgerichtet","Schwer und standfest","Leicht und flink"][column],13,Art.MUTED)
			Art.text(self,Vector2(x+22,220),"SPIELGRÖSSE",11,Art.MUTED)
			draw_line(Vector2(x+22,328),Vector2(x+426,328),Color("617167"),1)
			Art.text(self,Vector2(x+22,394),"DETAILANSICHT  2×",11,Art.MUTED)
			draw_line(Vector2(x+22,612),Vector2(x+426,612),Color("617167"),2)
			Art.text(self,Vector2(x+22,675),current_labels[column],16,accent)
			var lines: Array = [
				["Kontrollierter Schritt, ruhiger Oberkörper.","Prüft Funkgerät und Schultergurt."],
				["Breite Schritte, deutliches Abfedern.","Lockert Schultern und richtet den Bart."],
				["Kurze schnelle Schritte, hohe Knie.","Richtet die Brille und prüft sein Werkzeug."],
			][column]
			Art.text(self,Vector2(x+22,722),lines[0],12,Art.MUTED)
			Art.text(self,Vector2(x+22,749),lines[1],12,Art.MUTED)
		Art.text(self,Vector2(31,839),"EIGENE RUHEGESTEN" if gestures else "GLEICHE AKTION · DREI BEWEGUNGSSTILE",16,Art.LIGHT)
		Art.text(self,Vector2(32,865),"Animationen verwenden dieselben Kleidungsteile, Hände und Füße wie im Spiel.",12,Art.MUTED)
		draw_rect(Rect2(28,887,1380*clampf(elapsed/duration,0,1),3),Art.AMBER)

	func advance(delta: float) -> void:
		var next_stage := 0
		if gestures:
			next_stage = 0 if elapsed<4.5 else 1
		else:
			for index in MOTION_STARTS.size():
				if elapsed>=MOTION_STARTS[index]: next_stage=index
		var changed := next_stage!=stage
		stage = next_stage
		for index in actors.size():
			var actor: Worker = actors[index]
			var column := floori(index/2.0)
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			var ground_y := 324.0 if index%2==0 else 608.0
			actor.position.y = ground_y
			actor.velocity = Vector2.ZERO
			actor._airborne = false
			actor._landing_time = 0
			actor._jump_windup = 0
			actor.mining = false
			actor._interacting = false
			actor.focus = null
			actor.inventory.clear()
			actor.pickup_animation = 0
			actor.drop_animation = 0
			if gestures:
				var kind: String = Personality.gestures(IDS[column])[stage]
				current_labels[column] = GESTURE_LABELS[kind]
				if changed:
					visual.idle_clock.begin(kind)
			else:
				current_labels[column] = MOTION_LABELS[stage]
				visual.idle_clock.wait_remaining = 100
				match stage:
					1:
						actor.velocity.x = 160
					2:
						actor._airborne = true
						actor.velocity.y = -150
						actor.position.y -= sin((elapsed-4.0)/0.45*PI*0.5)*32*actor.scale.y
					3:
						actor._airborne = true
						actor.velocity.y = 150
						actor.position.y -= cos((elapsed-4.45)/0.45*PI*0.5)*32*actor.scale.y
					4:
						actor._landing_time = maxf(0.011,0.15-(elapsed-4.9))
					5,6:
						actor.inventory = {"ore":1}
						actor.selected_kind = "ore"
						actor.velocity.x = 160 if stage==6 else 0
					7:
						actor.mining = true
					8:
						actor._interacting = true
						actor.focus = get_node("WorkFocus")
			visual._process(delta)
			visual._identity.hide()
		elapsed += delta
		queue_redraw()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Character motion capture requires a graphical display")
		quit(1)
		return
	InputSetup.install()
	root.size = Vector2i(1440,900)
	var gallery := Gallery.new()
	gallery.gestures = "--gestures" in OS.get_cmdline_user_args()
	gallery.duration = 9.0 if gallery.gestures else 12.0
	root.add_child(gallery)
	var work_focus := Node2D.new()
	work_focus.name = "WorkFocus"
	gallery.add_child(work_focus)
	for column in 3:
		for size_index in 2:
			var actor := Worker.new()
			actor.character_id = IDS[column]
			actor.player_id = 1 if column!=1 else 2
			actor.position = Vector2(28+column*464+224,324 if size_index==0 else 608)
			actor.scale = Vector2.ONE*(1+size_index)
			gallery.add_child(actor)
			actor.set_physics_process(false)
			var visual := WorkerVisual.new()
			visual.name = "PixelVisual"
			actor.add_child(visual)
			visual.set_process(false)
			visual.set_physics_process(false)
			visual._identity.hide()
			gallery.actors.append(actor)
	var kind := "gestures" if gallery.gestures else "movement"
	var directory := "res://artifacts/character-motion/"+kind+"-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var frame_count := roundi(gallery.duration*30)
	for frame in frame_count:
		gallery.advance(1.0/30.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png(directory+"/%03d.png"%frame)
		if frame in ([36,75,171,202] if gallery.gestures else [64,132,219,258,344]):
			capture.save_png("res://artifacts/character-motion/%s-%03d.png"%[kind,frame])
	print("CHARACTER MOTION: %s, %d frames at 30 fps, %.1f seconds; prepared states with actual WorkerVisual"%[kind,frame_count,gallery.duration])
	await CLEANUP.free_scene(gallery,self)
	quit()
