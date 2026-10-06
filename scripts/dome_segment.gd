class_name DomeSegment
extends StaticBody2D
## Every pane owns its damage and real collision. Only the ground-level front
## belongs to enemy path targets; all glazed panes block projectiles on layer 2.

const DefenseArt := preload("res://scripts/defense_structure_art.gd")

enum Stage { PLAN, FRAME, GLASS, BROKEN }
var game
var controller
var panel_index := 0
var stage := Stage.PLAN
var front_line := false
var start := Vector2.ZERO
var finish := Vector2.ZERO
var thickness := 9.0
var max_hp := 140.0
var hp := 0.0
var flash := 0.0
var polygon := PackedVector2Array()
var polygons: Array[PackedVector2Array] = []
var sections: Array = []
var curve := PackedVector2Array()
var curve_normals := PackedVector2Array()
var outer_edge := PackedVector2Array()
var inner_edge := PackedVector2Array()
var collider: CollisionPolygon2D
var colliders: Array[CollisionPolygon2D] = []
var service_port := false
var uncut_polygon := PackedVector2Array()

func configure(from: Vector2, to: Vector2, index: int, ground_front: bool = false) -> void:
	position = to
	start = from - to
	finish = Vector2.ZERO
	panel_index = index
	front_line = ground_front
	if front_line:
		max_hp = 1200.0
		thickness = 7.0
		# Existing enemies aim 40px above an obstacle's origin. Place that target
		# on the lower physical pane at y410, clear of the firing window at310..404.
		position.y += 20.0
		start.y -= 20.0
		finish.y -= 20.0

func configure_curve(points: PackedVector2Array, normals: PackedVector2Array, index: int) -> void:
	configure(points[0], points[-1], index)
	thickness = 7.0
	for point in points:
		curve.append(point - position)
	curve_normals = normals

func _ready() -> void:
	add_to_group("dome_segments")
	collision_layer = 2
	collision_mask = 0
	if front_line:
		var axis := (finish - start).normalized()
		sections = [[start, start + axis * 65], [start + axis * 159, finish]]
	elif not curve.is_empty():
		var strip := PackedVector2Array()
		for index in curve.size():
			outer_edge.append(curve[index] + curve_normals[index] * thickness)
			inner_edge.append(curve[index] - curve_normals[index] * thickness)
		strip.append_array(outer_edge)
		var return_edge := inner_edge.duplicate()
		return_edge.reverse()
		strip.append_array(return_edge)
		assert(not Geometry2D.triangulate_polygon(strip).is_empty(), "Dome curved strip must form a simple triangulable polygon")
		uncut_polygon = strip
		polygons = _roof_polygons()
	else:
		sections = [[start, finish]]
	for section in sections:
		polygons.append(_section_polygon(section[0], section[1]))
	for shape in polygons:
		var part := CollisionPolygon2D.new()
		part.name = "GlassCollision%d" % colliders.size()
		part.polygon = shape
		part.disabled = true
		add_child(part)
		colliders.append(part)
	collider = colliders[0] if not colliders.is_empty() else null
	polygon = polygons[0] if not polygons.is_empty() else PackedVector2Array()
	queue_redraw()

func _roof_polygons() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if service_port and is_instance_valid(controller):
		var left: float = controller.flak_port_left-global_position.x
		var right: float = controller.flak_port_right-global_position.x
		var cut := PackedVector2Array([Vector2(left,-1000),Vector2(right,-1000),Vector2(right,1000),Vector2(left,1000)])
		for piece: PackedVector2Array in Geometry2D.clip_polygons(uncut_polygon,cut):
			result.append(piece)
	else:
		result.append(uncut_polygon)
	return result

func update_service_port(active: bool) -> void:
	if curve.is_empty() or active == service_port:
		return
	service_port = active
	polygons = _roof_polygons()
	for part in colliders:
		remove_child(part)
		part.queue_free()
	colliders.clear()
	for shape in polygons:
		var part := CollisionPolygon2D.new()
		part.polygon = shape
		part.disabled = not is_blocking()
		add_child(part)
		colliders.append(part)
	collider = colliders[0] if not colliders.is_empty() else null
	polygon = polygons[0] if not polygons.is_empty() else PackedVector2Array()
	queue_redraw()

func _section_polygon(from: Vector2, to: Vector2) -> PackedVector2Array:
	var normal := (to - from).normalized().orthogonal() * thickness
	return PackedVector2Array([from + normal, to + normal, to - normal, from - normal])

func set_frame() -> void:
	if stage != Stage.PLAN:
		return
	stage = Stage.FRAME
	queue_redraw()

func glaze() -> void:
	if stage != Stage.FRAME:
		return
	stage = Stage.GLASS
	hp = max_hp
	_update_collision()
	queue_redraw()

