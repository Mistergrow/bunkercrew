extends Node2D

var layer = 0
var rng = RandomNumberGenerator.new()

func _draw() -> void:
	rng.seed = 817 + layer
	match layer:
		0: _ruins()
		1: _earth()
		2: _interiors()
		3: _props()
		4: _structure()

func _ruins() -> void:
	for i in range(25):
		var x = 785 + i * 47
		var h = rng.randi_range(25, 104)
		var rect = Rect2(x, 430 - h, rng.randi_range(17,36), h)
		draw_rect(rect, Color("232b30"))
		for y in range(int(rect.position.y)+10, 420, 17):
			for wx in range(x+5, x+int(rect.size.x)-3, 10):
				draw_rect(Rect2(wx,y,3,7), Color("3b3a3e"))
		if i % 3 == 0:
			draw_line(Vector2(x+4,rect.position.y),Vector2(x+4,rect.position.y-20),Color("252e32"),3)
	for x in [930,1200,1345,1650,1850]:
		draw_line(Vector2(x,422),Vector2(x-8,300),Color("25282a"),5)
		draw_line(Vector2(x-25,317),Vector2(x+10,311),Color("25282a"),4)
		draw_polyline(PackedVector2Array([Vector2(x,310),Vector2(x+60,335),Vector2(x+130,315)]),Color("24272a"),2)

func _earth() -> void:
	draw_rect(Rect2(-960,447,3360,1500),Color("161a1d"))
	draw_rect(Rect2(0,245,80,580),Color("282929"))
	# The original hillside continues left when the camera reveals the perimeter.
	for x in [-960,-720,-480,-240,0]:
		var width := 240 if x < 0 else 78
		draw_texture_rect_region(preload("res://assets/rock.png"),Rect2(x,245,width,204),Rect2(90,80,width,204),Color("9b9c90"))
		for stone in range(0,width,12):
			draw_rect(Rect2(x+stone,243-posmod(stone,7),11,6),Color("55594d"))
	# Repeating geology texture; mining blocks and collision are independent objects.
	for x in range(-960,2400,480):
		draw_texture_rect(preload("res://assets/rock.png"),Rect2(x,447,480,480),false,Color(0.78,0.81,0.84))
	draw_texture_rect_region(preload("res://assets/rock.png"),Rect2(0,245,80,210),Rect2(200,160,210,550),Color(0.75,0.78,0.8))
	for y in [465,630,838]:
		for x in range(-960,2400,15):
			draw_rect(Rect2(x,y+rng.randi_range(-5,7),rng.randi_range(6,21),3),Color("514438"))

func _interiors() -> void:
	# Recessed cutaway rooms. These surfaces carry no collision.
	_panel(Rect2(80,263,695,163),Color("373b38"))
	_panel(Rect2(80,452,695,144),Color("383b36"))
	draw_rect(Rect2(82,638,1112,159),Color("222322"))
	for i in range(380):
		var p = Vector2(rng.randi_range(83,1190),rng.randi_range(642,795))
		draw_rect(Rect2(p,Vector2(rng.randi_range(4,19),rng.randi_range(3,11))),[Color("292a26"),Color("302d25"),Color("383127")][i%3])
	for x in [100,294,618,802,1170]:
		draw_rect(Rect2(x,639,13,160),Color("3e3026"))
		draw_rect(Rect2(x,639,3,160),Color("68503a"))
		draw_line(Vector2(x+8,673),Vector2(x+43,640),Color("54402d"),9)
		draw_rect(Rect2(x-6,675,25,8),Color("222627"))
	draw_rect(Rect2(90,636,1090,10),Color("584735"))
	draw_line(Vector2(97,638),Vector2(1177,638),Color("8a6a46"),2)
	for room_y in [275,461]:
		draw_polyline(PackedVector2Array([Vector2(101,room_y+102),Vector2(101,room_y),Vector2(747,room_y),Vector2(747,room_y+90)]),Color("181e20"),8)
		draw_line(Vector2(105,room_y),Vector2(745,room_y),Color("6b6751"),2)
		for x in range(100,750,60):
			draw_rect(Rect2(x,room_y-4,4,10),Color("a28a5b"))
	for y in [300,495]:
		Art.text(self,Vector2(301,y),LocaleText.text("SEKTOR 07") if y==300 else LocaleText.text("MATERIALWERK"),12,Color("979985"))
		Art.text(self,Vector2(301,y+17),LocaleText.text("BUNKERCREW / BETRIEB"),9,Color("71776b"))

