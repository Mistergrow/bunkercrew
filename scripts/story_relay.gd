extends Node2D
## A real, reachable work target. Progress and payment belong to the host.
var game
var director: Node
var progress := 0.0
var pulse := 0.0
var _work_clock := 0.0
var _last_work_time := -1000.0
var _last_send_frame := -1

func _ready() -> void:
	add_to_group("interactables")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(delta: float) -> void:
	pulse += delta
	queue_redraw()

func _physics_process(delta: float) -> void:
	# Simulation time freezes with the match; engine frame counters do not.
	_work_clock += delta
	if director.authoritative() and progress>0 and _work_clock-_last_work_time>.14:
		progress=0

func work_uses_real_time() -> bool:
	# Assembly benefits from work skills. Sending is a fixed-duration channel.
	return director.stage==6

func interaction_point() -> Vector2:
	return to_global(Vector2(0,-30))

func can_interact(_player) -> bool:
	return is_instance_valid(director) and director.stage in [2,4,6]

func interaction_progress(_player) -> float:
	return progress

func prompt(player) -> String:
	var stage := int(director.stage)
	var cost := 2 if stage==2 else 1 if stage==4 else 0
	if stage==2: return LocaleText.format("FELDFUNK · 2 Stahl für die Antennenleitung · halten (%d/2)", int(player.inventory.get("steel",0)))
	if stage==4: return LocaleText.format("FELDFUNK · Relais ersetzen: 1 Stahl · halten (%d/1)", int(player.inventory.get("steel",0)))
	if stage==6: return LocaleText.text("FELDFUNK · Notruf senden · fünf Sekunden halten")
	return LocaleText.format("FELDFUNK · %s", LocaleText.text("Notruf wird übertragen") if stage>=7 else LocaleText.text("Empfänger aktiv") if cost==0 else LocaleText.text("Leitung unterbrochen"))

func interact(player,delta: float) -> void:
	if get_tree().paused: return
	if not director.authoritative() or not can_interact(player) or not game.valid_focus(player,self): return
	if not is_finite(delta) or delta<=0: return
	var cost := 2 if director.stage==2 else 1 if director.stage==4 else 0
	if int(player.inventory.get("steel",0))<cost: return
	if work_uses_real_time():
		var frame := Engine.get_physics_frames()
		if frame==_last_send_frame: return
		_last_send_frame=frame
	if _work_clock-_last_work_time>.14: progress=0
	_last_work_time=_work_clock
	progress=minf(1,progress+minf(delta,.2)/(5.0 if director.stage==6 else 2.0))
	if progress<1: return
	if cost>0 and not player.take_item("steel",cost):
		progress=0
		return
	progress=0
	director.complete_relay()
	game.sound_at("build",global_position)

func _draw() -> void:
	var active: bool = is_instance_valid(director) and director.stage in [3,5,7,8]
	var amber := Color("c9a667")
	var body := Color("57695f")
	draw_rect(Rect2(-24,-48,48,46),Color("1e2928"))
	draw_rect(Rect2(-22,-46,44,40),body)
	draw_rect(Rect2(-18,-41,23,17),Color("132926"))
	for index in 5:
		var y := -36+index*2
		draw_line(Vector2(-16,y),Vector2(-5+sin(pulse*2+index)*5,y),Color("8eb9a0") if active else Color("566154"),1)
	for x in [11,17]:
		for row in 4: draw_rect(Rect2(x,-39+row*4,3,2),Color("26362e"))
	draw_rect(Rect2(-17,-18,18,3),amber.darkened(.4))
	draw_circle(Vector2(13,-15),4,Color("1d2927"))
	draw_line(Vector2(13,-15),Vector2(15,-17),amber,1)
	draw_line(Vector2(-14,-48),Vector2(-14,-59),Color("849185"),2)
	draw_line(Vector2(-14,-59),Vector2(-24,-64),Color("9ca395"),1)
	draw_line(Vector2(-14,-59),Vector2(0,-64),Color("9ca395"),1)
	for x in [-22,18]: draw_rect(Rect2(x,-6,5,6),Color("333f38"))
	draw_rect(Rect2(14,-45,3,2),Color("9bbe86") if active else Color("ce7753"))
	if is_instance_valid(director) and director.stage in [2,4,6]:
		draw_line(Vector2(-28,-55),Vector2(28,-55),Color(amber,.65+.25*sin(pulse*2)),2)
