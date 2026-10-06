class_name GlassFurnace
extends RecipeStation
const SurfaceArt := preload("res://scripts/station_surface_art.gd")
const MechanismArt := preload("res://scripts/machine_surface_details.gd")

# Kept as a named buffer for editor/debug tools and existing glass checks.
var limestone_amount: int:
	get:
		return amount_for("limestone")
	set(value):
		set_amount("limestone", value)

func _ready() -> void:
	kind = "glass"
	super._ready()
	add_to_group("glass_furnaces")

func _draw() -> void:
	_draw_oven()
	UiArt.world_label(self, Vector2(0, -148), interaction_title(), world_status(), world_status_color())
	if working:
		Art.bar(self, Rect2(-49, -127, 99, 3), production_time / duration(), Art.AMBER)
	for index in output_amount:
		var offset := Vector2(45+index*7,-27-index*2)
		draw_rect(Rect2(offset,Vector2(16,23)),Color("244047"))
		draw_rect(Rect2(offset+Vector2.ONE,Vector2(14,21)),Color(0.45,0.80,0.85,0.67))
		draw_rect(Rect2(offset+Vector2.ONE,Vector2(14,21)),Color("bce5df"),false,1)
		draw_line(offset+Vector2(3,13),offset+Vector2(11,5),Color("ecfff0"),1)

func _draw_oven() -> void:
	draw_rect(Rect2(-64,-3,145,5),Color(0,0,0,0.38))
	SurfaceArt.exhaust(self, PackedVector2Array([Vector2(57,-137),Vector2(69,-137)]), elapsed, working)
	# Twin flues, cast housing, refractory bricks and a separate output roller bed.
	draw_rect(Rect2(26,-99,47,9),Art.INK)
	SurfaceArt.face(self, Rect2(29,-97,41,5), Color("68776f"), 4)
	for x in [52,64]:
		draw_rect(Rect2(x,-136,10,43),Art.INK)
		SurfaceArt.face(self, Rect2(x+2,-133,6,37), Color("75827b"), x)
		SurfaceArt.face(self, Rect2(x,-128,10,4), Color("a7aa95"), x+1)
		draw_rect(Rect2(x+2,-119,1,17),Color("b5a080"))
		draw_rect(Rect2(x+6,-116,1,12),Color("343b31"))
	draw_colored_polygon(PackedVector2Array([Vector2(-46,-89),Vector2(-33,-105),Vector2(29,-105),Vector2(46,-88),Vector2(47,-11),Vector2(-47,-11)]),Art.INK)
	SurfaceArt.polygon(self, PackedVector2Array([Vector2(-42,-87),Vector2(-31,-101),Vector2(27,-101),Vector2(42,-86),Vector2(42,-14),Vector2(-43,-14)]), Color("67716b"), 3)
	draw_line(Vector2(-31,-102),Vector2(27,-102),Color("b4a487"),1)
	draw_line(Vector2(-42,-87),Vector2(-31,-101),Color("91856c"),1)
	draw_line(Vector2(28,-101),Vector2(42,-86),Color("403e33"),2)
	draw_line(Vector2(-41,-86),Vector2(40,-86),Color("3a3c30"),1)
	draw_rect(Rect2(-38,-82,73,57),Color("514738"))
	for row in 4:
		for column in 4:
			var pos := Vector2(-36+column*18+(3 if row%2 else 0),-80+row*14)
			SurfaceArt.face(self, Rect2(pos, Vector2(15,11)), Color("a58a63"), row*4+column, "brick")
	draw_rect(Rect2(-29,-70,54,39),Color("161f22"))
	SurfaceArt.firebox(self, Rect2(-26,-67,48,33), elapsed, working)
	MechanismArt.chamber_frame(self,Rect2(-29,-70,54,39))
	SurfaceArt.face(self, Rect2(-34,-30,65,6), Color("303d3d"), 2)
	draw_line(Vector2(-30,-71),Vector2(-30,-32),Color("b39a71"),2)
	SurfaceArt.panel(self, Rect2(-47,-18,95,9), Color("8a9080"), 4)
	for x in [-38,29]:
		draw_rect(Rect2(x,-10,11,10),Color("1b282d"))
		SurfaceArt.face(self, Rect2(x-2,-5,15,4), Color("5b5b48"), x+40)
	# Separate material funnel and control box keep the inputs and hot chamber readable.
	draw_colored_polygon(PackedVector2Array([Vector2(-67,-76),Vector2(-44,-76),Vector2(-48,-51),Vector2(-61,-51)]),Art.INK)
	SurfaceArt.polygon(self, PackedVector2Array([Vector2(-64,-73),Vector2(-47,-73),Vector2(-51,-55),Vector2(-59,-55)]), Color("999b81"), 5)
	MechanismArt.polygon(self,PackedVector2Array([Vector2(-47,-73),Vector2(-44,-76),Vector2(-48,-53),Vector2(-51,-55)]),"dark",1)
	draw_line(Vector2(-63,-74),Vector2(-47,-74),Color("b8ac87"),1)
	draw_rect(Rect2(-63,-73,15,3),Balance.RESOURCE_COLORS["sand"] if input_amount>0 else Color("414d47"))
	draw_rect(Rect2(-60,-64,10,3),Balance.RESOURCE_COLORS["limestone"] if limestone_amount>0 else Color("566359"))
	draw_rect(Rect2(48,-70,22,42),Art.INK)
	SurfaceArt.panel(self, Rect2(50,-68,18,38), Color("69776f"), 2)
	draw_rect(Rect2(52,-34,14,2),Color("384947"))
	draw_circle(Vector2(59,-58),6,Color("151f24"))
	draw_line(Vector2(59,-58),Vector2(62,-62 if working else -55),Art.AMBER,2)
	draw_rect(Rect2(54,-45,4,5),Color("eedda3") if working else Color("69765a"))
	draw_rect(Rect2(61,-45,4,5),Color("64b8b4"))
	MechanismArt.face(self,Rect2(43,-8,37,7),"dark",1)
	for x in range(45,78,7):
		draw_circle(Vector2(x,-9),3,Color("9ea793"))
		var spoke := Vector2.from_angle(elapsed*4 if working else 0.4)*2
		draw_line(Vector2(x,-9)-spoke,Vector2(x,-9)+spoke,Color("435450"),1)
	Art.bolts(self,Rect2(-43,-91,83,69))
