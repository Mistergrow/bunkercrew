extends Node2D
## Rooms open as complete accessible spaces. Decoration follows the bunker
## parallax; floors, production machines and resource piles stay in world space.
const PROP = preload("res://scenes/level_prop.tscn")
var game
var glassworks_open := false
var exterior_open := false
var dome_yard_open := false
var glass_furnace
var props: Array = []
var clock := 0.0

func _ready() -> void:
	z_index = -8
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _prop(kind: int, at: Vector2, size: Vector2, anchor: int = 0) -> void:
	var prop = PROP.instantiate()
	prop.kind_index = kind
	prop.position = at
	prop.display_size = size
	prop.anchor = anchor
	prop.modulate = Color("c0beb0")
	add_child(prop)
	props.append([prop, at])

func open_glassworks() -> void:
	if glassworks_open:
		return
	glassworks_open = true
	game.add_terrain(Rect2(775,600,420,22))
	game.add_terrain(Rect2(1195,452,24,170))
	glass_furnace = game._entity("glass_furnace",Vector2(1030,600))
	game._entity("wall",Vector2(1040,430))
	game._entity("supply",Vector2(850,600),{"kind":"limestone","amount":12})
	game._entity("supply",Vector2(1160,600),{"kind":"sand","amount":12})
	_prop(5,Vector2(890,468),Vector2(23,35),1)
	_prop(5,Vector2(1140,468),Vector2(23,35),1)
	_prop(7,Vector2(962,600),Vector2(34,69))
	_prop(6,Vector2(918,512),Vector2(45,45),1)
	_prop(10,Vector2(1134,510),Vector2(29,36),1)
	_prop(2,Vector2(907,600),Vector2(61,24))
	queue_redraw()

func open_exterior() -> void:
	if exterior_open:
		return
	exterior_open = true
	game.add_terrain(Rect2(1440,430,370,22))
	game._entity("wall",Vector2(1185,430))
	# A shattered maintenance outpost remains behind the accessible approach.
	_prop(13,Vector2(1535,430),Vector2(114,42))
	_prop(3,Vector2(1644,430),Vector2(47,40))
	_prop(4,Vector2(1690,430),Vector2(31,48))
	queue_redraw()

func open_dome_yard() -> void:
	if dome_yard_open:
		return
	dome_yard_open = true
	game.add_terrain(Rect2(1810,430,90,22))
	_prop(5,Vector2(1250,317),Vector2(25,36),1)
	queue_redraw()

func _process(delta: float) -> void:
	clock += delta
	var shift: Vector2 = game.scenery.offset * 0.25
	for entry in props:
		entry[0].position = entry[1] - shift
	queue_redraw()

func _draw() -> void:
	if glassworks_open:
		# The final wide camera sees beyond the original mine's right-hand geology.
		# Continue solid earth below the surface, outside the expanded bunker wall.
		for x in range(1209,2880,480):
			draw_texture_rect(preload("res://assets/rock.png"),Rect2(x,440,480,385),false,Color(0.68,0.72,0.76))
	if glassworks_open:
		_draw_glassworks()
	if exterior_open:
		_draw_outpost()
	if glassworks_open:
		_draw_defense_foundations()

