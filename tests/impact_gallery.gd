extends SceneTree
## A reproducible, rendered effects fixture. It is intentionally separate from a
## playable arena; physics floors, existing props and the real burst code are used.
const OUTPUT := "/tmp/lastshift-impact-frames"
class Gallery extends Node2D:
	var started := false
	var upgrades
	var rounds
	var cells: Array = []
	var elapsed := 0.0
	var pulse := -1
	var ladders: Array[Rect2] = []
	func get_focus(_worker): return null
	func sound(_kind): pass
	func notify(_message): pass
	func fx(point,color,count):
		var effect=load("res://scripts/effect.gd").new()
		effect.position=point
		effect.color=color
		effect.count=count
		add_child(effect)
	func impact(point,kind,normal=Vector2.LEFT,strength=1.0):
		var burst=ImpactBurst.new()
		burst.surface_material=kind
		burst.position=point
		burst.direction=normal
		burst.power=strength
		burst.seed_value=818+int(point.x)
		add_child(burst)
		return burst
	func _process(delta):
		elapsed+=delta
		var now=int(elapsed/1.25)
		if now!=pulse:
			pulse=now
			for cell in cells:
				var burst=ImpactBurst.new()
				burst.position=cell.point
				burst.surface_material=cell.kind
				burst.direction=Vector2.LEFT
				burst.power=1.4 if cell.kind!="flesh" else 1.0
				burst.reduced=cell.reduced
				burst.seed_value=1413+cells.find(cell)*39+now
				add_child(burst)
	func _draw():
		draw_rect(Rect2(0,0,1440,900),Color("121f26"))
		Art.text(self,Vector2(35,44),"LETZTE SCHICHT / EINSCHLAG UND MATERIAL",24,Art.LIGHT)
		Art.text(self,Vector2(35,72),"Laufende Godot-Effektvorschau · gerichtete Funken, Splitter und Staub · reale Bodenkollision",13,Art.MUTED)
		for index in cells.size():
			var cell=cells[index]
			var at: Vector2=cell.origin
			draw_rect(Rect2(at,Vector2(329,324)),Color("233135"))
			for panel in 5:
				draw_rect(Rect2(at+Vector2(4+panel*65,47),Vector2(61,260)),Color("2d3938") if panel%2 else Color("303c39"))
			draw_rect(Rect2(at+Vector2(0,0),Vector2(329,44)),Color("19292e"))
			Art.text(self,at+Vector2(13,26),cell.title,16,cell.tint)
			draw_rect(Rect2(at+Vector2(0,286),Vector2(329,15)),Color("647064"))
			draw_line(at+Vector2(0,286),at+Vector2(329,286),Color("a3a487"),2)
			Art.text(self,at+Vector2(13,319),cell.note,10,Art.MUTED)
		Art.text(self,Vector2(35,861),"Max.36 aktive Bursts · max.48 Teilchen je Burst · höchstens ein Abpraller · automatische Freigabe nach1,65s",13,Art.MUTED)

func _initialize(): call_deferred("run")
func floor_body(parent,rect):
	var body=StaticBody2D.new()
	body.collision_layer=1
	body.position=rect.get_center()
	var shape=CollisionShape2D.new()
	var rectangle=RectangleShape2D.new()
	rectangle.size=rect.size
	shape.shape=rectangle
	body.add_child(shape)
	parent.add_child(body)
func run():
	Engine.max_fps=30
	ThemeDB.fallback_font=load("res://assets/mono.ttf")
	InputSetup.install()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var gallery=Gallery.new()
	root.add_child(gallery)
	gallery.upgrades=UpgradeSystem.new()
	gallery.add_child(gallery.upgrades)
	var kinds=["metal","concrete","earth","glass","flesh","explosion","arc","metal"]
	var titles=["METALL","BETON","ERDREICH","GLAS","VERLETZUNG","ZERSTÖRUNG","IMPULS","REDUZIERTE EFFEKTE"]
	var notes=["Funken + Metallspäne","Brocken + Betonstaub","Staub + Gestein","Helle, drehende Splitter","Kurze dezente Trefferreaktion","Lokaler Blitz + Trümmer","Elektrische Verästelung","F3 · weniger Teilchen, kein Blitz"]
	for index in 8:
		var at=Vector2(35+(index%4)*348,115+floori(index/4.0)*348)
		var footing=at+Vector2(239,286)
		var point=footing+Vector2(-33,-53)
		var kind=kinds[index]
		floor_body(gallery,Rect2(at+Vector2(0,286),Vector2(329,15)))
		if kind in ["metal","arc","explosion"]:
			var enemy=load("res://scenes/enemy.tscn").instantiate()
			enemy.game=gallery
			enemy.kind="breaker" if kind=="explosion" else "strider"
			enemy.position=footing
			gallery.add_child(enemy)
			enemy.set_physics_process(false)
			point=footing+Vector2(-36,-enemy.body_height)
		elif kind=="concrete":
			var wall=load("res://scenes/wall.tscn").instantiate()
			wall.game=gallery
			wall.position=footing
			wall.initial_state=DefenseWall.State.HARD
			gallery.add_child(wall)
			point=footing+Vector2(-16,-53)
		elif kind=="earth":
			for row in 2:
				for col in 2:
					var rock=load("res://scenes/mine_block.tscn").instantiate()
					rock.game=gallery
					rock.position=footing+Vector2(-24+col*48,-72+row*48)
					gallery.add_child(rock)
			point=footing+Vector2(-49,-55)
		elif kind=="glass":
			var pane=DomeSegment.new()
			pane.game=gallery
			pane.configure(footing-Vector2(0,110),footing,0)
			gallery.add_child(pane)
			pane.set_frame()
			pane.glaze()
			point=footing+Vector2(-10,-55)
		elif kind=="flesh":
			var worker=load("res://scenes/player.tscn").instantiate()
			worker.game=gallery
			worker.position=footing
			worker.facing=-1
			gallery.add_child(worker)
			worker.set_physics_process(false)
			point=footing+Vector2(-9,-34)
		gallery.cells.append({"origin":at,"point":point,"kind":kind,"title":titles[index],"note":notes[index],"tint":ImpactBurst.PRESETS[kind].body,"reduced":index==7})
	gallery.queue_redraw()
	await physics_frame
	await physics_frame
	for frame in 90:
		await process_frame
		await RenderingServer.frame_post_draw
		var picture=root.get_texture().get_image()
		picture.save_png(OUTPUT+"/frame_%03d.png" % frame)
		if frame==3: picture.save_png("res://artifacts/impact-material-gallery.png")
	print("IMPACT GALLERY:90 real rendered frames saved")
	gallery.queue_free()
	await process_frame
	quit()
