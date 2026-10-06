extends RefCounted
## Native focus stays on the current panel as actions appear or become disabled.

static func available(panel: Control, candidates: Array[Control]) -> Array[Control]:
	var controls: Array[Control] = []
	for control: Control in candidates:
		if not is_instance_valid(control) or not panel.is_ancestor_of(control) or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE: continue
		if control is BaseButton and control.disabled: continue
		controls.append(control)
	return controls

static func signature(controls: Array[Control]) -> String:
	return str(controls.map(func(control): return [control.get_instance_id(), control.get_global_rect()]))

static func wire(controls: Array[Control]) -> void:
	for index in controls.size():
		var control := controls[index]
		control.focus_next = control.get_path_to(controls[(index + 1) % controls.size()])
		control.focus_previous = control.get_path_to(controls[posmod(index - 1, controls.size())])
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			var property: String = "focus_neighbor_" + str({Vector2.UP:"top", Vector2.DOWN:"bottom", Vector2.LEFT:"left", Vector2.RIGHT:"right"}[direction])
			control.set(property, control.get_path_to(_nearest(control, controls, direction)))

static func _nearest(origin: Control, controls: Array[Control], direction: Vector2) -> Control:
	var nearest := origin
	var score := INF
	var center := origin.get_global_rect().get_center()
	for candidate: Control in controls:
		if candidate == origin: continue
		var difference := candidate.get_global_rect().get_center() - center
		var advance := difference.dot(direction)
		if advance <= 1: continue
		var candidate_score := advance + absf(difference.cross(direction)) * 2.0
		if candidate_score < score:
			nearest = candidate
			score = candidate_score
	return nearest
