extends SceneTree
## Arranged, animated inspection of real aircraft visual components. The
## companion air_combat_test.gd exercises full AI and physical attacks.

class Gallery extends Node2D:
	var machines: Array = []
	var elapsed := 0.0
	var skyline: Texture2D = preload("res://assets/skyline.png")
	var roles := ["Zielsuche · kleiner Rotorantrieb","Drei echte Geschosse je Salve","Abwurf mit Schwerkraft","Sturzflug mit zwei Schüssen","Schildpausen · offenes Schussfenster","Lange Ladephase · schwere Rakete","Zwei Raketen · feste Ziele","Vier Schüsse im Vorbeiflug","Schweben vor der Salve","Sturzflug · zwei schwere Bomben","Geladene Impulse · zwei Schüsse","Zwei schwere Geschütze im Wechsel"]
	func _process(delta: float):
		elapsed += delta
		for index in machines.size():
			var air = machines[index]
			air.age += delta
			var phase := elapsed+index*0.53
			air.flight_velocity = Vector2(sin(phase)*75,cos(phase)*13)
			air.position.y = 300+floori(float(index)/4)*300+sin(phase*2)*(12 if index==3 else 4)
			var cycle := fmod(phase,5.0)
			air.windup = clampf(cycle-1,0,float(air.profile.windup)) if cycle<3.3 else 0.0
			air.muzzle_flash = 0.12 if cycle>3.3 and cycle<3.45 else 0.0
			air.weapon_recoil = 5 if air.muzzle_flash>0 else 0
			air.locked_aim = air.global_position+Vector2(-300,130)
			air._pose_parts()
			for part in [air.body_part,air.propulsion_part,air.weapon_part]: part.queue_redraw()
			air.queue_redraw()
		queue_redraw()
	func _draw():
		draw_rect(Rect2(0,0,1920,1080),Color("0e1921"))
		Art.text(self,Vector2(32,44),"LETZTE SCHICHT / LUFTKONTAKTE",29,Art.LIGHT)
		Art.text(self,Vector2(34,70),"Zwölf Klassen · getrennte Rotoren, Triebwerke, Rümpfe und schwenkbare Waffen",15,Art.MUTED)
		for index in AirEnemyCatalog.CLASS_ORDER.size():
			var x := 18+(index%4)*480
			var y := 92+floori(float(index)/4)*300
			var plate := Rect2(x,y,444,284)
			draw_rect(plate,Color("445153"))
			draw_texture_rect_region(skyline,plate.grow(-3),Rect2(700,0,600,490),Color("65747e"))
			draw_rect(Rect2(x+3,y+3,438,64),Color("17252d"))
			draw_rect(Rect2(x+3,y+242,438,39),Color("17252d"))
			var kind: String = AirEnemyCatalog.CLASS_ORDER[index]
			Art.text(self,Vector2(x+17,y+28),str(AirEnemyCatalog.PROFILES[kind].label),20,Art.LIGHT)
			Art.text(self,Vector2(x+17,y+50),"WELLE %02d · %d LP" % [AirEnemyCatalog.INTRO_WAVES[kind],ceili(machines[index].max_hp)],12,Art.AMBER)
			Art.text(self,Vector2(x+17,y+267),roles[index],13,Art.LIGHT)
			for corner in [plate.position+Vector2(7,7),plate.end-Vector2(8,8)]:
				draw_rect(Rect2(corner,Vector2(3,3)),Art.MUTED)
		Art.text(self,Vector2(34,1035),"ANIMIERTE INSPEKTIONSSZENE / arrangierte Positionen und Angriffsposen / tatsächlicher Godot-Renderer",13,Art.MUTED)
		Art.text(self,Vector2(34,1063),"Separat geprüft: reale Dach- und Glaskollision, Flugbahnen, Verwundbarkeit, Bergung, endliche Munition und EP.",13,Art.LIGHT)

func _initialize(): call_deferred("run")
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Air gallery needs an actual rendering display")
		quit(1)
		return
	ThemeDB.fallback_font = preload("res://assets/mono.ttf")
	root.size = Vector2i(1920,1080)
	var gallery := Gallery.new()
	root.add_child(gallery)
	for index in AirEnemyCatalog.CLASS_ORDER.size():
		var air = load("res://scenes/air_enemy.tscn").instantiate()
		air.kind = AirEnemyCatalog.CLASS_ORDER[index]
		air.wave = int(AirEnemyCatalog.INTRO_WAVES[air.kind])
		gallery.add_child(air)
		air.set_physics_process(false)
		air.position = Vector2(228+(index%4)*480,300+floori(float(index)/4)*300)
		air.scale = Vector2.ONE*2.05
		air.show_status_labels = false
		gallery.machines.append(air)
	var directory := "res://artifacts/air-gallery-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 90:
		await physics_frame
		await physics_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.save_png(directory+"/%03d.png" % frame)
		if frame==48:
			screenshot.save_png("res://artifacts/air-enemy-gallery.png")
	print("AIR GALLERY: 12 actual aircraft visual scenes, 90 rendered animation frames; arranged inspection fixture, not a combat playthrough")
	gallery.queue_free()
	await process_frame
	await process_frame
	quit()
