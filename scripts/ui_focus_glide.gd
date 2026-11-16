extends Control
## Travelling focus highlight. When focus moves between two visible controls a
## warm wash with an amber lead edge glides (eased) from the old rectangle to
## the new one and dissolves into the control's own settled focus style. It is drawn on top, takes no input and
## changes no layout; with motion off nothing is drawn at all.
var _from := Rect2()
var _to := Rect2()
var _started := -10.0
var _owner: WeakRef

func _ready() -> void:
	name = "FocusGlide"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 20
	set_process(false)
	get_viewport().gui_focus_changed.connect(_focus_changed)

func _local_rect(control: Control) -> Rect2:
	return get_global_transform().affine_inverse()*control.get_global_rect()

func _focus_changed(control: Control) -> void:
	var previous: Control = _owner.get_ref() as Control if _owner != null else null
	_owner = weakref(control) if is_instance_valid(control) else null
	if not UiMotion.enabled() or not is_instance_valid(control) or not control.is_visible_in_tree(): return
	if not is_instance_valid(previous) or previous == control or previous.is_queued_for_deletion() or not previous.is_visible_in_tree(): return
	# A glide in flight continues from where it currently is: interruptible.
	_from = current_rect() if UiMotion.running(_started,UiMotion.QUICK) else _local_rect(previous)
	_to = _local_rect(control)
	_started = UiMotion.now()
	set_process(true)
	queue_redraw()

## True when focus went to a tab whose selection moves with it (a pressed
## toggle, checked when drawing, after the screen selected it): that tab shows
## its own highlight at once, and a travelling wash would mark a second item.
func _selected_target() -> bool:
	var control: Control = _owner.get_ref() as Control if _owner != null else null
	return control is BaseButton and (control as BaseButton).toggle_mode and (control as BaseButton).button_pressed

func current_rect() -> Rect2:
	var travel := UiMotion.progress(_started,UiMotion.QUICK)
	return Rect2(_from.position.lerp(_to.position,travel),_from.size.lerp(_to.size,travel))

func is_gliding() -> bool:
	return UiMotion.running(_started,UiMotion.QUICK)

func _process(_delta: float) -> void:
	# Follow the target while it travels with a scrolling list.
	var control: Control = _owner.get_ref() as Control if _owner != null else null
	if is_instance_valid(control) and control.is_visible_in_tree(): _to = _local_rect(control)
	queue_redraw()
	if not is_gliding(): set_process(false)

func _draw() -> void:
	if not is_gliding() or _selected_target(): return
	# The travelling cursor speaks the settled focus language (a warm wash with
	# an amber lead edge), never a hollow outline box, and thins out on arrival.
	var fade := 1.0-UiMotion.ease_in_out(UiMotion.linear(_started,UiMotion.QUICK))
	var rect := current_rect()
	rect = Rect2(rect.position.round(),rect.size.round())
	draw_rect(rect,Color(UiArt.AMBER,0.16*fade))
	draw_rect(Rect2(rect.position,Vector2(2,rect.size.y)),Color(UiArt.AMBER,0.9*fade))