func _draw_glassworks() -> void:
	var shift: Vector2 = game.scenery.offset * 0.58
	draw_rect(Rect2(777,451,418,149),Color("202726"))
	draw_set_transform(-shift)
	draw_texture_rect(preload("res://assets/bunker_wall.png"),Rect2(774,448,425,157),false,Color("9a9682"))
	for band in 4:
		draw_rect(Rect2(779,452+band*5,411,5),Color(0.02,0.025,0.02,0.34-band*0.065))
		draw_rect(Rect2(779,596-band*3,411,3),Color(0.02,0.025,0.02,0.25-band*0.05))
	draw_rect(Rect2(985,477,118,111),Color(0.015,0.022,0.02,0.14))
	draw_line(Vector2(990,588),Vector2(1099,588),Color("4e594b"),2)
	# Recessed wall bays, soot above the kiln, service conduit and a wall vent.
	for x in [787,985,1180]:
		draw_rect(Rect2(x,451,9,150),Color("343d36"))
		draw_line(Vector2(x+1,451),Vector2(x+1,599),Color("666c59"),2)
	for i in range(8):
		draw_rect(Rect2(1005-i*2,455,43+i*4,65-i*5),Color(0.08,0.07,0.06,0.04))
	draw_polyline(PackedVector2Array([Vector2(797,551),Vector2(797,468),Vector2(1178,468),Vector2(1178,565)]),Color("242a26"),7)
	draw_line(Vector2(801,466),Vector2(1180,466),Color("9c885c"),2)
	for x in range(800,1180,44):
		draw_rect(Rect2(x,463,3,11),Color("b5a077"))
	Art.text(self,Vector2(813,494),LocaleText.text("GLASWERK / 03"),13,Color("b9ad88"))
	Art.text(self,Vector2(813,510),LocaleText.text("SAND + KALK"),10,Color("9b9274"))
	draw_set_transform(Vector2.ZERO)
	_slab(Rect2(776,600,431,22))
	_slab(Rect2(1187,451,22,171))
	# The opening into the existing mixer room has no new door or collision.
	draw_rect(Rect2(776,451,420,10),Color("303733"))
	draw_line(Vector2(778,452),Vector2(1192,452),Color("aaa88c"),2)
	for x in range(786,1185,20):
		draw_line(Vector2(x,605),Vector2(x+8,614),Color("a69666"),3)
	Art.text(self,Vector2(829,591),LocaleText.text("KALK"),9,Color("d3d1b9"))
	Art.text(self,Vector2(1128,591),LocaleText.text("SAND"),9,Color("c4af7b"))

func _slab(rect: Rect2) -> void:
	draw_rect(rect,Color("242a28"))
	draw_rect(rect.grow(-2),Color("62685b"))
	draw_line(rect.position,Vector2(rect.end.x,rect.position.y),Color("a4a68b"),2)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(rect.position.x+rect.position.y*13)
	for index in int(rect.get_area()/50):
		var p := Vector2(rng.randf_range(rect.position.x+3,rect.end.x-4),rng.randf_range(rect.position.y+3,rect.end.y-3)).round()
		draw_rect(Rect2(p,Vector2(3,2)),Color("454e44") if index%2 else Color("8a8e7a"))

func _draw_outpost() -> void:
	var shift: Vector2 = game.scenery.offset * 0.22
	draw_set_transform(-shift)
	# Broken masonry, exposed reinforcement and cables echo the bunker materials.
	_slab(Rect2(1486,337,19,92))
	_slab(Rect2(1734,368,21,62))
	_slab(Rect2(1473,333,107,16))
	for x in range(1490,1565,19):
		draw_line(Vector2(x,332),Vector2(x+8,312),Color("857052"),2)
	draw_polyline(PackedVector2Array([Vector2(1504,340),Vector2(1570,362),Vector2(1640,378),Vector2(1734,370)]),Color("212829"),3)
	for i in range(15):
		var x := 1540+i*13
		var h := 7+posmod(i*17,19)
		draw_colored_polygon(PackedVector2Array([Vector2(x,427),Vector2(x+4,427-h),Vector2(x+14,424-floori(h/2.0)),Vector2(x+19,430)]),Color("5c6254") if i%2 else Color("434c45"))
	draw_rect(Rect2(1512,370,79,25),Color("343a33"))
	Art.text(self,Vector2(1518,387),LocaleText.text("OSTWERK"),12,Color("a49b7b"))
	draw_set_transform(Vector2.ZERO)

func _draw_defense_foundations() -> void:
	# Foundations and buried service cables physically tie new defense slots to
	# the existing front, leaving the turret's overhead firing corridor open.
	var edge := 1210.0 if exterior_open else 1065.0
	_slab(Rect2(870,423,edge-870,16))
	for x in range(881,int(edge),24):
		draw_line(Vector2(x,424),Vector2(x+7,431),Color("9f9167"),2)
	var shift: Vector2 = game.scenery.offset*0.25
	draw_set_transform(-shift)
	for x in [1040,1185]:
		if x==1185 and not exterior_open: continue
		draw_colored_polygon(PackedVector2Array([Vector2(x-48,423),Vector2(x-25,400),Vector2(x-20,399),Vector2(x-20,423)]),Color("4b574a"))
		draw_line(Vector2(x-47,421),Vector2(x-23,399),Color("90977d"),2)
		draw_line(Vector2(x-34,418),Vector2(x+34,418),Color("afa57d"),2)
		for side in [-1,1]:
			draw_rect(Rect2(x+side*33,401,3,21),Color("222a28"))
			draw_rect(Rect2(x+side*33-2,398,7,5),Color("c8a369"))
	draw_set_transform(Vector2.ZERO)
