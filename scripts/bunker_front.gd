extends Node2D
## Connected cutaway defense gallery. Its roof is solid; wall panels stay separate.
var game
var elapsed := 0.0

func _ready() -> void:
	z_index = -6
	game.add_terrain(Rect2(638,326,231,12))
	var shell := StaticBody2D.new()
	shell.collision_layer = 1
	var slab := CollisionPolygon2D.new()
	slab.polygon = PackedVector2Array([Vector2(747,260),Vector2(775,279),Vector2(873,324),Vector2(849,324),Vector2(747,279)])
	shell.add_child(slab)
	add_child(shell)

func _process(delta: float) -> void:
	elapsed += delta
	queue_redraw()

func _draw() -> void:
	var shift: Vector2 = game.scenery.offset*0.52
	# Recessed service corridor ties the three upgradeable panels into the bunker.
	draw_set_transform(-shift)
	draw_texture_rect(preload("res://assets/bunker_wall.png"),Rect2(636,333,239,96),false,Color("777d70"))
	draw_rect(Rect2(638,338,229,12),Color(0,0,0,0.4))
	for x in [686,779]:
		draw_rect(Rect2(x,344,17,82),Color("3e4540"))
		draw_rect(Rect2(x+2,345,3,76),Color("758171"))
	draw_line(Vector2(641,354),Vector2(861,354),Color("968456"),3)
	draw_line(Vector2(641,358),Vector2(861,358),Color("1f2828"),3)
	draw_set_transform(Vector2.ZERO)
	for rect in [Rect2(632,324,242,14),Rect2(635,423,238,7)]:
		draw_rect(rect,Art.INK)
		draw_rect(rect.grow(-2),Color("697164"))
		draw_line(rect.position+Vector2(2,2),rect.position+Vector2(rect.size.x-2,2),Color("a7a78d"),2)
	for x in range(640,866,19):
		draw_line(Vector2(x,327),Vector2(x+7,333),Color("b8a36a"),2)
	# The overhang joins the upper shell instead of floating in front of it.
	draw_colored_polygon(PackedVector2Array([Vector2(747,260),Vector2(775,279),Vector2(873,324),Vector2(849,324),Vector2(747,279)]),Color("4d5650"))
	draw_polyline(PackedVector2Array([Vector2(747,260),Vector2(775,279),Vector2(873,324)]),Color("969982"),3)
	for x in [711,801]:
		draw_rect(Rect2(x,349,7,10),Color("ffce78"))
		draw_circle(Vector2(x+3,353),18,Color(1,0.65,0.29,0.035))
	Art.text(self,Vector2(655,317),LocaleText.text("VERTEIDIGUNG / OST"),10,Color("c1b58f"))
