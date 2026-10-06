extends SceneTree
## Physical excavation, surface access, material conservation and bounded ownership.

class TestWorker extends CharacterBody2D:
	var inventory: Dictionary = {}
	var focus
	var intent := 0.0
	func _ready() -> void:
		collision_layer = 8
		collision_mask = 1
		add_to_group("players")
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(18,42)
		shape.shape = box
		shape.position = Vector2(0,-21)
		add_child(shape)
	func _physics_process(delta: float) -> void:
		velocity = Vector2(intent*150,velocity.y+1100*delta)
		move_and_slide()
	func add_item(kind: String,amount: int) -> int:
		var held := 0
		for count in inventory.values(): held += int(count)
		var accepted := mini(amount,maxi(0,2-held))
		inventory[kind] = int(inventory.get(kind,0))+accepted
		return accepted

class TestGame extends Node2D:
	var drops: Dictionary = {}
	var effects: Array[Vector2] = []
	func fx(point: Vector2,_color: Color,_amount: int) -> void: effects.append(point)
	func sound(_kind: String) -> void: pass
	func spawn_pickup(kind: String,amount: int,_position: Vector2) -> void:
		drops[kind] = int(drops.get(kind,0))+amount

var failed := 0
var checks := 0
var clears := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool,label: String) -> void:
	checks += 1
	if value: print("PASS ",label)
	else:
		failed += 1
		push_error(label)

func run() -> void:
	var game := TestGame.new()
	root.add_child(game)
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	var floor_shape := CollisionShape2D.new()
	var floor_box := RectangleShape2D.new()
	floor_box.size = Vector2(600,16)
	floor_shape.shape = floor_box
	floor_shape.position = Vector2(300,296)
	floor_body.add_child(floor_shape)
	game.add_child(floor_body)
	var field = load("res://scripts/diggable_terrain.gd").new()
	field.setup(game,Rect2(192,144,192,144),{Vector2i(0,2):{"kind":"ore","yield":3},Vector2i(2,1):"limestone",Vector2i(3,0):{"kind":"tungsten","yield":2}})
	field.cleared.connect(func(): clears+=1)
	game.add_child(field)
	var worker := TestWorker.new()
	worker.position = Vector2(166,288)
	game.add_child(worker)
	for frame in 4: await physics_frame
	check(field.remaining_count()==12 and field.blocks.size()==12,"192×144 field creates exactly12 real48px cells")
	check(field.cell_at(Vector2i(0,0)).global_position==Vector2(216,168) and field.cell_at(Vector2i(3,2)).global_position==Vector2(360,264),"Cell centers exactly fill the bounded world rectangle")
	check(field.blocks.all(func(block):return block.collision_layer==1 and not block.collider.disabled),"Every earth cell owns real solid geometry")
	check(field.cell_at(Vector2i(1,1)).exposed_sides.values().all(func(side):return not side),"Buried center cell has no decorative box border")
	var first: MineBlock = field.cell_at(Vector2i(0,2))
	var behind: MineBlock = field.cell_at(Vector2i(1,2))
	check(first.exposed_sides[Vector2i.LEFT] and not first.exposed_sides[Vector2i.RIGHT] and not first.exposed_sides[Vector2i.DOWN],"Only exposed cave face is edged; neighboring rock and floor remain joined")
	check(first.can_interact(worker) and not behind.can_interact(worker),"An intact front cell blocks interaction with buried cells")
	worker.focus = first
	check(first.is_selected() and not behind.is_selected(),"Mining overlay belongs only to the selected cell")
	first.interact(worker,0.60)
	first.mining_strike(worker)
	check(is_equal_approx(first.mining,0.60) and not first.depleted,"Resource vein uses fixed sustained mining progress")
	check(first.mining_duration()==Balance.MINE_TIME and behind.mining_duration()==Balance.SOIL_DIG_TIME,"Ordinary room soil takes0.5s; valuable veins retain their longer work time")
	check(not game.effects.is_empty() and is_equal_approx(game.effects[0].x,192.0),"Contact particles originate at the struck earth surface")
	behind.interact(worker,10.0)
	check(behind.mining==0 and field.remaining_count()==12,"Held interaction cannot mine through the front obstacle")
	worker.focus = behind
	check(not first.is_selected(),"Old cracks/progress disappear when another target is selected")
	worker.focus = first
	first.interact(worker,0.66)
	first.interact(worker,10.0)
	check(field.remaining_count()==11 and field.blocks.size()==11 and clears==0,"One completed dig removes exactly one owned cell without clearing the room")
	check(worker.inventory.get("ore",0)==2 and game.drops.get("ore",0)==1,"A full pack preserves all overflow ore as a pickup")
	for frame in 3: await physics_frame
	check(behind.can_interact(worker) and behind.exposed_sides[Vector2i.LEFT],"Excavation exposes the next real rock face and opens its interaction")
	worker.intent = 1
	for frame in 40: await physics_frame
	worker.intent = 0
	check(worker.position.x>215 and worker.position.x<233,"Character physically enters the excavated void and stops at the next solid cell")
	for col in range(1,4):
		var block: MineBlock = field.cell_at(Vector2i(col,2))
		worker.focus = block
		block.interact(worker,Balance.SOIL_DIG_TIME+0.01)
		for frame in 2: await physics_frame
		worker.intent = 1
		for frame in 22: await physics_frame
		worker.intent = 0
	check(field.remaining_count()==8 and worker.position.x>365,"Successive real removals form a continuous walkable horizontal tunnel")
	for col in range(4):
		worker.position = Vector2(216+col*48,288)
		worker.velocity = Vector2.ZERO
		for frame in 2: await physics_frame
		for row in [1,0]:
			var block: MineBlock = field.cell_at(Vector2i(col,row))
			worker.focus = block
			check(block.can_interact(worker),"Cleared passage exposes row%d column%d within surface reach" % [row,col])
			block.interact(worker,block.mining_duration()+0.01)
			for frame in 2: await physics_frame
	check(field.is_cleared() and field.remaining_count()==0 and field.blocks.is_empty() and field.cells.is_empty(),"All field references are removed once its real earth is excavated")
	check(clears==1,"The cleared signal fires exactly once on the final dig")
	var total := 0
	for amount in worker.inventory.values(): total += int(amount)
	for amount in game.drops.values(): total += int(amount)
	check(total==15 and game.drops.get("sand",0)==9 and game.drops.get("limestone",0)==1 and game.drops.get("tungsten",0)==2,"All15 configured resource units survive excavation and limited carrying capacity")
	for frame in 30: await physics_frame
	check(field.remaining_count()==0 and clears==1 and get_nodes_in_group("mine_blocks").is_empty(),"Cleared earth never automatically respawns")
	check(is_instance_valid(floor_body) and worker.is_on_floor(),"Permanent foundation remains physically intact after field clearing")
	print("DIGGING CHECKS: %d passed, %d failed" % [checks-failed,failed])
	game.queue_free()
	await process_frame
	quit(0 if failed==0 else 1)
