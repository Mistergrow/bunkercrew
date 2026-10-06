class_name DiggableTerrain
extends Node2D
## A bounded excavation field containing real, individually removable solid cells.
## setup(game, world_bounds, {Vector2i(col,row): kind or {kind,yield}}) precedes add_child.

signal cleared

const CELL := 48
const BLOCK_SCENE = preload("res://scenes/mine_block.tscn")
var game
var bounds := Rect2()
var resource_map: Dictionary = {}
var blocks: Array[MineBlock] = []
var cells: Dictionary = {}
var _spawned := false
var _cleared_emitted := false

func setup(owner_game: Node,world_bounds: Rect2,kind_map: Dictionary = {}) -> void:
	assert(not is_inside_tree(),"Configure a digging field before adding it to the tree")
	assert(world_bounds.size.x >= 0 and world_bounds.size.y >= 0,"Excavation bounds must have a positive size")
	assert(is_equal_approx(fmod(world_bounds.size.x,CELL),0) and is_equal_approx(fmod(world_bounds.size.y,CELL),0),"Excavation dimensions must use complete 48px cells")
	game = owner_game
	bounds = world_bounds
	resource_map = kind_map.duplicate(true)

func _ready() -> void:
	if _spawned:
		return
	_spawned = true
	global_position = Vector2.ZERO
	add_to_group("diggable_terrain")
	for row in int(bounds.size.y/CELL):
		for col in int(bounds.size.x/CELL):
			var cell := Vector2i(col,row)
			var value = resource_map.get(cell,"sand")
			var block: MineBlock = BLOCK_SCENE.instantiate()
			block.kind = str(value.get("kind","sand")) if value is Dictionary else str(value)
			block.yield_amount = maxi(0,int(value.get("yield",value.get("yield_amount",1)))) if value is Dictionary else 1
			block.game = game
			block.terrain_owner = self
			block.grid_cell = cell
			block.position = bounds.position+Vector2(cell)*CELL+Vector2.ONE*(CELL*0.5)
			block.name = "Earth_%d_%d" % [col,row]
			block.mined.connect(_on_mined)
			block.tree_exiting.connect(_on_cell_exiting.bind(block,cell))
			blocks.append(block)
			cells[cell] = block
			add_child(block)
	if blocks.is_empty():
		_emit_cleared.call_deferred()

func cell_at(cell: Vector2i) -> MineBlock:
	var block = cells.get(cell)
	return block if is_instance_valid(block) and not block.depleted and not block.is_queued_for_deletion() else null

func remaining_count() -> int:
	var count := 0
	for block in blocks:
		if is_instance_valid(block) and not block.depleted and not block.is_queued_for_deletion():
			count += 1
	return count

func is_cleared() -> bool:
	return remaining_count() == 0

func _on_mined(block: MineBlock) -> void:
	cells.erase(block.grid_cell)
	blocks.erase(block)
	if is_cleared():
		_emit_cleared()

func _on_cell_exiting(block: MineBlock,cell: Vector2i) -> void:
	# Teardown cleans references but never awards material or starts room construction.
	blocks.erase(block)
	if cells.get(cell) == block:
		cells.erase(cell)

func _emit_cleared() -> void:
	if not _cleared_emitted and is_inside_tree() and not is_queued_for_deletion():
		_cleared_emitted = true
		cleared.emit()
