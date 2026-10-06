class_name CraftingCatalog
extends RefCounted
## Stable recipe IDs; the original five indices remain a legacy compatibility API.
const Registry := preload("res://scripts/content_registry.gd")
const LEGACY_IDS := ["jaw_trap","blast_trap","armor_1","armor_2","sentry_kit"]
static var _signature := ""
static var _recipes: Array[Dictionary] = []
static var _indices: Dictionary = {}
static var _stations: Dictionary = {}
static var _textures: Dictionary = {}

static func _ensure() -> void:
	var signature: String = Registry.fingerprint()
	if signature == _signature and not _recipes.is_empty(): return
	_recipes = []
	_indices = {}
	_stations = {}
	var entries: Array = Registry.entries("workshop_recipes")
	# Never let an add-on or catalog ordering reinterpret an old paid order.
	for recipe_id: String in LEGACY_IDS:
		var entry: Dictionary = Registry.data("workshop_recipes",recipe_id)
		if not entry.is_empty(): _append(entry)
	for entry: Dictionary in entries:
		if not LEGACY_IDS.has(str(entry.id)): _append(entry)
	for entry: Dictionary in Registry.entries("station_recipes"):
		_freeze(entry)
		_stations[str(entry.id)] = entry
	_recipes.make_read_only()
	_stations.make_read_only()
	_signature = signature

static func _append(entry: Dictionary) -> void:
	_freeze(entry)
	_indices[str(entry.id)] = _recipes.size()
	_recipes.append(entry)

static func _freeze(value: Variant) -> void:
	if value is Dictionary:
		for child in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child in value: _freeze(child)
		value.make_read_only()

static func recipes() -> Array[Dictionary]:
	_ensure()
	return _recipes

static func stations() -> Dictionary:
	_ensure()
	return _stations

static func index(recipe_ref: Variant) -> int:
	_ensure()
	if recipe_ref is int: return recipe_ref if recipe_ref>=0 and recipe_ref<_recipes.size() else -1
	if recipe_ref is String: return int(_indices.get(recipe_ref,-1))
	return -1

static func valid_reference(recipe_ref: Variant) -> bool:
	return index(recipe_ref)>=0

static func recipe(recipe_ref: Variant) -> Dictionary:
	var at := index(recipe_ref)
	return _recipes[at] if at>=0 else {}

static func id(recipe_ref: Variant) -> String:
	return str(recipe(recipe_ref).get("id",""))

static func order_key(owner: int,recipe_ref: Variant) -> String:
	var at := index(recipe_ref)
	return "%d:%d" % [owner,at] if at<LEGACY_IDS.size() else "%d:%s" % [owner,id(at)]

static func draw_picture(node: CanvasItem,recipe_ref: Variant,rect: Rect2) -> void:
	var entry := recipe(recipe_ref)
	if entry.is_empty(): return
	var art: Dictionary = entry.art
	var path := str(art.texture)
	if not _textures.has(path): _textures[path] = load(path)
	var texture: Texture2D = _textures[path]
	if texture != null: node.draw_texture_rect_region(texture,rect,ItemCatalog.region(art.region))

static func valid_workshop_state(state: Dictionary,transfer_limit: float) -> bool:
	if not state.get("selection") is Dictionary or not state.get("orders") is Dictionary: return false
	if not state.get("elapsed") is float or not is_finite(state.elapsed) or state.elapsed<0: return false
	if state.selection.size()>4 or state.orders.size()>recipes().size()*4: return false
	for owner in state.selection:
		if not owner is int or owner<1 or owner>4 or not valid_reference(state.selection[owner]): return false
	for key in state.orders:
		var order = state.orders[key]
		if not key is String or not order is Dictionary or not order.get("owner") is int or order.owner<1 or order.owner>4: return false
		if order.has("recipe_id") and not order.recipe_id is String: return false
		var at := index(order.get("recipe_id",order.get("recipe")))
		if at<0 or not order.get("recipe") is int or index(order.recipe)!=at: return false
		# Numeric keys remain accepted for the five historic recipes. New keys
		# carry a stable ID; old numeric extension snapshots are accepted only
		# when their explicit stable ID matches the current catalog entry.
		if key!=order_key(order.owner,at) and not (order.has("recipe_id") and key=="%d:%d" % [order.owner,at]): return false
		for field in order:
			if field not in ["materials","transfer","remaining","working","ready","recipe","recipe_id","owner"]: return false
		if not order.get("materials") is Dictionary or not order.get("working") is bool or not order.get("ready") is bool or (order.working and order.ready): return false
		var entry := recipe(at)
		for material in order.materials:
			if not entry.cost.has(material) or not order.materials[material] is int or order.materials[material]<0 or order.materials[material]>int(entry.cost[material]): return false
		for field: String in ["transfer","remaining"]:
			if not order.get(field) is float or not is_finite(order[field]) or order[field]<0: return false
		if order.transfer>transfer_limit or order.remaining>float(entry.time): return false
	return true
