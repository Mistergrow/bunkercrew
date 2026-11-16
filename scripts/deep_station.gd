class_name DeepProductionStation
extends RecipeStation
## Separate animated machine assemblies; all recipe and inventory work lives in
## RecipeStation. The press visibly stamps, while the alloy furnace heats plates.
const SurfaceArt := preload("res://scripts/station_surface_art.gd")
const MechanismArt := preload("res://scripts/machine_surface_details.gd")

func _draw() -> void:
	if kind == "ammo_press":
		_draw_press()
	else:
		_draw_alloy_furnace()
	var tint: Color = Balance.RESOURCE_COLORS[output_kind()]
	UiArt.world_label(self, Vector2(0, -145), interaction_title(), world_status(), world_status_color())
	if working:
		Art.bar(self, Rect2(-64, -124, 128, 3), production_time / duration(), tint)
	_draw_output()

func _panel(rect: Rect2, tint: Color, seed_value: int) -> void:
	SurfaceArt.panel(self, rect, tint, seed_value)

func _draw_press() -> void:
	draw_rect(Rect2(-72,-3,150,5),Color(0,0,0,0.4))
	# The static frame is kitbashed from the furnace's and the core cabinet's
	# painted steel and baked at one texel per world unit
	# (tools/bake_world_density_art.py, "press_frame"), so the press carries
	# the same material as the stations upstairs. Ram, flywheel, strip and
	# rounds stay separate moving parts on whole world units.
	var frame := WorldTexels.authored("press_frame")
	if frame != null:
		draw_texture(frame, Vector2(-70,-124))
	var stroke := roundf(pow((sin(elapsed*5.6)+1.0)*0.5,2.0)*25.0) if working else 2.0
	MechanismArt.shaft(self,Vector2(-5,-93),Vector2(-5,-72+stroke),6)
	MechanismArt.face(self,Rect2(-11,-93,13,4),"dark",3)
	var ram := WorldTexels.authored("press_ram")
	if ram != null:
		draw_texture(ram, Vector2(-25,-82+stroke))
	draw_rect(Rect2(-15,-68+stroke,23,6),Color("202c2d"))
	draw_rect(Rect2(-13,-66+stroke,19,3),Color("d6b45e"))
	draw_rect(Rect2(-13,-66+stroke,19,1),Color("f1d79a"))
	# A material strip advances over the bed; individual rounds move to the tray.
	draw_rect(Rect2(-62,-41,104,4),Art.INK)
	draw_rect(Rect2(-61,-40,102,2),Color("879e9a"))
	var feed := floorf(fmod(elapsed*19,17.0)) if working else 0.0
	for index in 5:
		var x := -57 + index*17 + feed
		if x < 38:
			draw_rect(Rect2(x,-40,7,1),Color("d5c091"))
	for index in 4:
		var x := 14 + index*7 + floorf(feed*0.3)
		draw_rect(Rect2(x,-45,3,8),Art.INK)
		draw_rect(Rect2(x,-44,2,7),Color("d0a456"))
		draw_rect(Rect2(x,-44,2,2),Color("f3d797"))
	MechanismArt.shaft(self,Vector2(44,-36),Vector2(64,-17),3)
	var angle := elapsed*4 if working else 0.5
	MechanismArt.wheel(self,Vector2(52,-104),17,angle)
	# Status lamp in the control box: whole texels, dark when idle.
	draw_rect(Rect2(-64,-71,6,5),Art.INK)
	draw_rect(Rect2(-63,-70,4,3),Art.AMBER if working else Color("4b5540"))
	if working:
		draw_rect(Rect2(-63,-70,1,1),Color("fff0bf"))
	if working and stroke > 23:
		for chip in 3:
			draw_rect(Rect2(10+chip*7,-48-chip*3,2,2),Color("f3d6a0"))