func _panel(rect: Rect2, _base: Color) -> void:
	rect = rect.grow(9)
	BunkerArchitecture.rear_wall(self,rect)

func _props() -> void:
	# Dressing objects are separate swappable scenes; only rails and stencils live here.
	for y in [796,799]:
		draw_line(Vector2(91,y),Vector2(1190,y),Color("695b47"),2)
	for x in range(94,1180,33):
		draw_line(Vector2(x,794),Vector2(x+12,800),Color("3f3b32"),3)
	Art.text(self,Vector2(107,681),LocaleText.text("MINE  /  -12 M"),12,Color("88765a"))
	Art.text(self,Vector2(894,679),LocaleText.text("ERZ + SAND"),12,Color("897861"))
	Art.text(self,Vector2(392,701),LocaleText.text("FREIER TRANSPORTWEG"),11,Color("b5b58d"))
	Art.text(self,Vector2(466,719),LocaleText.text("OFEN →"),11,Art.AMBER)
	for x in range(380,600,37):
		draw_line(Vector2(x,793),Vector2(x+19,793),Color("9a956d"),2)

func _structure() -> void:
	for rect in [Rect2(67,245,683,18),Rect2(67,430,735,22),Rect2(67,600,730,24),Rect2(65,244,20,580),Rect2(75,800,1133,26)]:
		_concrete(rect)
	# Exterior road is a solid collision surface, visibly distinct from empty sky.
	draw_rect(Rect2(802,430,1598,22),Color("5f5c4d"))
	for x in range(803,2400,10):
		draw_rect(Rect2(x,430-rng.randi_range(0,4),rng.randi_range(3,13),4),Color("8a7b5d"))
	for x in [85,283,766]:
		for y in [263,452]:
			if x==766 and y==263:
				continue
			_concrete(Rect2(x,y,15,148 if y==452 else 167))
	# Service ladders are foreground silhouettes and line up with the actual climb areas.
	for data in [[240,215,600],[342,570,800]]:
		var x = data[0]
		for side in [-12,12]:
			draw_line(Vector2(x+side,data[1]),Vector2(x+side,data[2]),Color("171f22"),7)
			draw_line(Vector2(x+side-1,data[1]),Vector2(x+side-1,data[2]),Color("a28352"),3)
		for y in range(data[1]+5,data[2],14):
			draw_line(Vector2(x-12,y+2),Vector2(x+12,y+2),Color("222729"),5)
			draw_line(Vector2(x-12,y),Vector2(x+12,y),Color("c3a067"),3)
	for x in range(80,747,23):
		draw_line(Vector2(x,247),Vector2(x+8,259),Color("92825b"),3)
	Art.text(self,Vector2(86,233),LocaleText.text("DACHZUGANG"),10,Art.MUTED)
	Art.text(self,Vector2(395,417),LocaleText.text("← KERN     WARTUNGSGANG →"),10,Color("b1aa88"))
	Art.text(self,Vector2(1100,414),LocaleText.text("ANFLUG / OST"),10,Color("d2b690"))
	# Tiny roof rubble and bent reinforcing rods.
	for i in range(45):
		var x = rng.randi_range(82,575)
		draw_rect(Rect2(x,241-rng.randi_range(0,7),rng.randi_range(3,9),5),Color("575b52"))
	for x in [97,155,405,510]:
		draw_line(Vector2(x,244),Vector2(x-5,224),Color("695f4d"),2)

func _concrete(rect: Rect2) -> void:
	BunkerArchitecture.concrete(self,rect)
