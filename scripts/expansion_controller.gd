extends Node2D
## Supported shafts reach bounded natural seams. Rooms require their own actual
## excavation before any structural materials can be installed.
var game
var unlocked := false
var deeper_available := false
var open_depths := 0
var modules: Array = []
var props: Array[Node2D] = []
var shaft_ladder_index := -1

func _ready() -> void:
	z_index = -9

func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	_add_shaft(1,800)
	queue_redraw()

func unlock_deeper() -> void:
	if deeper_available:
		return
	deeper_available = true
	if open_depths == 1:
		_add_shaft(2,1020)

func _add_shaft(depth: int, floor_y: float) -> void:
	var site = preload("res://scripts/excavation_site.gd").new()
	site.game = game
	site.expansion = self
	site.depth = depth
	site.position = Vector2(420,floor_y)
	game.add_child(site)

func excavate(depth: int) -> bool:
	if depth != open_depths+1 or depth > (2 if deeper_available else 1):
		return false
	open_depths = depth
	var floor_y := 800.0 + depth*220.0
	game.floor_levels.append(floor_y)
	if depth == 1:
		shaft_ladder_index = game.ladders.size()
		game.ladders.append(Rect2(398,765,44,260))
	else:
		# One continuous shaft avoids competing overlap rectangles at the landing.
		# The paid flak may have appended its ladder before the first excavation.
		# Retain this shaft's own slot rather than replacing an unrelated route.
		assert(shaft_ladder_index>=0 and shaft_ladder_index<game.ladders.size())
		game.ladders[shaft_ladder_index] = Rect2(398,765,44,floor_y-760)
	game.add_terrain(Rect2(75,floor_y,1120,24))
	game.add_terrain(Rect2(58,floor_y-196,16,220))
	game.add_terrain(Rect2(1195,floor_y-196,24,220))
	var specs := [["furnace",550],["ammo_press",810],["depot",1070]] if depth==1 else [["core_room",550],["alloy",810],["armory",1070]]
	for spec in specs:
		var field = load("res://scripts/diggable_terrain.gd").new()
		field.setup(game,Rect2(spec[1]-96,floor_y-144,192,144))
		game.add_child(field)
		var site = preload("res://scenes/expansion_site.tscn").instantiate()
		site.game = game
		site.kind = spec[0]
		site.position = Vector2(spec[1],floor_y)
		site.excavation = field
		game.add_child(site)
		modules.append(site)
	for row in 3:
		for col in 3:
			game._entity("mine_block",Vector2(154+col*48,floor_y-120+row*48),{"kind":["ore","sand","limestone"][col] if depth==1 else ["tungsten","ore","tungsten"][col],"yield_amount":6 if depth==1 else 8})
	for x in [355,650,927,1155]:
		var prop = preload("res://scenes/level_prop.tscn").instantiate()
		prop.kind_index = 5
		prop.anchor = 1
		prop.display_size = Vector2(25,35)
		prop.position = Vector2(x,floor_y-158)
		add_child(prop)
		props.append(prop)
	# Deep seams are richer, so a twenty-wave defense remains materially finite
	# and feasible without respawning mined blocks or granting invisible supplies.
	if depth == 1 and deeper_available:
		_add_shaft(2,1020)
	queue_redraw()
	return true

func _process(_delta: float) -> void:
	if unlocked:
		queue_redraw()

func _draw() -> void:
	# The sealed first expansion is already inside the wider camera view. Keep
	# continuous earth behind it, and beyond the right edge of the final view.
	if unlocked:
		for x in range(-960,2880,480):
			for y in range(825,1920,480):
				draw_texture_rect(preload("res://assets/rock.png"),Rect2(x,y,480,480),false,Color(0.68,0.72,0.76))
	if open_depths == 0:
		Art.text(self,Vector2(393,821),LocaleText.text("TIEFBAU · NACH WELLE 5") if not unlocked else LocaleText.text("SCHACHT ABSTÜTZEN"),10,Color("96876b"))
		return
	for depth in open_depths:
		draw_set_transform(Vector2(0,depth*220))
		_draw_depth(depth)
	draw_set_transform(Vector2.ZERO)
	_draw_shaft()

func _draw_depth(depth: int) -> void:
	var origin := Vector2(0,depth*220)
	var shift: Vector2 = game.scenery.offset*0.48
	# Rough cave backing appears only behind dug space. Finished rooms add their
	# own masonry lining above this dark rear surface, never a free full-width hall.
	draw_set_transform(origin-shift)
	draw_rect(Rect2(75,838,1120,182),Color("151c1b"))
	for x in range(75,1195,280):
		draw_texture_rect_region(preload("res://assets/rock.png"),Rect2(x,838,280,182),Rect2(posmod(x,180),90,280,182),Color("414940"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 712+depth
	for x in range(78,1195,17):
		var h := rng.randi_range(4,21)
		draw_colored_polygon(PackedVector2Array([Vector2(x,840),Vector2(x+20,840),Vector2(x+14,840+h),Vector2(x+4,849+h*0.2)]),Color("262f29"))
	for x in [307,390]:
		draw_rect(Rect2(x,846,10,174),Color("443c2d"))
		draw_line(Vector2(x+1,848),Vector2(x+1,1016),Color("79664a"),2)
		draw_line(Vector2(x+5,870),Vector2(x+33,847),Color("625138"),7)
	# A service cable is attached to the dug shaft, with masonry only at landings.
	draw_line(Vector2(387,850),Vector2(387,1015),Color("c4a062"),2)
	Art.text(self,Vector2(305,873),"-24 M" if depth==0 else "-36 M",11,Color("b5a480"))
	Art.text(self,Vector2(114,858),LocaleText.text("Eisenerz / Sand / Kalkstein") if depth==0 else LocaleText.text("Wolframerz / Eisenerz"),10,Color("ad9c79"))
	draw_set_transform(origin)
	# Earth remains around a narrow lined shaft and its accessible gallery floor.
	for rect in [Rect2(397,823,8,199),Rect2(436,823,8,199)]:
		draw_rect(rect,Color("313e35"))
		draw_line(rect.position,rect.position+Vector2(0,rect.size.y),Color("6e7763"),2)
	draw_rect(Rect2(75,1020,1120,22),Color("343d33"))
	draw_rect(Rect2(75,1020,1120,4),Color("8b8b70"))
	for x in range(82,1190,29):
		draw_rect(Rect2(x,1026,12,3),Color("686e58"))
	draw_rect(Rect2(75,1013,1120,7),Color(0.02,0.025,0.02,0.4))
	Art.text(self,Vector2(447,996),LocaleText.text("← SCHACHT"),9,Color("b39d6b"))

func _draw_shaft() -> void:
	# One uninterrupted shaft follows the merged climb rectangle. Rendering after
	# every rear room keeps intermediate floors from erasing or doubling its rungs.
	var bottom := 800 + open_depths * 220
	draw_rect(Rect2(402,780,36,bottom-780),Color(0.015,0.025,0.02,0.38))
	for side in [-12,12]:
		draw_line(Vector2(420+side,774),Vector2(420+side,bottom),Art.INK,7)
		draw_line(Vector2(419+side,774),Vector2(419+side,bottom),Color("a28352"),3)
	for y in range(780,bottom,14):
		draw_line(Vector2(408,y),Vector2(432,y),Color("c3a067"),3)
		draw_line(Vector2(409,y+2),Vector2(431,y+2),Color("695a3e"),1)
