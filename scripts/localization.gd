extends Node
## A local presentation preference, deliberately absent from world snapshots.
signal locale_changed(locale: String)

func _enter_tree() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	LocaleText.initialize()
	locale_changed.connect(_changed)

func _ready() -> void:
	_update_title()

func _changed(_locale: String) -> void:
	_update_title()
	_redraw(get_tree().root)

func _update_title() -> void:
	get_tree().root.title=str(ProjectSettings.get_setting("application/config/name", "Bunkercrew"))

func _redraw(node: Node) -> void:
	if node is CanvasItem: node.queue_redraw()
	for child in node.get_children(): _redraw(child)