func is_blocking() -> bool:
	return stage == Stage.GLASS and hp > 0.0

func interaction_point() -> Vector2:
	return global_position + Vector2(0, -40) if front_line else to_global((start + finish) * 0.5)

func needs_repair() -> bool:
	return stage in [Stage.GLASS, Stage.BROKEN] and hp < max_hp - 0.001

func repair(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or not needs_repair():
		return
	hp = minf(max_hp, hp + amount)
	stage = Stage.GLASS
	flash = 0.22
	_update_collision()
	queue_redraw()

func take_damage(amount: float) -> void:
	if not is_finite(amount) or amount <= 0.0 or not is_blocking():
		return
	hp = maxf(0.0, hp - amount)
	flash = 0.16
	var center := to_global((start + finish) * 0.5)
	if get_meta("impact_contact_frame", -1) != Engine.get_physics_frames():
		ImpactBurst.emit(game, center, "glass", Vector2.RIGHT, 0.7)
	if hp <= 0.0:
		stage = Stage.BROKEN
		_update_collision()
		if is_instance_valid(game):
			ImpactBurst.emit(game, center, "glass", Vector2.DOWN, 1.8)
			preload("res://scripts/spatial_sound.gd").emit(game,"glass_break",global_position)
	queue_redraw()
	if is_instance_valid(controller):
		controller.queue_redraw()

func _update_collision() -> void:
	for part in colliders:
		part.set_deferred("disabled", not is_blocking())
	if front_line:
		if is_blocking():
			add_to_group("walls")
		else:
			remove_from_group("walls")

func _process(delta: float) -> void:
	if flash > 0.0:
		flash = maxf(0.0, flash - delta)
		queue_redraw()

func _draw() -> void:
	if not curve.is_empty():
		_draw_curve()
	for index in sections.size():
		_draw_section(sections[index][0], sections[index][1], polygons[index])
	if front_line and stage == Stage.GLASS and hp < max_hp:
		Art.bar(self, Rect2(-24, -123, 48, 4), hp / max_hp, Art.AMBER)

func _draw_curve() -> void:
	if stage!=Stage.PLAN:
		_draw_rear_glazing()
	if service_port and curve[0].x+global_position.x < controller.flak_port_right and curve[-1].x+global_position.x > controller.flak_port_left:
		_draw_port_pieces()
		return
	if stage == Stage.PLAN:
		for edge in range(0, curve.size() - 1, 2):
			draw_line(curve[edge], curve[edge + 1], Color(0.47, 0.55, 0.51, 0.25), 2)
		return
	if stage == Stage.GLASS:
		DefenseArt.glass(self,polygon,flash)
		# Uneven, short glints leave the textured metal more prominent than the
		# pane reflections. They stay fixed to each individual panel.
		var index := 2+panel_index%3
		var tangent := (curve[index + 1] - curve[index - 1]).normalized()
		draw_line(curve[index]-tangent*4,curve[index]+tangent*2+curve_normals[index]*2,Color(.73,.83,.77,.29),1)
		if hp < max_hp * 0.75:
			var midpoint: Vector2 = curve[floori(curve.size() / 2.0)]
			draw_polyline(PackedVector2Array([midpoint - Vector2(8, 5), midpoint + Vector2(1, 1), midpoint + Vector2(-2, 4), midpoint + Vector2(9, 6)]), Color("9caeaa"), 1)
	elif stage == Stage.BROKEN:
		for index in [0, curve.size() - 1]:
			var inward := (curve[1] - curve[0]).normalized() if index == 0 else (curve[-2] - curve[-1]).normalized()
			draw_colored_polygon(PackedVector2Array([curve[index] + curve_normals[index] * thickness, curve[index] - curve_normals[index] * thickness, curve[index] + inward * 12]), Color(0.43, 0.57, 0.56, 0.35))
	for edge: PackedVector2Array in [outer_edge,inner_edge]:
		DefenseArt.rail(self,edge,3.0,panel_index,stage==Stage.BROKEN)
	for index in [0, curve.size() - 1]:
		var normal: Vector2 = curve_normals[index]
		DefenseArt.beam(self,curve[index]-normal*10,curve[index]+normal*10,5,panel_index,stage==Stage.BROKEN)
		for side in [-1,1]: DefenseArt.bolt(self,curve[index]+normal*7*side)

func _rear_curve() -> PackedVector2Array:
	var result := PackedVector2Array()
	for index in curve.size():
		# A shallow perspective return gives the glazed roof depth. The offset
		# tapers to zero at both springing points rather than crossing the floor.
		result.append(curve[index]+Vector2(0,22*absf(curve_normals[index].y)))
	return result

func _clip_visual_shape(shape: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not service_port or not is_instance_valid(controller):
		result.append(shape)
		return result
	var left: float=controller.flak_port_left-global_position.x
	var right: float=controller.flak_port_right-global_position.x
	var aperture := PackedVector2Array([Vector2(left,-1000),Vector2(right,-1000),Vector2(right,1000),Vector2(left,1000)])
	for piece: PackedVector2Array in Geometry2D.clip_polygons(shape,aperture): result.append(piece)
	return result

func _rear_paths(path: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not service_port or not is_instance_valid(controller):
		result.append(path)
		return result
	var left: float=controller.flak_port_left-global_position.x
	var right: float=controller.flak_port_right-global_position.x
	# Monotonic roof arcs can have one visible path on each aperture side.
	for side in [-1,1]:
		var boundary: float=left if side<0 else right
		var piece := PackedVector2Array()
		for index in path.size()-1:
			var a := path[index]
			var b := path[index+1]
			var a_visible: bool=a.x<=boundary if side<0 else a.x>=boundary
			var b_visible: bool=b.x<=boundary if side<0 else b.x>=boundary
			if a_visible and (piece.is_empty() or piece[-1]!=a): piece.append(a)
			if a_visible!=b_visible:
				piece.append(a.lerp(b,(boundary-a.x)/(b.x-a.x)))
			if b_visible and (piece.is_empty() or piece[-1]!=b): piece.append(b)
		if piece.size()>1: result.append(piece)
	return result

func _draw_rear_glazing() -> void:
	var rear := _rear_curve()
	if stage==Stage.GLASS:
		var shape := curve.duplicate()
		var return_edge := rear.duplicate()
		return_edge.reverse()
		shape.append_array(return_edge)
		for piece: PackedVector2Array in _clip_visual_shape(shape):
			DefenseArt.glass(self,piece,flash,true)
	for path: PackedVector2Array in _rear_paths(rear):
		DefenseArt.rail(self,path,2.0,panel_index+2,stage==Stage.BROKEN)
	for index in [0,curve.size()-1]:
		var world_x: float=curve[index].x+global_position.x
		if service_port and world_x>controller.flak_port_left and world_x<controller.flak_port_right: continue
		DefenseArt.beam(self,curve[index],rear[index],3,panel_index,stage==Stage.BROKEN)

func _draw_port_pieces() -> void:
	# Main pane borders and the perspective return both respect the physical
	# opening. No decorative sheet bridges the gun's genuine firing aperture.
	for shape: PackedVector2Array in polygons:
		if stage == Stage.GLASS:
			DefenseArt.glass(self,shape,flash)
		var border := shape.duplicate()
		border.append(shape[0])
		if stage == Stage.PLAN:
			draw_polyline(border,Color(0.47,0.55,0.51,0.25),1)
		else:
			DefenseArt.rail(self,border,3.0,panel_index,stage==Stage.BROKEN)

func _draw_section(from: Vector2, to: Vector2, shape: PackedVector2Array) -> void:
	var axis := (to - from).normalized()
	var normal := axis.orthogonal()
	if stage == Stage.PLAN:
		for fraction in [0.0, 0.4, 0.8]:
			var p: Vector2 = from.lerp(to, fraction)
			draw_line(p, p + axis * minf(10, from.distance_to(to) * 0.15), Color(0.47, 0.55, 0.51, 0.25), 2)
		return
	if stage == Stage.GLASS:
		DefenseArt.glass(self,shape,flash)
		var glint: Vector2=from.lerp(to,.27)
		draw_line(glint-axis*4-normal*2,glint+axis*2+normal*2,Color(.73,.83,.77,.29),1)
		if hp < max_hp * 0.75:
			var midpoint := from.lerp(to, 0.52)
			draw_polyline(PackedVector2Array([midpoint - normal * thickness, midpoint - axis * 6, midpoint + normal * 3, midpoint + axis * 7 + normal * thickness]), Color("a0b0aa"), 1)
	elif stage == Stage.BROKEN:
		for end in [from, to]:
			var inward := axis if end == from else -axis
			draw_colored_polygon(PackedVector2Array([end + normal * thickness, end - normal * thickness, end + inward * 12 + normal * 2]), Color(0.43, 0.57, 0.56, 0.35))
	for side in [-1.0, 1.0]:
		var offset: Vector2 = normal * thickness * side
		DefenseArt.beam(self,from+offset,to+offset,3,panel_index,stage==Stage.BROKEN)
	for fraction in [0.0, 0.5, 1.0]:
		var p: Vector2 = from.lerp(to, fraction)
		DefenseArt.beam(self,p-normal*(thickness+3),p+normal*(thickness+3),5,panel_index,stage==Stage.BROKEN)
		for side in [-1.0, 1.0]: DefenseArt.bolt(self,p+normal*thickness*side)