func _draw_alloy_furnace() -> void:
	draw_rect(Rect2(-75,-3,154,5),Color(0,0,0,0.4))
	# Two electrode columns enter a reinforced refractory chamber.
	for x in [-28,12]:
		_panel(Rect2(x,-125,14,45),Color("738083"),x+44)
		draw_rect(Rect2(x+4,-122,4,36),Color("bac0b2"))
		draw_rect(Rect2(x-3,-113,20,6),Color("34494e"))
		for fin in 3:
			MechanismArt.face(self,Rect2(x-2,-111+fin*7,18,3),"steel",fin)
	_panel(Rect2(-47,-83,91,66),Color("596a70"),61)
	_panel(Rect2(-41,-97,79,18),Color("6c7e80"),43)
	for x in [-51,43]:
		draw_rect(Rect2(x,-81,7,61),Color("283c45"))
		draw_rect(Rect2(x,-74,7,6),Color("b6b6a0"))
		draw_rect(Rect2(x,-36,7,6),Color("abac96"))
	draw_rect(Rect2(-36,-76,65,46),Color("282e31"))
	for row in 3:
		for column in 4:
			SurfaceArt.face(self, Rect2(-34+column*16,-74+row*14,14,12), Color("aaa085"), row*4+column, "brick")
	draw_rect(Rect2(-27,-68,47,31),Art.INK)
	SurfaceArt.firebox(self, Rect2(-25,-66,43,27), elapsed, working, true)
	MechanismArt.chamber_frame(self,Rect2(-27,-68,47,31))
	_panel(Rect2(-51,-18,103,12),Color("81928b"),22)
	for x in [-42,30]:
		draw_rect(Rect2(x,-6,14,6),Color("23343d"))
		MechanismArt.face(self,Rect2(x,-5,14,4),"dark",1)
	# A side cooling vessel and pressure gauge distinguish it from the glass oven.
	_panel(Rect2(-73,-68,19,52),Color("415d66"),4)
	for y in [-63,-50,-25]:
		SurfaceArt.face(self, Rect2(-75,y,23,4), Color("9ba89b"), y+70)
	MechanismArt.shaft(self,Vector2(-64,-69),Vector2(-64,-101),3,"brass")
	MechanismArt.shaft(self,Vector2(-64,-101),Vector2(-38,-101),3,"brass")
	MechanismArt.face(self,Rect2(-68,-85,8,4),"brass",2)
	_panel(Rect2(51,-74,24,42),Color("63787a"),29)
	draw_circle(Vector2(63,-63),7,Art.INK)
	draw_circle(Vector2(63,-63),5,Color("c5c6a9"))
	draw_line(Vector2(63,-63),Vector2(66,-66 if working else -60),Color("71432f"),2)
	draw_rect(Rect2(55,-50,6,7),Color("e8bd71") if working else Color("626f60"))
	draw_rect(Rect2(65,-50,5,7),Color("344d53"))

func _draw_output() -> void:
	MechanismArt.face(self,Rect2(44,-7,39,6),"dark",1)
	for x in range(46,81,7):
		draw_circle(Vector2(x,-7),3,Color("a3ad9d"))
		var axis := Vector2.from_angle(elapsed*4.0 if working else 0.3)*2
		draw_line(Vector2(x,-7)-axis,Vector2(x,-7)+axis,Color("465c5c"),1)
	for index in output_amount:
		var origin := Vector2(57+index*14,-21-index*2)
		if output_kind() == "alloy":
			MaterialArt.draw_material(self,"alloy",origin,0.7)
		else:
			draw_rect(Rect2(origin-Vector2(10,12),Vector2(21,21)),Art.INK)
			draw_rect(Rect2(origin-Vector2(8,10),Vector2(17,17)),Color("58644a"))
			draw_rect(Rect2(origin-Vector2(8,10),Vector2(17,3)),Color("b4b27e"))
			for round_index in 3:
				draw_rect(Rect2(origin+Vector2(-5+round_index*4,-4),Vector2(2,7)),Art.AMBER)
