extends "res://scripts/scenario_scenery.gd"
## The classic bunker shares Sector 07's complete backdrop.
var clock := 0.0
var lighting: Node2D
var legacy_layers: Array[Node2D] = []

func _ready() -> void:
	environment_id = "sector07"
	super()
	props_layer.hide()
	props_layer.set_process(false)
	# The shared panorama supplies the backdrop; classic rooms and their
	# finite outdoor terrain still need their original, world-fixed backing.
	for index in range(1,5):
		var drawing_layer := preload("res://scripts/scenery_layer.gd").new()
		drawing_layer.name="ClassicDrawing%d"%index
		drawing_layer.layer=index
		drawing_layer.z_index=index
		legacy_layers.append(drawing_layer)
		add_child(drawing_layer)
	var localization := get_node_or_null("/root/Localization")
	if is_instance_valid(localization): localization.locale_changed.connect(_redraw_legacy_labels)
	lighting = Node2D.new()
	lighting.z_index=6
	lighting.draw.connect(_draw_lighting)
	add_child(lighting)

func _redraw_legacy_labels(_locale: String) -> void:
	for drawing_layer: Node2D in legacy_layers: drawing_layer.queue_redraw()

func _process(delta: float) -> void:
	super(delta)
	clock += delta
	lighting.queue_redraw()

func _draw_lighting() -> void:
	# Local pools of warm light; work surfaces stay readable without obscuring actors.
	for p in [Vector2(154,281), Vector2(433,281), Vector2(700,281), Vector2(144,461), Vector2(455,461), Vector2(710,461), Vector2(280,656), Vector2(675,658), Vector2(1113,658)]:
		var flicker = 0.96 + sin(clock * 2.2 + p.x) * 0.04
		for r in range(7, 0, -1):
			lighting.draw_circle(p + Vector2(0,21), 16.0 * r, Color(0.95,0.60,0.24,0.010 * flicker))
		lighting.draw_colored_polygon(PackedVector2Array([p+Vector2(-3,9),p+Vector2(3,9),p+Vector2(48,114),p+Vector2(-48,114)]),Color(0.95,0.65,0.30,0.027))
		lighting.draw_line(p - Vector2(0,12), p, Color("222725"), 3)
		lighting.draw_rect(Rect2(p - Vector2(5,0), Vector2(10,14)), Color("564433"))
		lighting.draw_rect(Rect2(p - Vector2(3,-2), Vector2(6,9)), Color("ffd18a"))
		lighting.draw_circle(p + Vector2(0,5), 2, Color("fff0c0"))
	if game.started and game.rounds and game.rounds.phase in ["warning", "attack"]:
		var bright = 0.5 + sin(clock * 7) * 0.5
		for p in [Vector2(777,297), Vector2(108,290)]:
			lighting.draw_circle(p, 24, Color(1,0.16,0.06,0.065 * bright))
			lighting.draw_rect(Rect2(p-Vector2(6,5), Vector2(12,10)), Color(0.65 + bright * 0.35,0.15,0.09))
