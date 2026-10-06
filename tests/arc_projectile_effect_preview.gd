extends SceneTree
## Prepared real projectile drawing at a fixed position to inspect its shape.
class WeatherStub extends Node:
	var reduced_effects := false
class GameStub extends Node2D:
	var weather := WeatherStub.new()
	func _ready() -> void:
		add_child(weather)
class Backdrop extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,720),Color("182320"))
		Art.text(self,Vector2(40,52),"IMPULSPROJEKTIL / STROMBOEGEN",24,Color("dfe1cc"))
		Art.text(self,Vector2(40,82),"Echter Projektilcode · vorbereitete, feste Position · 12 Hz · gleiche Ausrichtung und Trefferregeln",14,Color("9da99c"))
		for row in 2:
			var top := 140+row*270
			Art.text(self,Vector2(40,top+26),"VOLLE EFFEKTE" if row == 0 else "F3 / REDUZIERTE EFFEKTE",18,Color("d8bd84"))
			Art.text(self,Vector2(70,top+230),"Native Groesse",14,Color("9da99c"))
			Art.text(self,Vector2(345,top+230),"4x / nach rechts",14,Color("9da99c"))
			Art.text(self,Vector2(750,top+230),"4x / diagonal",14,Color("9da99c"))
			Art.text(self,Vector2(1120,top+230),"4x / nach links",14,Color("9da99c"))
			for column in 4:
				draw_line(Vector2(40+column*355,top+175),Vector2(335+column*355,top+175),Color("48544a"),1)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.content_scale_size = Vector2i(1440,720)
	root.size = Vector2i(1440,720)
	var directory := "res://artifacts/graphics-audit/arc-projectile"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory+"/frames"))
	var backdrop := Backdrop.new()
	root.add_child(backdrop)
	var shots: Array[WorkerShot] = []
	for row in 2:
		var game := GameStub.new()
		game.weather.reduced_effects = row == 1
		backdrop.add_child(game)
		for column in 4:
			var shot := WorkerShot.new()
			shot.game = game
			shot.flavor = "arcgun"
			shot.distance_travelled = 31.0
			shot.position = Vector2(190+column*355,270+row*270)
			shot.scale = Vector2.ONE*(1.0 if column == 0 else 4.0)
			shot.direction = Vector2.RIGHT if column < 2 else (Vector2(1,-1).normalized() if column == 2 else Vector2.LEFT)
			game.add_child(shot)
			shot.set_physics_process(false)
			shots.append(shot)
	for frame in 60:
		for shot in shots:
			shot.age = float(frame)/30.0
			shot.queue_redraw()
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("%s/frames/%03d.png" % [directory,frame])
		if frame == 6: image.save_png(directory+"/arcs.png")
	print("ARC PREVIEW: 60 rendered frames at 30 fps")
	backdrop.queue_free()
	await process_frame
	quit()
