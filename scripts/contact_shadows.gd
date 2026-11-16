extends Node2D
## Pixel-stepped contact shadows and ground occlusion. Static pieces (props,
## machines, wall feet) are redrawn only when their layout changes; one child
## follows the feet of hostile ground actors. Draw-only: no physics queries.
const MAX_ACTORS := 64
const MAX_LIFT := 150.0
const INK := Color(.02, .03, .035)
## Footprint width in world pixels per group; level props report their own.
const FOOTPRINTS := {
	"stations":112.0, "supplies":50.0, "core":92.0, "field_workshops":92.0, "turrets":46.0,
	"flak_stations":60.0, "medics":30.0, "walls":40.0, "dome_sites":0.0,
}
static var _strips: Dictionary = {}
static var _edges: Dictionary = {}
var game: Node
var bunker: Node2D
var static_entries: Array[Dictionary] = []
var actor_layer: Node2D
var actor_count := 0
var static_redraws := 0
var _signature := 0
var _widths: Dictionary = {}

func _ready() -> void:
	name = "ContactShadows"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 121
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var paint := CanvasItemMaterial.new()
	paint.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = paint
	actor_layer = Node2D.new()
	actor_layer.name = "ActorContact"
	actor_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	actor_layer.use_parent_material = true
	actor_layer.draw.connect(_draw_actors)
	add_child(actor_layer)

## Symmetric blob: a solid core and a lighter outer step toward both ends,
## stepped on whole texels like the art (no ordered-dither checkerboard, which
## reads as a seam on bright snow, sand or paving).
static func strip(width: int) -> ImageTexture:
	var key := clampi(int(ceil(width / 8.0)) * 8, 16, 256)
	if not _strips.has(key):
		var image := Image.create(key, 5, false, Image.FORMAT_RGBA8)
		var rows := [.42, .78, 1.0, .70, .34]
		for y in 5:
			for x in key:
				var along := absf((x + .5) / key * 2.0 - 1.0)
				var density := clampf((1.0 - along * along) * 1.25, 0.0, 1.0) * float(rows[y])
				image.set_pixel(x, y, Color(1, 1, 1, _step(density)))
		_strips[key] = ImageTexture.create_from_image(image)
	return _strips[key]

## Two shadow values and clear ground: solid, half, none.
static func _step(density: float) -> float:
	if density > .62: return 1.0
	if density > .26: return .5
	return 0.0

## One-sided occlusion where a wall meets the ground: dense at x=0, open at
## the end, in the same two steps.
static func edge(width: int) -> ImageTexture:
	var key := clampi(int(ceil(width / 8.0)) * 8, 16, 128)
	if not _edges.has(key):
		var image := Image.create(key, 6, false, Image.FORMAT_RGBA8)
		var rows := [1.0, .86, .66, .46, .28, .14]
		for y in 6:
			for x in key:
				var density := pow(1.0 - (x + .5) / key, 1.6) * float(rows[y])
				image.set_pixel(x, y, Color(1, 1, 1, _step(density)))
		_edges[key] = ImageTexture.create_from_image(image)
	return _edges[key]

func refresh() -> void:
	_widths.clear()
	static_entries.clear()
	if not is_instance_valid(game) or not is_inside_tree(): return
	var tree := get_tree()
	for group: String in FOOTPRINTS:
		for node: Node in tree.get_nodes_in_group(group):
			var item := node as Node2D
			if item == null or not game.is_ancestor_of(item) or not item.is_visible_in_tree(): continue
			var width := float(FOOTPRINTS[group])
			if width <= 0.0: continue
			# Wider than the footprint: the part beside the machine is what shows.
			static_entries.append({"at":item.global_position.round(), "width":width * 1.3, "strength":.58})
	for prop: Node in tree.get_nodes_in_group("level_props"):
		var item := prop as Node2D
		if item == null or not game.is_ancestor_of(item) or not item.is_visible_in_tree(): continue
		var size: Variant = item.get("display_size")
		static_entries.append({"at":item.global_position.round(), "width":(float(size.x) if size is Vector2 else 30.0) + 12.0, "strength":.40})
	if is_instance_valid(bunker) and bool(bunker.get("_bootstrapped")):
		# The structure's outer faces darken the ground they stand on.
		var ground := float(bunker.ground_y)
		static_entries.append({"at":Vector2(float(bunker.room_left), ground), "width":56.0, "strength":.50, "side":-1})
		static_entries.append({"at":Vector2(float(bunker.room_right), ground), "width":56.0, "strength":.50, "side":1})
	var signature := static_entries.hash()
	if signature != _signature:
		_signature = signature
		static_redraws += 1
		queue_redraw()

func _draw() -> void:
	for entry: Dictionary in static_entries:
		var at := to_local(Vector2(entry.at)).round()
		var tint := Color(INK.r, INK.g, INK.b, float(entry.strength))
		if entry.has("side"):
			var texture := edge(int(entry.width))
			var size := texture.get_size()
			var side := float(entry.side)
			draw_texture_rect(texture, Rect2(at.x, at.y, size.x * side, size.y), false, tint)
		else:
			var texture := strip(int(entry.width))
			draw_texture(texture, at - Vector2(texture.get_width() * .5, 2), tint)

func _process(_delta: float) -> void:
	if not is_instance_valid(game) or not is_visible_in_tree(): return
	var present := get_tree().get_node_count_in_group("enemies") > 0
	if present or actor_count > 0: actor_layer.queue_redraw()

func _footprint(actor: Node2D) -> float:
	var id := actor.get_instance_id()
	if _widths.has(id): return _widths[id]
	var width := 30.0
	for child in actor.get_children():
		var shape_node := child as CollisionShape2D
		if shape_node == null or shape_node.shape == null: continue
		var extent := shape_node.shape.get_rect().size.x * absf(shape_node.global_scale.x)
		if extent > 1.0: width = clampf(extent * 1.15 + 6.0, 18.0, 220.0)
		break
	_widths[id] = width
	return width

func _draw_actors() -> void:
	actor_count = 0
	if not is_instance_valid(game): return
	var floors: Array = game.get("floor_levels") if "floor_levels" in game else []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if actor_count >= MAX_ACTORS: break
		var actor := node as CharacterBody2D
		if actor == null or not actor.is_visible_in_tree(): continue
		var feet := actor.global_position
		# Presentation only: project onto the nearest known floor line below the feet.
		var floor_y := INF
		for level in floors:
			if float(level) >= feet.y - 3.0 and float(level) < floor_y: floor_y = float(level)
		var lift := floor_y - feet.y
		if lift > MAX_LIFT: continue
		var fade := 1.0 - clampf(lift / MAX_LIFT, 0.0, 1.0)
		var texture := strip(int(_footprint(actor) * lerpf(.6, 1.0, fade)))
		var at := actor_layer.to_local(Vector2(feet.x, floor_y)).round()
		actor_layer.draw_texture(texture, at - Vector2(texture.get_width() * .5, 2), Color(INK.r, INK.g, INK.b, .44 * fade))
		actor_count += 1

func diagnostics() -> Dictionary:
	return {"static":static_entries.size(), "actors":actor_count, "static_redraws":static_redraws, "physics_queries":0}
