extends SceneTree
## Thirty rendered frames of actual cells, worker movement and excavation.
## This isolated gallery uses a small focus adapter; full-project E selection is
## covered separately by the integration fixtures.

class DigGallery extends Node2D:
	var started := true
	var world_right := 410.0
	var ladders: Array[Rect2] = []
	var floor_levels: Array = [288.0]
	var upgrades
	var field
	var player
	var frame_number := 0
	func _draw() -> void:
		draw_rect(Rect2(-200,-200,1100,1000),Color("111c20"))
		draw_rect(Rect2(90,118,334,171),Color("202521"))
		for index in 180:
			var at := Vector2(95+(index*29)%325,125+(index*41)%157)
			draw_rect(Rect2(at,Vector2(3+index%7,2)),Color("30312a") if index%2 else Color("39342a"))
		for x in [107,406]:
			draw_rect(Rect2(x,120,8,168),Color("564630"))
			draw_line(Vector2(x,121),Vector2(x,284),Color("91724b"),1)
			draw_line(Vector2(x+4,157),Vector2(x+36 if x<200 else x-28,125),Color("564630"),6)
		draw_rect(Rect2(103,119,313,7),Color("685337"))
		draw_line(Vector2(103,120),Vector2(416,120),Color("a68958"),1)
		# The cap is permanent terrain; it joins the same world-aligned texture.
		var texture = preload("res://assets/rock.png")
		var scale_ratio: Vector2 = texture.get_size()/480.0
		draw_texture_rect_region(texture,Rect2(192,124,192,20),Rect2(Vector2(192,124)*scale_ratio,Vector2(192,20)*scale_ratio),Color(0.84,0.83,0.76))
		draw_rect(Rect2(90,288,334,13),Color("575d4e"))
		draw_line(Vector2(90,288),Vector2(424,288),Color("a3a187"),2)
		for x in range(95,422,13):
			draw_rect(Rect2(x,294,6,2),Color("353e35"))
		for x in [135,370]:
			draw_line(Vector2(x,123),Vector2(x,142),Color("a78e57"),2)
			draw_rect(Rect2(x-3,142,7,8),Color("d4a655"))
			draw_rect(Rect2(x-2,143,5,4),Color("fff0b7"))
	func valid_focus(worker,target) -> bool:
		return is_instance_valid(target) and not target.is_queued_for_deletion() and target.has_method("can_interact") and target.can_interact(worker)
	func focus_candidates(worker) -> Array:
		var result: Array = []
		for block in get_tree().get_nodes_in_group("mine_blocks"):
			if valid_focus(worker,block): result.append(block)
		result.sort_custom(func(a,b):
			var p: Vector2 = worker.global_position-Vector2(0,22)
			return a.surface_near(p).distance_to(p)+absf(a.global_position.y-p.y)*0.8 < b.surface_near(p).distance_to(p)+absf(b.global_position.y-p.y)*0.8)
		return result
	func get_focus(worker):
		var candidates := focus_candidates(worker)
		return null if candidates.is_empty() else candidates[0]
	func fx(at: Vector2,color: Color,count: int) -> void:
		var effect = load("res://scripts/effect.gd").new()
		effect.position = at
		effect.color = color
		effect.count = count
		effect.z_index = 20
		add_child(effect)
	func sound(_kind: String) -> void: pass
	func notify(_message: String) -> void: pass
	func spawn_pickup(kind: String,amount: int,at: Vector2) -> void:
		var drop = load("res://scenes/resource_pickup.tscn").instantiate()
		drop.kind = kind
		drop.amount = amount
		drop.position = at
		drop.game = self
		add_child.call_deferred(drop)

class DigHeader extends Control:
	var gallery
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,132),Color("101b20"))
		Art.text(self,Vector2(32,50),"LETZTE SCHICHT / DURCHS ERDREICH",29,Art.LIGHT)
		Art.text(self,Vector2(34,84),"Feste Erdwand → aufbrechen → in den freigegrabenen Stollen laufen",18,Art.AMBER)
		Art.text(self,Vector2(35,113),"E: graben · D: vorarbeiten · %02d / 30 Renderframes · Restliche Erdzellen: %d" % [gallery.frame_number,gallery.field.remaining_count()],15,Art.MUTED)
		draw_rect(Rect2(0,838,1440,62),Color("101b20"))
		Art.text(self,Vector2(32,864),"Durchgehende Gesteinstextur · eingebettete Erzadern · reale entfernbare Kollision",15,Art.LIGHT)
		Art.text(self,Vector2(32,887),"Gerenderte Inspektionsszene mit echten Spielobjekten / begrenztes4×3-Ausgrabungsfeld",12,Art.MUTED)

func _initialize() -> void:
	call_deferred("run")

func solid(parent: Node,rect: Rect2) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	body.add_child(shape)
	parent.add_child(body)

func run() -> void:
	InputSetup.install()
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	Engine.max_fps = 30
	Engine.time_scale = 1.0
	var gallery := DigGallery.new()
	root.add_child(gallery)
	solid(gallery,Rect2(90,288,450,14))
	solid(gallery,Rect2(405,144,10,144))
	solid(gallery,Rect2(192,124,192,20))
	gallery.field = load("res://scripts/diggable_terrain.gd").new()
	gallery.field.setup(gallery,Rect2(192,144,192,144),{Vector2i(0,0):"ore",Vector2i(1,0):"ore",Vector2i(2,0):"ore",Vector2i(3,0):"ore",Vector2i(2,1):"limestone",Vector2i(3,1):"limestone"})
	gallery.add_child(gallery.field)
	gallery.player = load("res://scenes/player.tscn").instantiate()
	gallery.player.game = gallery
	gallery.player.position = Vector2(165,288)
	gallery.add_child(gallery.player)
	var camera := Camera2D.new()
	camera.position = Vector2(263,171)
	camera.zoom = Vector2.ONE*2.8
	gallery.add_child(camera)
	var ui := CanvasLayer.new()
	root.add_child(ui)
	var header := DigHeader.new()
	header.gallery = gallery
	ui.add_child(header)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/digging-frames"))
	for frame in 3: await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/digging-before.png"))
	Input.action_press("p1_right")
	Input.action_press("p1_interact")
	for frame in range(1,31):
		await process_frame
		gallery.frame_number = frame
		header.queue_redraw()
		await RenderingServer.frame_post_draw
		var result := root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/digging-frames/frame-%02d.png" % frame))
		if result != OK:
			push_error("Could not save digging frame")
			quit(1)
			return
	Input.action_release("p1_right")
	Input.action_release("p1_interact")
	print("DIGGING GALLERY:30 real render frames; cells remaining=",gallery.field.remaining_count()," worker x=",gallery.player.global_position.x)
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://artifacts/digging-after.png"))
	quit(0)
