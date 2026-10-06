extends SceneTree
## Rendered visual fixture: real worker sprites, prepared armor tiers and poses.
class Gallery extends Node2D:
	var started := false
	var upgrades
	func _draw():
		BunkerArchitecture.rear_wall(self,Rect2(0,0,1440,900))
		draw_rect(Rect2(0,0,1440,94),Color("111c24"))
		Art.text(self,Vector2(35,44),"LETZTE SCHICHT / FIGUREN & RÜSTUNG",28,Art.AMBER)
		Art.text(self,Vector2(35,72),"ANIMATIONSPRÜFUNG · VORBEREITETE RÜSTUNGSSTUFEN · ORIGINALFIGUREN",14,Color("a2aba0"))
		for row in 3:
			BunkerArchitecture.concrete(self,Rect2(35,340+row*255,1365,17))
			for col in 3:
				var at := Vector2(90+col*460,119+row*255)
				var title: String = CharacterCatalog.CHARACTERS[col].title
				Art.text(self,at,title+" / "+["ARBEITSKLEIDUNG","STAHLWESTE · 20 %","VERBUNDPANZER · 35 %"][row],18,Art.AMBER)
				Art.text(self,at+Vector2(0,24),CharacterCatalog.CHARACTERS[col].detail,13,Color("b3b4a2"))
	func sound(_kind): pass
	func fx(_pos,_color,_count): pass
	func notify(_text): pass
var workers: Array = []
func _initialize(): call_deferred("run")
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Equipment gallery needs a real display")
		quit(1)
		return
	InputSetup.install()
	var gallery := Gallery.new()
	root.add_child(gallery)
	for row in 3:
		for col in 3:
			var worker = load("res://scenes/player.tscn").instantiate()
			worker.game = gallery
			worker.character_id = CharacterCatalog.CHARACTERS[col].id
			worker.player_id = 1 if col<2 else 2
			worker.position = Vector2(235+col*460,340+row*255)
			worker.scale = Vector2(2.2,2.2)
			gallery.add_child(worker)
			worker.set_physics_process(false)
			worker.get_node("WorkerWeapon").set_physics_process(false)
			worker.get_node("PixelVisual").set_physics_process(false)
			worker.progression.set_physics_process(false)
			for tier in row: worker.progression.equip_armor(tier+1)
			workers.append(worker)
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/player-equipment-gallery.png")
	for worker in workers: worker.mining = true
	await create_timer(0.32).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/player-equipment-mining.png")
	for worker in workers:
		worker.mining = false
		worker.climbing = true
		worker._ladder = Rect2(0,0,30,1000)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://artifacts/player-equipment-climbing.png")
	gallery.free()
	print("EQUIPMENT GALLERY: idle / mining / ladder renders saved")
	quit()
