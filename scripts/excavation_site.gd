extends Node2D
## A fixed supported shaft opens only after its milestone. No player can remove
## the sole access route: completion installs the floor and matching ladder.
var game
var expansion
var depth := 1
var materials: Dictionary = {}
var transfer: Dictionary = {}
var work := 0.0
var completed := false

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("excavation_sites")

func cost() -> Dictionary:
	return {"steel":2} if depth==1 else {"steel":2,"concrete":2}

func complete_materials() -> bool:
	for kind in cost():
		if int(materials.get(kind,0)) < int(cost()[kind]): return false
	return true

func interaction_point() -> Vector2:
	return global_position-Vector2(0,19)

func can_interact(_player) -> bool:
	return not completed

func prompt(_player) -> String:
	if complete_materials():
		return LocaleText.format("SCHACHT · halten: %d m tiefer graben · Leiter wird abgestützt", (depth*12+12))
	var needs: Array[String] = []
	for kind in cost():
		needs.append(LocaleText.format("%s %d/%d", [Balance.RESOURCE_NAMES[kind],materials.get(kind,0),cost()[kind]]))
	return LocaleText.format("SCHACHT ABSTÜTZEN · %s · halten: einbauen", " + ".join(needs))

func interaction_progress(_player) -> float:
	return work/3.0

func interact(player,delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0 or completed: return
	if not complete_materials():
		var id: int = player.get_instance_id()
		transfer[id] = float(transfer.get(id,0.0))+delta
		if transfer[id] >= Balance.TRANSFER_TIME:
			for kind in cost():
				if int(materials.get(kind,0)) < int(cost()[kind]) and player.take_item(kind,1):
					materials[kind] = int(materials.get(kind,0))+1
					transfer[id] = 0.0
					preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
					break
	else:
		work += delta
		if work >= 3.0 and expansion.excavate(depth):
			completed = true
			game.notify(LocaleText.text("SCHACHT OFFEN · S / ↓ absteigen · Räume an den Bauplänen errichten"))
			queue_free()
	queue_redraw()

func mining_strike(_player: Node2D) -> void:
	if completed or not complete_materials() or not is_instance_valid(game):
		return
	game.fx(global_position-Vector2(0,8),Color("8e8669"),3)
	preload("res://scripts/spatial_sound.gd").emit(game,"mine",interaction_point())

func _draw() -> void:
	draw_rect(Rect2(-30,-7,60,10),Color("17201f"))
	for x in [-29,23]:
		draw_rect(Rect2(x,-33,6,37),Color("9b8258"))
		draw_line(Vector2(x,-32),Vector2(x,-2),Color("c9b382"),1)
	for i in 5:
		draw_rect(Rect2(-24+i*10,-4,8,6),Color("706b56"))
	for y in [-29,-18]:
		draw_line(Vector2(-25,y),Vector2(25,y),Color("5b6456"),4)
	for x in [-20,11]:
		draw_line(Vector2(x,-32),Vector2(x+9,-17),Color("b6a36c"),3)
	Art.text(self,Vector2(-45,-44),LocaleText.text("TIEFENSCHACHT"),10,Art.AMBER)
	if work>0:
		Art.bar(self,Rect2(-31,-39,62,4),work/3.0,Art.AMBER)
