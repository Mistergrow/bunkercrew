extends SceneTree
## Rendered material/anchor inspection at integer magnification. Dry and wet
## states are arranged deliberately; actor_wetness_test covers actual transitions.

class Gallery extends Node2D:
	var actors: Array = []
	var elapsed := 0.0
	var labels := ["ARBEITSKLEIDUNG / HELM","LAUF / STIEFEL","LEITER / TRITTE","VERWUNDET / BODENLAGE","PANZERUNG / HYDRAULIK","LUFTMASCHINE / WAFFE"]
	func _process(delta: float):
		elapsed+=delta
		for pair in actors:
			for index in 2:
				var actor: Node2D=pair[index]
				actor.wetness.amount=0.0 if index==0 else 1.0
				actor.wetness.mud=0.0 if index==0 or actor.is_in_group("air_enemies") else 0.85
				actor.wetness.advance(delta)
				if actor is Worker:
					var visual: WorkerVisual=actor.get_node("PixelVisual")
					visual._process(delta)
					if int(actor.get_meta("card"))==0:
						visual.special_pose="helmet"
						visual.pose_skeleton=WorkerPoseArt.sample("helmet",fmod(elapsed/4.0,1.0))
					elif int(actor.get_meta("card"))==2:
						visual.pose_frame=int(elapsed*4)%8
					elif int(actor.get_meta("card"))==3:
						visual.special_pose="downed"
						visual.pose_skeleton=WorkerPoseArt.sample("downed",1.0)
					visual.queue_redraw()
				elif actor is SiegeMachine:
					actor.age+=delta
					actor.gait+=delta*3.0
					actor.moving=true
					actor._pose_parts()
					for part in [actor.body_part,actor.legs_part,actor.weapon_part]: part.queue_redraw()
				elif actor is AirMachine:
					actor.age+=delta
					actor.flight_velocity=Vector2(sin(elapsed)*35,0)
					actor._pose_parts()
					for part in [actor.body_part,actor.propulsion_part,actor.weapon_part]: part.queue_redraw()
		queue_redraw()
	func _draw():
		draw_rect(Rect2(0,0,1440,900),Color("111b20"))
		Art.text(self,Vector2(28,38),"LETZTE SCHICHT / NÄSSE & SCHMUTZ",26,Art.LIGHT)
		Art.text(self,Vector2(30,66),"Originalgrafiken · dieselbe Palette · dezente Feuchtigkeitsreflexe · Schlamm an den tatsächlichen Schuhen",13,Art.MUTED)
		for card in 6:
			var x:=18+card%3*480
			var y:=92+floori(float(card)/3)*350
			draw_rect(Rect2(x,y,444,333),Color("475249"))
			draw_rect(Rect2(x+2,y+2,440,329),Color("26332e"))
			Art.text(self,Vector2(x+12,y+26),labels[card],14,Art.LIGHT)
			Art.text(self,Vector2(x+70,y+54),"TROCKEN",12,Art.MUTED)
			Art.text(self,Vector2(x+267,y+54),"NASS",12,Art.CYAN)
			draw_line(Vector2(x+222,y+68),Vector2(x+222,y+282),Color("435249"),1)
			if card!=5:
				draw_rect(Rect2(x+9,y+282,426,5),Color("737b66"))
				draw_rect(Rect2(x+9,y+287,426,6),Color("131f20"))
			if card==2:
				for center in [x+118,x+320]:
					for side in [-1,1]: draw_rect(Rect2(center+side*30,y+90,5,190),Color("75775b"))
					for rung in 7: draw_rect(Rect2(center-30,y+94+rung*28,65,3),Color("8c886b"))
			Art.text(self,Vector2(x+12,y+316),"MATERIALVERGLEICH / %s / ARRANGIERTE ZUSTÄNDE"%("1× PIXEL" if card==5 else "2× PIXEL"),10,Art.MUTED)
		Art.text(self,Vector2(28,838),"ECHTER GODOT-RENDERER: gleiche Figuren und Animationsphasen; rechts volle Nässe, Bodeneinheiten mit anhaftendem Schlamm.",12,Art.LIGHT)
		Art.text(self,Vector2(28,866),"Im Spiel: langsames Durchnässen und Trocknen, ablaufende Tropfen, reale Fußkontakte und kein Malus auf Bewegung oder Kampf.",12,Art.MUTED)

func _initialize(): call_deferred("run")
func stop_actor(actor: Node):
	actor.set_physics_process(false)
	for child in actor.find_children("*","Node",true,false):
		child.set_physics_process(false)
		child.set_process(false)
func run():
	if DisplayServer.get_name()=="headless":
		push_error("Wet actor gallery requires actual rendering")
		quit(1)
		return
	InputSetup.install()
	ThemeDB.fallback_font=preload("res://assets/mono.ttf")
	root.size=Vector2i(1440,900)
	var gallery:=Gallery.new()
	root.add_child(gallery)
	for card in 6:
		var pair: Array=[]
		for side in 2:
			var actor: Node2D
			if card<4:
				actor=load("res://scenes/player.tscn").instantiate()
				actor.player_id=1
			elif card==4:
				actor=SiegeMachine.new()
				actor.kind="strider"
			else:
				actor=AirMachine.new()
				actor.kind="gunship"
			gallery.add_child(actor)
			stop_actor(actor)
			actor.position=Vector2(136+card%3*480+side*202,374+floori(float(card)/3)*350)
			actor.scale=Vector2.ONE*2
			actor.set_meta("card",card)
			if card==1: actor.velocity.x=80
			elif card==2: actor.climbing=true
			elif card==3:
				actor.hp=0
				actor.medical.state="downed"
				actor.medical.down_elapsed=1
			elif card==5:
				actor.position.y-=75
				actor.scale=Vector2.ONE
			pair.append(actor)
		gallery.actors.append(pair)
	var path:="res://artifacts/actor-weather-frames"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	for frame in 75:
		await physics_frame
		await physics_frame
		await RenderingServer.frame_post_draw
		var capture:=root.get_texture().get_image()
		capture.save_png(path+"/%03d.png"%frame)
		if frame==38: capture.save_png("res://artifacts/actor-wetness-gallery.png")
	print("ACTOR WEATHER GALLERY: 75 real rendered frames, arranged dry/wet material and medical/ladder/locomotion comparisons")
	gallery.queue_free()
	await process_frame
	await process_frame
	quit()
