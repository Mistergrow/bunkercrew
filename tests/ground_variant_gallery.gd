extends SceneTree
## Rendered variant inspection: prepared poses, original chassis and live equipment layers.
## This is a visual inspection gallery, not a substitute for the physics checks.

class Gallery extends Node2D:
	const CLASSES := ["shield_guard","lancer","sniper","demolisher","repair_crawler","bastion"]
	var machines: Array = []
	var elapsed := 0.0
	var names := ["SCHILDWACHE", "LANZENTRÄGER", "ZIELSUCHER", "SPRENGBRECHER", "INSTANDSETZER", "BASTION"]
	var roles := ["Takt-Schild · Ladung & Öffnungsfenster", "Ansturm mit sichtbarer Warnung", "Präzisionslauf · lange Zielaufladung", "Sprenghammer · gedeckte Schockwelle", "Endlicher Reparaturvorrat", "Sechsersalve · offene Kühllamellen"]
	func _process(delta: float) -> void:
		elapsed += delta
		for index in machines.size():
			var machine = machines[index]
			machine.age += delta
			machine.abilities.update(delta)
			if machine.kind=="bastion": machine.abilities.vent_time=1.0 if fmod(elapsed,4.0)>2.0 else 0.0
			if machine.kind=="repair_crawler":
				machine.abilities.repair_flash=0.22 if fmod(elapsed,2.0)<0.6 else 0.0
				machine.abilities.repair_endpoint=machine.global_position+Vector2(110,-40)
			machine.moving = index % 2 == 0
			machine.gait += delta * float(machine.profile.gait) * 0.75
			var cycle := fmod(elapsed+index*0.21,3.8)
			machine.windup = clampf(cycle-1.4,0,float(machine.profile.windup))
			machine.muzzle_flash = 0.08 if cycle > 2.9 and cycle < 3.02 else 0.0
			machine.weapon_recoil = 4 if machine.muzzle_flash > 0 else 0
			machine._pose_parts()
			machine.target.position.y = machine.weapon_part.global_position.y+40+sin(elapsed+index)*45
			machine._pose_parts()
			machine.tracer_end = machine.to_local(machine.target_attack_point())
			for part in [machine.body_part,machine.legs_part,machine.weapon_part]: part.queue_redraw()
			machine.variant_visual.queue_redraw()
			machine.queue_redraw()
		queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(0,0,1440,900),Color("111b20"))
		for row in range(2):
			for col in range(3):
				var origin := Vector2(col*480,90+row*370)
				var plate := Rect2(origin+Vector2(15,12),Vector2(450,348))
				draw_rect(plate,Color("222d2c"))
				draw_rect(plate.grow(-6),Color("303832"))
				for n in range(115):
					var p := origin+Vector2(23+(n*67)%431,20+(n*43)%326)
					draw_rect(Rect2(p,Vector2(2+n%3,1)),Color("42483c") if n%2 else Color("252e2b"))
				for x in [origin.x+30,origin.x+450]:
					draw_line(Vector2(x,origin.y+17),Vector2(x,origin.y+355),Color("495046"),2)
					draw_rect(Rect2(x-2,origin.y+20,4,4),Color("a59f7c"))
					draw_rect(Rect2(x-2,origin.y+349,4,4),Color("a59f7c"))
				var floor_y := 380+row*400
				draw_rect(Rect2(origin.x+18,floor_y,444,17),Color("697060"))
				draw_rect(Rect2(origin.x+18,floor_y,444,3),Color("a3a48a"))
				for grate in range(40):
					draw_rect(Rect2(origin.x+23+grate*11,floor_y+6,7,3),Color("343e38"))
				var index := row*3+col
				var label_y := 125+row*370
				Art.text(self,Vector2(origin.x+36,label_y),names[index],23,Art.LIGHT)
				Art.text(self,Vector2(origin.x+36,label_y+25),"AB WELLE %02d · %s" % [EnemyCatalog.INTRO_WAVES[CLASSES[index]],roles[index]],12,Art.AMBER)
		Art.text(self,Vector2(30,48),"LETZTE SCHICHT  /  MASCHINENKONTAKTE",30,Art.LIGHT)
		Art.text(self,Vector2(33,74),"Sechs neue Bodentypen · Originalchassis + eigene Schilde, Werkzeuge, Läufe und Kühllamellen",15,Art.MUTED)
		draw_rect(Rect2(0,831,1440,69),Color("0b141a"))
		Art.text(self,Vector2(30,860),"STEUERUNG & SCHADEN: reale Kollisionsgeometrie · Angriffstelegraphen · begrenzte Skalierung bis Welle 20",14,Art.LIGHT)
		Art.text(self,Vector2(30,885),"Visuelle Inspektionsszene / tatsächlicher Godot-Renderer / generierte austauschbare Chassis-Module",12,Art.MUTED)

func _initialize() -> void:
	call_deferred("render_gallery")

func render_gallery() -> void:
	ThemeDB.fallback_font = load("res://assets/mono.ttf")
	var gallery := Gallery.new()
	root.add_child(gallery)
	for index in 6:
		var machine = load("res://scenes/enemy.tscn").instantiate()
		machine.kind = Gallery.CLASSES[index]
		machine.show_status_labels = false
		machine.position = Vector2(266+(index%3)*480,375 if index<3 else 775)
		gallery.add_child(machine)
		machine.scale = Vector2.ONE*(1.55 if machine.kind=="bastion" else (1.8 if machine.kind=="demolisher" else 2.0))
		var target := Node2D.new()
		target.position = machine.position + Vector2(-190,0)
		gallery.add_child(target)
		machine.target = target
		machine.set_physics_process(false)
		gallery.machines.append(machine)
	var directory := "res://artifacts/ground-gallery-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	for frame in 150:
		await physics_frame
		await physics_frame
		await RenderingServer.frame_post_draw
		var screenshot := root.get_texture().get_image()
		screenshot.save_png(directory+"/%03d.png" % frame)
		if frame==73: screenshot.save_png("res://artifacts/enemy-ground-specialists.png")
	print("GROUND GALLERY: 6 actual machine scenes, 150 rendered frames; arranged positions and attack poses")
	gallery.free()
	quit()
