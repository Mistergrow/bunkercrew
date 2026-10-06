class_name MineBlock
extends StaticBody2D
## One solid cell of continuous geology. Adjacent cells share texture coordinates;
## only open tunnel faces receive edge shading, never a border around every cell.

signal mined(block: MineBlock)

@export var kind: String = "sand"
@export var yield_amount: int = Balance.MINE_YIELD
var game
var terrain_owner: Node
var grid_cell := Vector2i.ZERO
var mining: float = 0.0
var last_work: float = -100.0
var elapsed: float = 0.0
var depleted := false
var exposed_sides: Dictionary = {}
var contact_point := Vector2.ZERO
var last_worker: Node2D
var selected_last_frame := false
var _drawn_work_step := -1
var collider: CollisionShape2D
const CELL_SIZE := 48.0
const HALF := 24.0
const TEXTURE_PERIOD := 480.0
const ROCK = preload("res://assets/rock.png")
const MineralDeposits = preload("res://scripts/mineral_deposits.gd")
const DIRECTIONS: Array[Vector2i] = [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]
var _mineral_facets: Array[Dictionary] = []
var _mineral_origin := Vector2(INF,INF)
var _mineral_kind := ""

func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_to_group("interactables")
	add_to_group("mine_blocks")
	collider = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(CELL_SIZE,CELL_SIZE)
	collider.shape = shape
	add_child(collider)
	contact_point = global_position+Vector2(-HALF,0)
	refresh_neighbors.call_deferred()
	get_tree().physics_frame.connect(refresh_neighbors,CONNECT_ONE_SHOT)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	var selected := is_selected()
	var work_step := floori(clampf(mining/mining_duration(),0,1)*24.0)
	if selected != selected_last_frame or work_step != _drawn_work_step or (selected and elapsed-last_work < 0.3):
		queue_redraw()
	_drawn_work_step = work_step
	selected_last_frame = selected

func interaction_point() -> Vector2:
	# The lower reachable surface keeps a three-cell-high seam diggable from below.
	return global_position+Vector2(0,16)

func surface_near(point: Vector2) -> Vector2:
	return Vector2(clampf(point.x,global_position.x-HALF,global_position.x+HALF),clampf(point.y,global_position.y-HALF,global_position.y+HALF))

