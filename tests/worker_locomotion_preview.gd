extends SceneTree
## Prepared, deterministic states using the actual WorkerVisual at 60 Hz.
## Not a gameplay recording. Actors move in world space; only their visual
## presentation is recentered to compare all six identities on a treadmill.

const IDS := ["mara", "branko", "ivo", "nora", "levin", "selma"]
const STARTS := [0.0, 0.6, 2.0, 3.4, 4.8, 5.1, 6.2, 7.0, 7.2, 8.5, 8.9, 9.5]
const LABELS := ["BEREIT", "GEHEN", "RENNEN", "TIEF GEHEN", "AUFRICHTEN", "LAST TRAGEN", "SPRUNG / FALL", "LANDEN", "KLETTERN", "ANHALTEN", "RICHTUNGSWECHSEL", "BEREIT"]
const CLEANUP := preload("res://tests/scene_cleanup.gd")

class Board extends Node2D:
	var actors: Array[Worker] = []
	var elapsed := 0.0
	var stage := 0
	var revision := ""

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1440, 900), Color("111a1d"))
		Art.text(self, Vector2(28, 43), "BUNKERCREW · BEWEGUNGEN · "+revision.to_upper(), 25, Art.LIGHT)
		Art.text(self, Vector2(30, 73), "Vorbereitete Bewegungszustände · echte Spielfiguren · 60 Bilder/s · Spielgröße und 2× Detail", 13, Art.MUTED)
		for column in IDS.size():
			var x := 18+column*238
			var spec := CharacterCatalog.data(IDS[column])
			var accent := Color(spec.accent)
			draw_rect(Rect2(x, 102, 226, 712), Color("1b2628"))
			draw_rect(Rect2(x, 102, 226, 3), accent)
			Art.text(self, Vector2(x+14, 140), spec.title, 20, accent)
			Art.text(self, Vector2(x+14, 194), "SPIELGRÖSSE", 11, Art.MUTED)
			Art.text(self, Vector2(x+14, 426), "DETAIL 2×", 11, Art.MUTED)
			for floor_y in [320, 660]:
				draw_line(Vector2(x+12, floor_y), Vector2(x+214, floor_y), Color("617167"), 1)
				if stage in [1, 2, 3, 5, 10]:
					var speed := 80.0 if stage==1 else (95.0 if stage==3 else (105.0 if stage==5 else 190.0))
					var slide := fposmod(elapsed*speed, 32.0)
					for index in 6:
						var at := x+18+index*32-slide
						if at>=x+12: draw_line(Vector2(at, floor_y+4), Vector2(at+8, floor_y+4), Color("354341"), 1)
			Art.text(self, Vector2(x+14, 748), LABELS[stage], 12, accent)
			if stage==3 and elapsed-STARTS[stage]>0.7:
				Art.text(self, Vector2(x+14, 778), "KRABBELN", 12, accent)
		Art.text(self, Vector2(28, 853), "Gleiche Aktion · sechs Körperhaltungen · unveränderte Spielgeschwindigkeit", 14, Art.LIGHT)
		draw_rect(Rect2(20, 884, 1400*elapsed/10.0, 3), Art.AMBER)

	func advance(delta: float) -> void:
		for index in STARTS.size():
			if elapsed>=STARTS[index]: stage=index
		for index in actors.size():
			var actor := actors[index]
			var visual: WorkerVisual = actor.get_node("PixelVisual")
			var scale_factor := float(1+index%2)
			var floor_y := 320.0 if index%2==0 else 660.0
			var time: float = elapsed-STARTS[stage]
			actor.velocity=Vector2.ZERO
			actor._airborne=false
			actor._jump_windup=0
			actor._landing_time=0
			actor.climbing=false
			actor.inventory.clear()
			visual.crouched=false
			visual.ceiling_height=128.0
			actor.position.y=floor_y
			actor.facing=1.0
			var lift := 0.0
			match stage:
				1: actor.velocity.x=80
				2: actor.velocity.x=190
				3:
					actor.velocity.x=95
					visual.crouched=true
					visual.ceiling_height=42.0 if time>0.7 else 58.0
				5:
					actor.velocity.x=105
					actor.inventory={"ore":1}
					actor.selected_kind="ore"
				6:
					actor.velocity=Vector2(150, -390+time*975)
					actor._airborne=true
					lift=maxf(0, 390*time-487.5*time*time)
				7: actor._landing_time=maxf(0, 0.15-time)
				8:
					actor.climbing=true
					actor._ladder=Rect2(0, floor_y-250, 40, 320)
					actor.position.y=floor_y-time*155
				10:
					actor.facing=-1.0 if time>0.3 else 1.0
					actor.velocity.x=actor.facing*190
			actor.position.x+=actor.velocity.x*delta
			visual.position=Vector2((18+floori(index/2.0)*238+113-actor.position.x)/scale_factor, (floor_y-actor.position.y-lift*scale_factor)/scale_factor)
			visual.idle_clock.wait_remaining=100
			visual._process(delta)
			visual._identity.hide()
		elapsed+=delta
		queue_redraw()

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Locomotion capture requires a graphical display")
		quit(1)
		return
	InputSetup.install()
	root.size=Vector2i(1440, 900)
	var board := Board.new()
	board.revision="after" if "--after" in OS.get_cmdline_user_args() else "before"
	root.add_child(board)
	for id in IDS:
		for size_index in 2:
			var actor := Worker.new()
			actor.character_id=id
			actor.scale=Vector2.ONE*(1+size_index)
			board.add_child(actor)
			actor.set_physics_process(false)
			var visual := WorkerVisual.new()
			visual.name="PixelVisual"
			actor.add_child(visual)
			visual.set_process(false)
			visual.set_physics_process(false)
			board.actors.append(actor)
	var directory := "res://artifacts/worker-locomotion/"+board.revision+"-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 600:
		board.advance(1.0/60.0)
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		capture.save_png(directory+"/%04d.png"%frame)
		if frame in [80, 155, 235, 340, 392, 430, 485]:
			capture.save_png("res://artifacts/worker-locomotion/%s-%04d.png"%[board.revision, frame])
	print("LOCOMOTION PREVIEW: "+board.revision+", 600 frames, 60 fps, 10 seconds; prepared states with actual WorkerVisual")
	await CLEANUP.free_scene(board, self)
	quit()
