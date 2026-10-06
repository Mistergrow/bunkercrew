class_name ItemCatalog
extends RefCounted
## Resource identity, carrying and storage use the same registered definitions.
const Registry := preload("res://scripts/content_registry.gd")
static var _signature := ""
static var _items: Dictionary = {}
static var _names: Dictionary = {}
static var _colors: Dictionary = {}
static var _ordered: Array[String] = []
static var _stored: Array[String] = []
static var _cargo: Array[String] = []
static var _textures: Dictionary = {}

static func _ensure() -> void:
	var signature: String = Registry.fingerprint()
	if signature == _signature and not _items.is_empty(): return
	_items.clear()
	_names = {}
	_colors = {}
	_ordered = []
	_stored = []
	_cargo = []
	var entries: Array = Registry.entries("items")
	for entry: Dictionary in entries:
		var id := str(entry.id)
		_items[id] = entry
		_names[id] = str(entry.label)
		_colors[id] = Color(str(entry.color))
		if bool(entry.storage): _stored.append(id)
		if bool(entry.cargo): _cargo.append(id)
	entries.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return int(a.inventory_order)<int(b.inventory_order) if int(a.inventory_order)!=int(b.inventory_order) else str(a.id)<str(b.id))
	for entry: Dictionary in entries: _ordered.append(str(entry.id))
	_names.make_read_only()
	_colors.make_read_only()
	_ordered.make_read_only()
	_stored.make_read_only()
	_cargo.make_read_only()
	_signature = signature

static func contains(id: Variant) -> bool:
	_ensure()
	return id is String and _items.has(id)

static func data(id: String) -> Dictionary:
	_ensure()
	return _items.get(id,{}).duplicate(true)

static func names() -> Dictionary:
	_ensure()
	return _names

static func colors() -> Dictionary:
	_ensure()
	return _colors

static func ordered() -> Array[String]:
	_ensure()
	return _ordered

static func storage_kinds() -> Array[String]:
	_ensure()
	return _stored

static func cargo_kinds() -> Array[String]:
	_ensure()
	return _cargo

static func _sprite(id: String) -> Dictionary:
	_ensure()
	var art: Dictionary = _items.get(id,{}).get("art",{})
	return art if art.get("kind") == "sprite" else {}

static func _texture(path: String) -> Texture2D:
	if not _textures.has(path): _textures[path] = load(path)
	return _textures[path] as Texture2D

static func region(values: Array) -> Rect2:
	return Rect2(float(values[0]),float(values[1]),float(values[2]),float(values[3]))

static func draw_icon(node: CanvasItem,id: String,rect: Rect2) -> bool:
	var art := _sprite(id)
	if art.is_empty(): return false
	var texture := _texture(str(art.texture))
	if texture == null: return false
	var source := region(art.region)
	var dimensions := (source.size*minf(rect.size.x/source.size.x,rect.size.y/source.size.y)).round()
	node.draw_texture_rect_region(texture,Rect2((rect.get_center()-dimensions*0.5).round(),dimensions),source)
	return true

static func draw_carried(node: CanvasItem,id: String,anchor: Vector2,size: float = 1.0,pouring: bool = false) -> bool:
	var art := _sprite(id)
	if art.is_empty(): return false
	var texture := _texture(str(art.texture))
	if texture == null: return false
	# Only the concrete definition has a pouring frame. Other items keep their
	# identity while a worker deposits or drops a selected material.
	var source := region(art.pour_region if pouring and art.has("pour_region") else art.region)
	var dimensions := source.size*(24.0/maxf(source.size.x,source.size.y))*size
	node.draw_texture_rect_region(texture,Rect2((anchor-Vector2(dimensions.x*0.5,dimensions.y*0.375)).round(),dimensions),source)
	return true

static func draw_world(node: CanvasItem,id: String,origin: Vector2) -> bool:
	var art := _sprite(id)
	if art.is_empty(): return false
	var texture := _texture(str(art.texture))
	if texture == null: return false
	var source := region(art.get("world_region",art.region))
	var width := float(art.get("world_width",24.0))
	var dimensions := Vector2(width,roundf(width*source.size.y/source.size.x))
	node.draw_texture_rect_region(texture,Rect2((origin-Vector2(floorf(width*0.5),dimensions.y)).round(),dimensions),source)
	return true