func can_interact(player) -> bool:
	if depleted or is_queued_for_deletion() or not is_instance_valid(player):
		return false
	var start: Vector2 = player.global_position+Vector2(0,-22)
	if start.distance_to(surface_near(start)) > 88.0:
		return false
	var query := PhysicsRayQueryParameters2D.create(start,global_position,1)
	query.hit_from_inside = true
	if player is CollisionObject2D:
		query.exclude = [player.get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == self

func prompt(_player) -> String:
	var label: String = Balance.RESOURCE_NAMES.get(kind,kind)
	return LocaleText.format("ERDREICH · freigraben · halten · %s ×%d", [label,yield_amount]) if kind == "sand" else LocaleText.format("%sADER · freigraben · halten · Ertrag %d", [label.to_upper(),yield_amount])

func interaction_progress(_player) -> float:
	return clampf(mining/mining_duration(),0,1)

func mining_duration() -> float:
	return Balance.SOIL_DIG_TIME if kind == "sand" and yield_amount == 1 else Balance.MINE_TIME

func is_selected() -> bool:
	if not is_inside_tree() or depleted:
		return false
	for player in get_tree().get_nodes_in_group("players"):
		if "focus" in player and player.focus == self:
			return true
	return is_instance_valid(last_worker) and not "focus" in last_worker and elapsed-last_work < 0.3

func interact(player,delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not can_interact(player):
		return
	last_worker = player
	mining += delta
	last_work = elapsed
	contact_point = _contact_from(player.global_position+Vector2(0,-22))
	if mining >= mining_duration():
		depleted = true
		collision_layer = 0
		collider.set_deferred("disabled",true)
		remove_from_group("interactables")
		remove_from_group("mine_blocks")
		var added: int = player.add_item(kind,yield_amount)
		if is_instance_valid(game):
			var events=game.get("combat_events")
			if is_instance_valid(events) and events.has_method("record_mined"): events.record_mined(yield_amount,player)
			if added < yield_amount:
				game.spawn_pickup(kind,yield_amount-added,global_position+Vector2(0,20))
			if game.has_method("impact"):
				game.impact(contact_point,mining_material(),(player.global_position+Vector2(0,-22)-contact_point).normalized(),0.8)
			else:
				game.fx(contact_point,Color("9c8967"),12)
				game.fx(global_position,Balance.RESOURCE_COLORS.get(kind,Art.AMBER),7)
			preload("res://scripts/spatial_sound.gd").emit(game,"impact_stone",contact_point)
		mined.emit(self)
		_refresh_nearby()
		queue_free()
	queue_redraw()

func mining_strike(player: Node2D) -> void:
	# Animation owns contact timing; work accumulation and depletion stay in
	# interact(). Each worker presents their own strike when sharing a rock face.
	if not can_interact(player) or not is_instance_valid(game):
		return
	contact_point = _contact_from(player.global_position+Vector2(0,-22))
	if game.has_method("impact"):
		game.impact(contact_point,mining_material(),(player.global_position+Vector2(0,-22)-contact_point).normalized(),0.25)
	else:
		game.fx(contact_point,Balance.RESOURCE_COLORS.get(kind,Art.AMBER),4)
	preload("res://scripts/spatial_sound.gd").emit(game,"mine",contact_point)
	queue_redraw()

func mining_material() -> String:
	return "mining_" + kind if kind in ["ore","limestone","tungsten"] else "mining_sand"

func _contact_from(start: Vector2) -> Vector2:
	var query := PhysicsRayQueryParameters2D.create(start,global_position,1)
	query.hit_from_inside = true
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.position if not hit.is_empty() and hit.get("collider") == self else surface_near(start)

func refresh_neighbors() -> void:
	if not is_inside_tree() or depleted:
		return
	exposed_sides.clear()
	var space := get_world_2d().direct_space_state
	for direction in DIRECTIONS:
		var filled := false
		if is_instance_valid(terrain_owner) and terrain_owner.has_method("cell_at"):
			filled = terrain_owner.cell_at(grid_cell+direction) != null
		if not filled:
			var neighbor_center := global_position+Vector2(direction)*CELL_SIZE
			for other in get_tree().get_nodes_in_group("mine_blocks"):
				if other != self and not other.depleted and other.global_position.distance_squared_to(neighbor_center)<1.0:
					filled = true
					break
		if not filled:
			var query := PhysicsPointQueryParameters2D.new()
			query.position = global_position+Vector2(direction)*(HALF+1.0)
			query.collision_mask = 1
			query.exclude = [get_rid()]
			filled = not space.intersect_point(query,1).is_empty()
		exposed_sides[direction] = not filled
	queue_redraw()

func _refresh_nearby() -> void:
	for other in get_tree().get_nodes_in_group("mine_blocks"):
		if other != self and other.global_position.distance_squared_to(global_position)<CELL_SIZE*CELL_SIZE*1.1:
			other.refresh_neighbors.call_deferred()

func _draw() -> void:
	if depleted:
		return
	_draw_continuous_rock()
	_draw_minerals()
	for direction in DIRECTIONS:
		if exposed_sides.get(direction,false):
			_draw_open_face(direction)
	if mining > 0:
		_draw_work_cracks()

func _draw_continuous_rock() -> void:
	# Split only at the large texture repeat, keeping every 48px grid seam invisible.
	var world_start := global_position-Vector2(HALF,HALF)
	var source_scale := ROCK.get_size()/TEXTURE_PERIOD
	var y := 0.0
	while y < CELL_SIZE-0.01:
		var source_y := fposmod(world_start.y+y,TEXTURE_PERIOD)
		var height := minf(CELL_SIZE-y,TEXTURE_PERIOD-source_y)
		var x := 0.0
		while x < CELL_SIZE-0.01:
			var source_x := fposmod(world_start.x+x,TEXTURE_PERIOD)
			var width := minf(CELL_SIZE-x,TEXTURE_PERIOD-source_x)
			var dest := Rect2(Vector2(x-HALF,y-HALF),Vector2(width,height))
			var source := Rect2(Vector2(source_x,source_y)*source_scale,Vector2(width,height)*source_scale)
			draw_texture_rect_region(ROCK,dest,source,Color(0.84,0.83,0.76))
			x += width
		y += height

func _draw_minerals() -> void:
	if _mineral_origin != global_position or _mineral_kind != kind:
		_mineral_origin = global_position
		_mineral_kind = kind
		_mineral_facets = MineralDeposits.facets(kind,Rect2(global_position-Vector2(HALF,HALF),Vector2.ONE*CELL_SIZE))
		for facet in _mineral_facets:
			var local_points := PackedVector2Array()
			var texture_points := PackedVector2Array()
			for point: Vector2 in facet.points:
				local_points.append(point-global_position)
				texture_points.append(point/TEXTURE_PERIOD)
			facet.points = local_points
			facet.uvs = texture_points
			if facet.textured:
				var tint: Color = facet.color
				# Preserve the host rock's painted grain and deep cracks. The
				# mineral changes its material, instead of covering it with a decal.
				facet.color = Color(tint.r*3.1,tint.g*3.1,tint.b*3.1,tint.a)
	for facet in _mineral_facets:
		if facet.textured:
			draw_polygon(facet.points,PackedColorArray([facet.color]),facet.uvs,ROCK)
		else:
			draw_colored_polygon(facet.points,facet.color)

func _draw_open_face(direction: Vector2i) -> void:
	var normal := Vector2(direction)
	var along := normal.orthogonal()
	var outline := PackedVector2Array()
	var rim := PackedVector2Array()
	for index in range(9):
		var edge := normal*HALF+along*(-HALF+index*6)
		var world_point := global_position+edge
		var grain := hash(Vector2i(world_point))
		var notch := 1.0+float(posmod(grain,4))
		rim.append((edge-normal*notch).round())
	outline.append(normal*HALF+along*(-HALF))
	outline.append(normal*HALF+along*HALF)
	for index in range(rim.size()-1,-1,-1):
		outline.append(rim[index])
	draw_colored_polygon(outline,Color(0.025,0.034,0.034,0.74))
	var edge_color := Color("6e6753") if direction in [Vector2i.LEFT,Vector2i.UP] else Color("3c4035")
	# Broken mineral lips belong to the exposed face, not a bright rectangular
	# outline around a grid cell. Stable world noise avoids a sawtooth repeat.
	for index in range(1,rim.size()):
		var world_point := global_position+rim[index]
		if posmod(hash(Vector2i(world_point)),5)<3:
			draw_line(rim[index-1],rim[index],Color(edge_color,.72),1)
	for index in range(1,7,2):
		var chip := normal*(HALF-3)+along*(-HALF+index*6)
		draw_rect(Rect2(chip.round(),Vector2(2,2)),Color("77705a"))

func _draw_work_cracks() -> void:
	preload("res://scripts/mining_surface_art.gd").fractures(self,to_local(contact_point),mining/mining_duration(),kind,grid_cell)
