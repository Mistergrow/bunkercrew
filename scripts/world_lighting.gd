extends Node2D
## Unified presentation lighting for one scenario world: an ambient derived
## from the light measured in the world's painted backdrop, with a storm grade;
## the backdrop's key light as a rim on the exterior's upward and sunward edges
## (actors, perimeter, ground, roof and crates) and the weather settled on them;
## lightning that lights only the sky and what stands under it; a bounded pool
## of fixture lights (one shaped light per room instead of one per lamp), a
## multiplied light structure per room that darkens and cools with depth, sky
## light through the roof hatches, a lifted key for the crew and enemies so
## they always read at night, fixture glows and contact shadows. Everything is
## derived from state that every peer already has; the node never touches
## simulation, collision or replicated fields.
## Shared per-item budget of 16 (both renderers, measured): 4 fire + 3 shot +
## 2 blast lights exist elsewhere, so the fixture pool keeps 7. Actors are
## outside the fixture lights and get the actor key instead (1 more for them).
const MAX_LIGHTS := 7
const LIGHT_Z_MIN := -8
const LIGHT_Z_MAX := 20
const REFRESH_SECONDS := .25
const FLICKER_FPS := 12.0
const NIGHT_LEVEL := .54
const FLOOR_LUMINANCE := .44
const FLOOR_CHANNEL := .36
const WARM := Color(1.0, .74, .44)
const FIRE := Color(1.0, .52, .20)
const ELECTRIC := Color(.80, .90, 1.0)
const ALARM := Color(1.0, .22, .12)
## Light-mask bit of actor art (workers, medics, enemies, pickups). Fixture
## lights leave it out; the actor key, gunfire, blasts and fires include it.
const ACTOR_MASK := 1 << 9
## Room light colours from the surface down, one character per room (the
## rooms are built in catalog order, so depth is the room): warm lamps in the
## living room, sodium yellow in the supply gallery, cold white over the
## glassworks, furnace orange in the deep smelter, a green-white service
## light in the arsenal. Deeper floors are dimmer (energy, ROOM_LIT).
const ROOM_COLORS := [Color(1.0, .74, .44), Color(1.0, .82, .46), Color(.74, .90, 1.0), Color(1.0, .58, .34), Color(.76, .96, .80)]
## Shadow side of each room's multiplied light structure, leaning toward its
## lamp colour, darker with depth.
const ROOM_SHADES := [Color(.80, .78, .76), Color(.64, .60, .54), Color(.44, .50, .60), Color(.46, .36, .34), Color(.32, .40, .38)]
## Value of the lamp-lit end of each depth: deeper floors never get as bright.
const ROOM_LIT := [Color(1.0, 1.0, 1.0), Color(.98, .94, .86), Color(.86, .92, .98), Color(.92, .80, .72), Color(.76, .86, .80)]
## Dust hanging in the lamp beams of every lit room below the surface: motes
## per room, drawn additively on the fixture glow layer (under the room's
## multiplied light, so they only show inside the cones), drifting slowly.
const ROOM_MOTES := 18
## The crew and enemies keep at least this share of their authored value.
const ACTOR_TARGET := 1.0
## Room overlay: above machines and ladders (z 0..7), below the crew (14+).
const ROOM_GRADE_Z := 9
const ROOM_TEXEL := 4.0
const ContactShadows := preload("res://scripts/contact_shadows.gd")
const RoomGrade := preload("res://shaders/room_light_grade.gdshader")
const WetMaterials := preload("res://scripts/actor_wet_materials.gd")
const BackdropGrade := preload("res://scripts/backdrop_grade.gd")
const LightKeys := preload("res://scripts/backdrop_light_keys.gd")
const PerimeterArt := preload("res://scripts/perimeter_art.gd")
const Accumulation := preload("res://scripts/weather_accumulation.gd")
## Lightning on the exterior: cool white, from the bolt's side.
const FLASH_TINT := Color(.80, .88, 1.0)
## Additive share of the flash on the exterior foreground under the bolt
## (_draw_flash_wash); it falls to WASH_FAR of that a long way off.
const FLASH_WASH := .18
const WASH_FAR := .6
const WASH_STRIP := 48.0
## The wash reaches this far above the ground line, full from WASH_FULL down.
const WASH_HEIGHT := 330.0
const WASH_FULL := 170.0
## Rows of the ground surface below the ground line that the flash lights.
const WASH_GROUND := 7.0
## Firebox centres of the furnace stations, relative to their floor anchor.
const FURNACES := {
	"station.gd":[Vector2(0, -33), false],
	"glass_furnace.gd":[Vector2(-2, -50), false],
	"deep_station.gd":[Vector2(-3, -52), true],
}
const ACTOR_GROUPS := ["players", "enemies", "medics", "pickups"]
static var _flat_texture: ImageTexture
static var _pool_texture: ImageTexture
static var _round_texture: ImageTexture
static var _room_textures: Dictionary = {}
static var _glow_textures: Dictionary = {}
static var _unshaded: CanvasItemMaterial
static var _additive: CanvasItemMaterial
static var _software := -1
## The world whose sky key and weather the shared actor and perimeter
## materials currently carry; only it may clear them when it leaves.
static var _exterior_owner := 0
var game: Node
var bunker: Node2D
var environment_id := "sector07"
var ambient := Color.WHITE
var base_ambient := Color.WHITE
var night := 0.0
var storm := 0.0
var flash := 0.0
var canvas_modulate: CanvasModulate
var actor_key: PointLight2D
var lights: Array[PointLight2D] = []
var fixtures: Array[Dictionary] = []
var active_fixtures: Array[int] = []
var room_grades: Array[Node2D] = []
var glow_layer: Node2D
var shadows: Node2D
var effects_enabled := true
var light_updates := 0
var actors_marked := 0
var flashes := 0
var _refresh := REFRESH_SECONDS
var _clock := 0.0
var _tick := -1
var _view := Rect2()
var _reduced := false
var _selection_dirty := true
var _excluded := 0
var _flash_start := -10.0
var _flash_peak := 0.0
var _last_ambient_age := 10.0
var _last_strike_age := 10.0
var _graded := Color.WHITE
var _backdrop: Array[CanvasItem] = []
var _phase := 3
var _key_center := Vector2(INF, INF)
var _key_width := 0.0
var _quiet := false
var _shown := true
var _sky := Color.WHITE
var backdrop_grade: Node2D
## Sky key on the exterior (rgb colour, a strength) and the side it comes from.
var sky_rim := Color(1, 1, 1, 0)
var key_side := 0.0
var world_hue := Color.WHITE
var accumulation: Node2D
## World x of the last lightning bolt; the flash comes from that side.
var flash_x := 0.0
var _flash_y := 0.0
var _pushed := Color(-1, -1, -1, -1)
var _pushed_flash := Vector2(-1, -1)
var _flash_drawn := false
var _shaft_points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _shaft_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
var _wash_points := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _wash_colors := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])

func _ready() -> void:
	name = "WorldLighting"
	process_mode = Node.PROCESS_MODE_PAUSABLE
	process_priority = 120 # After the camera (100) and the panorama framing (110).
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var data: Dictionary = ScenarioCatalog.environment(environment_id)
	base_ambient = ambient_for(data)
	night = night_for(data)
	sky_rim = sky_rim_for(data)
	key_side = key_side_for(data)
	world_hue = light_hue(data)
	ambient = base_ambient
	canvas_modulate = CanvasModulate.new()
	canvas_modulate.name = "Ambient"
	canvas_modulate.color = ambient
	add_child(canvas_modulate)
	# A flat light over the whole view that only actor art receives. (A
	# DirectionalLight2D would be simpler, but Compatibility ignores its item
	# cull mask and lifts everything.)
	actor_key = PointLight2D.new()
	actor_key.name = "ActorKey"
	actor_key.texture = flat_texture()
	actor_key.range_item_cull_mask = ACTOR_MASK
	actor_key.range_z_min = -4096
	actor_key.range_z_max = 4096
	actor_key.shadow_enabled = false
	actor_key.energy = 1.0
	actor_key.enabled = false
	add_child(actor_key)
	shadows = ContactShadows.new()
	shadows.game = game
	shadows.bunker = bunker
	shadows.z_index = 2 # Above floors and static props, below every actor.
	add_child(shadows)
	accumulation = Accumulation.new()
	accumulation.bunker = bunker
	accumulation.game = game
	accumulation.configure(data, sky_rim)
	add_child(accumulation)
	_configure_exterior(data)
	for index in MAX_LIGHTS:
		var lamp := PointLight2D.new()
		lamp.name = "FixtureLight%02d" % index
		lamp.texture = pool_texture()
		lamp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		lamp.range_z_min = LIGHT_Z_MIN
		lamp.range_z_max = LIGHT_Z_MAX
		lamp.range_layer_min = 0
		lamp.range_layer_max = 0
		lamp.range_item_cull_mask = 1
		lamp.shadow_enabled = false
		lamp.enabled = false
		add_child(lamp)
		lights.append(lamp)
	glow_layer = Node2D.new()
	glow_layer.name = "FixtureGlow"
	glow_layer.z_as_relative = false
	glow_layer.z_index = 1
	glow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glow_layer.material = additive_material()
	glow_layer.draw.connect(_draw_glow)
	add_child(glow_layer)
	_apply_reduced(_wants_reduced())
	_exclude_backdrop.call_deferred()

# ---------------------------------------------------------------- ambient

static func luminance(color: Color) -> float:
	return color.r * .299 + color.g * .587 + color.b * .114

## The light of a world's painted backdrop, measured offline from the panorama
## (tools/generate_backdrop_light.py): mean sky, land along the ground line,
## the brightest sky light (sun, moon, lit cloud, city glow) and its side.
## A world without a measured panorama derives the same fields from its
## catalog colours, so new worlds need no lighting row.
static func light_key(data: Dictionary) -> Dictionary:
	var id := str(data.get("id", ""))
	if LightKeys.KEYS.has(id):
		var measured: Dictionary = LightKeys.KEYS[id]
		# A content pack that repaints a known world falls back to its catalog.
		if str(data.get("path", measured.source)) == str(measured.source): return measured
	var sky := Color(str(data.get("sky_color", "#808890")))
	var palette: Array = data.get("palette", [])
	var land := Color(str(palette[0])) if not palette.is_empty() else sky.darkened(.5)
	var key := Color(str(palette[-1])) if palette.size() > 1 else sky.lightened(.35)
	return {"sky":sky, "land":land, "key":key, "key_x":0.0}

## 0 for a daylight world, 1 for a night world: the backdrop's sky, the land
## under it and its brightest light, weighted as the eye reads a scene.
static func night_for(data: Dictionary) -> float:
	var key := light_key(data)
	var light := luminance(key.sky) * .5 + luminance(key.land) * .3 + luminance(key.key) * .2
	return 1.0 - smoothstep(.20, .55, light)

## Hue of the light that falls on the foreground: the sky, the land it bounces
## from and a share of the key light, normalised to full value.
static func light_hue(data: Dictionary) -> Color:
	var key := light_key(data)
	var sky: Color = key.sky
	var land: Color = key.land
	var lamp: Color = key.key
	var mixed := Color(sky.r * .5 + land.r * .3 + lamp.r * .2, sky.g * .5 + land.g * .3 + lamp.g * .2, sky.b * .5 + land.b * .3 + lamp.b * .2)
	var peak := maxf(.001, maxf(mixed.r, maxf(mixed.g, mixed.b)))
	return Color(mixed.r / peak, mixed.g / peak, mixed.b / peak)

static func ambient_for(data: Dictionary) -> Color:
	var dark := night_for(data)
	var tint := Color.WHITE.lerp(light_hue(data), lerpf(.22, .46, dark))
	var level := lerpf(1.0, NIGHT_LEVEL, dark)
	# Heavy cloud takes a little more light than a clear sky of the same key.
	level *= 1.0 - .07 * clampf(float(data.get("rain_strength", 0.0)), 0.0, 1.0)
	var result := Color(tint.r * level, tint.g * level, tint.b * level)
	return readable(result)

## Sky key on the exterior's upward and sunward edges: the hue of the
## backdrop's brightest light (rgb) and its strength (a), weaker at night.
static func sky_rim_for(data: Dictionary) -> Color:
	var key := light_key(data)
	var lamp: Color = key.key
	var peak := maxf(.001, maxf(lamp.r, maxf(lamp.g, lamp.b)))
	var strength := lerpf(.30, .20, night_for(data)) * clampf(luminance(lamp) * 1.5, .40, 1.0)
	return Color(lamp.r / peak, lamp.g / peak, lamp.b / peak, strength)

## Side of the key light: -1 left .. 1 right, 0 straight above.
static func key_side_for(data: Dictionary) -> float:
	return clampf(float(light_key(data).get("key_x", 0.0)) * 1.4, -1.0, 1.0)

## Readability floor: the world never drops below a fixed luminance or channel.
## Actors are additionally lifted by actor_lift(), whatever the world does.
static func readable(color: Color) -> Color:
	var result := color
	var light := luminance(result)
	if light < FLOOR_LUMINANCE:
		var gain := FLOOR_LUMINANCE / maxf(light, .001)
		result = Color(result.r * gain, result.g * gain, result.b * gain)
	result.r = clampf(result.r, FLOOR_CHANNEL, 1.0)
	result.g = clampf(result.g, FLOOR_CHANNEL, 1.0)
	result.b = clampf(result.b, FLOOR_CHANNEL, 1.0)
	result.a = 1.0
	return result

## Light added to actor art on top of an ambient: brings them back to
## ACTOR_TARGET of their authored value, leaning slightly toward the world's
## hue so they still sit in the scene. Zero in daylight.
static func actor_lift(color: Color) -> Color:
	var peak := maxf(.001, maxf(color.r, maxf(color.g, color.b)))
	var hue := Color(color.r / peak, color.g / peak, color.b / peak)
	var target := Color.WHITE.lerp(hue, .10) * ACTOR_TARGET
	return Color(maxf(0.0, target.r - color.r), maxf(0.0, target.g - color.g), maxf(0.0, target.b - color.b), 1.0)

## Night grade of the crew and enemies under the open sky (rgb multiplier, a
## strength; actor_wet.gdshader): the actor key keeps every figure at its
## authored value, which by night left the outdoor crew brighter than the
## lamp-lit rooms. Outside they sink to about two thirds, leaning toward the
## night's hue, and read by a stronger sky rim instead. None by day.
static func exterior_grade_for(dark: float, storm_share: float, hue: Color) -> Color:
	var amount := smoothstep(.30, .85, clampf(dark + storm_share * .3, 0.0, 1.0))
	var shade := Color.WHITE.lerp(hue, .28) * lerpf(1.0, .66, amount)
	return Color(shade.r, shade.g, shade.b, amount)

## Software rasterisers (llvmpipe, SwiftShader, WARP...) spend most of their
## light time on 2D shadow maps; they get the shadowless tier.
static func software_renderer() -> bool:
	if _software < 0:
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		_software = 0
		for name_part in ["llvmpipe", "softpipe", "swiftshader", "lavapipe", "software", "basic render"]:
			if name_part in adapter: _software = 1
	return _software == 1

static func shadows_allowed() -> bool:
	return not software_renderer()

# ---------------------------------------------------------------- textures

static func unshaded_material() -> CanvasItemMaterial:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unshaded

static func additive_material() -> CanvasItemMaterial:
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _additive

static func flat_texture() -> ImageTexture:
	if _flat_texture == null:
		var image := Image.create(8, 8, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE)
		_flat_texture = ImageTexture.create_from_image(image)
	return _flat_texture

## Ceiling pool: origin a quarter down the texture, short above, long below.
static func pool_texture() -> ImageTexture:
	if _pool_texture == null:
		var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
		for y in 128:
			for x in 128:
				var dx := (x - 63.5) / 62.0
				var dy := (y - 31.5) / (30.0 if y < 32 else 94.0)
				var distance := sqrt(dx * dx + dy * dy)
				var value := pow(clampf(1.0 - distance, 0.0, 1.0), 1.7)
				image.set_pixel(x, y, Color(value, value, value))
		_pool_texture = ImageTexture.create_from_image(image)
	return _pool_texture

static func round_texture() -> ImageTexture:
	if _round_texture == null:
		var image := Image.create(96, 96, false, Image.FORMAT_RGB8)
		for y in 96:
			for x in 96:
				var distance := Vector2(x - 47.5, y - 47.5).length() / 47.0
				var value := pow(clampf(1.0 - distance, 0.0, 1.0), 1.9)
				image.set_pixel(x, y, Color(value, value, value))
		_round_texture = ImageTexture.create_from_image(image)
	return _round_texture

## Light of a whole room in one texture (ROOM_TEXEL world pixels per texel):
## the three ceiling cones and their floor pools, black at the room's edges so
## nothing outside the room receives it. Matches room_light_grade.gdshader.
static func room_light_texture(height: int) -> ImageTexture:
	if not _room_textures.has(height):
		var width := int(ScenarioRoomCatalog.ROOM_WIDTH / ROOM_TEXEL)
		var rows := int(ceilf(height / ROOM_TEXEL))
		var image := Image.create(width, rows, false, Image.FORMAT_RGB8)
		var lamps: Array[float] = []
		for fraction in ScenarioBunkerArt.LAMP_FRACTIONS: lamps.append(roundf(ScenarioRoomCatalog.ROOM_WIDTH * float(fraction)))
		for row in rows:
			for column in width:
				var p := Vector2((column + .5) * ROOM_TEXEL, (row + .5) * ROOM_TEXEL)
				var value := 0.0
				for x in lamps:
					var below := p.y - 36.0
					var across := absf(p.x - x)
					var spread := 30.0 + maxf(below, 0.0) * .70
					var beam := (1.0 - smoothstep(.25, 1.0, across / spread)) * smoothstep(-14.0, 6.0, below) * (1.0 - .35 * smoothstep(30.0, float(height) - 20.0, below))
					var pool := (1.0 - smoothstep(34.0, 100.0, across)) * smoothstep(float(height) - 80.0, float(height) - 20.0, p.y)
					value = maxf(value, maxf(beam, pool * .8))
				# Faint fill so the room never has a hard light edge inside.
				value = maxf(value, .16)
				var edge := minf(minf(p.x, ScenarioRoomCatalog.ROOM_WIDTH - p.x), minf(p.y, float(height) - p.y))
				value *= smoothstep(0.0, 14.0, edge)
				image.set_pixel(column, row, Color(value, value, value))
		_room_textures[height] = ImageTexture.create_from_image(image)
	return _room_textures[height]

## Additive halo on the pixel grid: stepped rings broken by a 4x4 ordered
## dither instead of a smooth gradient. One texture per drawn size keeps every
## dither cell exactly one world pixel.
static func glow_texture(size: Vector2i) -> ImageTexture:
	if not _glow_textures.has(size):
		var bayer := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		var half := Vector2(size) * .5
		for y in size.y:
			for x in size.x:
				var distance := ((Vector2(x, y) + Vector2(.5, .5) - half) / half).length()
				var value := pow(clampf(1.0 - distance, 0.0, 1.0), 1.5) * 4.0
				var step := floorf(value)
				if value - step > (bayer[(y % 4) * 4 + x % 4] + .5) / 16.0: step += 1.0
				image.set_pixel(x, y, Color(1, 1, 1, clampf(step / 4.0, 0.0, 1.0)))
		_glow_textures[size] = ImageTexture.create_from_image(image)
	return _glow_textures[size]

# ---------------------------------------------------------------- exclusion

## Painted backdrop layers keep their authored brightness: ambient and fixture
## lights belong to the playable foreground only. Foreground props, plants and
## animals inside the scenery stay shaded so they match the crew beside them.
func _exclude_backdrop() -> void:
	if not is_instance_valid(game): return
	var scenery: Node = game.get("scenery")
	if is_instance_valid(scenery):
		var shaded: Array = [scenery.get("props_layer"), scenery.get("vegetation_layer"), scenery.get("fauna_layer")]
		if not scenery.child_entered_tree.is_connected(_on_backdrop_child.bind(shaded)):
			scenery.child_entered_tree.connect(_on_backdrop_child.bind(shaded))
		for child in scenery.get_children():
			if child not in shaded:
				_exclude(child)
				if child is CanvasItem and child not in _backdrop: _backdrop.append(child)
		_place_backdrop_grade(scenery, shaded)
	var weather: Node = game.get("weather")
	if is_instance_valid(weather) and is_instance_valid(weather.get("sky_layer")): _exclude(weather.sky_layer)
	exclude_labels()

## The atmospheric veil (BackdropGrade) goes over the last painted layer and
## under the shaded foreground layers; as a backdrop child it is unshaded and
## takes the storm grade with the rest.
func _place_backdrop_grade(scenery: Node, shaded: Array) -> void:
	if not is_instance_valid(backdrop_grade):
		backdrop_grade = scenery.get_node_or_null("BackdropGrade") as Node2D
	if not is_instance_valid(backdrop_grade):
		backdrop_grade = BackdropGrade.new()
		if is_instance_valid(bunker): backdrop_grade.ground_line = float(bunker.ground_y)
		backdrop_grade.configure(scenery, night)
		scenery.add_child(backdrop_grade)
	var below := scenery.get_child_count() - 1
	for layer: Variant in shaded:
		if layer is Node and (layer as Node).get_parent() == scenery: below = mini(below, (layer as Node).get_index())
	scenery.move_child(backdrop_grade, below)
	backdrop_grade.visible = is_visible_in_tree()

func _on_backdrop_child(child: Node, shaded: Array) -> void:
	if child not in shaded:
		_exclude(child)
		if child is CanvasItem and child not in _backdrop:
			_backdrop.append(child)
			child.modulate = _sky

func _exclude(node: Node) -> void:
	var item := node as CanvasItem
	if item != null and item.material == null and not item.use_parent_material:
		item.material = unshaded_material()
		_excluded += 1
	if not node.child_entered_tree.is_connected(_exclude):
		node.child_entered_tree.connect(_exclude)
	for child in node.get_children(): _exclude(child)

## Floating identity tags are interface, not lit surfaces.
func exclude_labels() -> void:
	if not is_instance_valid(game) or not "players" in game: return
	for worker in game.players:
		if not is_instance_valid(worker): continue
		var tag := worker.find_child("WorkerIdentity", true, false) as CanvasItem
		if tag != null and tag.material == null: tag.material = unshaded_material()

## Moves the art of every actor onto the actor light mask: out of the fixture
## lights (no double lighting under a lamp), into the actor key. Presentation
## property only; revisited when an actor gains or loses children.
func mark_actors() -> void:
	if not is_instance_valid(game): return
	var tree := get_tree()
	for group: String in ACTOR_GROUPS:
		for node: Node in tree.get_nodes_in_group(group):
			if not node is CanvasItem or not game.is_ancestor_of(node): continue
			var signature := node.get_child_count()
			if int(node.get_meta(&"actor_light", -1)) == signature: continue
			node.set_meta(&"actor_light", signature)
			_mark(node)
			actors_marked += 1

func _mark(node: Node) -> void:
	var item := node as CanvasItem
	if item != null and not item is Light2D and str(node.name) not in ["WorkerIdentity", "GroundShadow"]:
		item.light_mask = ACTOR_MASK
	for child in node.get_children(): _mark(child)

# ---------------------------------------------------------------- fixtures

func _wants_reduced() -> bool:
	if not effects_enabled: return true
	if not is_instance_valid(game): return false
	var weather: Node = game.get("weather")
	return is_instance_valid(weather) and bool(weather.get("reduced_effects"))

func _apply_reduced(value: bool) -> void:
	_reduced = value
	# Without fixture lights the interior keeps more of its authored brightness.
	ambient = readable(base_ambient.lerp(Color.WHITE, .45)) if value else base_ambient
	_graded = Color(-1, -1, -1)
	_quiet = false
	_apply_grade()
	if value:
		for lamp in lights: lamp.enabled = false
		active_fixtures.clear()
		flash = 0.0
	_selection_dirty = true
	_tick = -1
	glow_layer.queue_redraw()

func _fixture(at: Vector2, radius: float, color: Color, energy: float, kind: String, room: int = -1, flicker: float = 0.0) -> void:
	fixtures.append({"at":at, "radius":radius, "color":color, "energy":energy, "kind":kind, "room":room, "flicker":flicker})

func collect_fixtures() -> void:
	fixtures.clear()
	if not is_instance_valid(bunker) or not is_instance_valid(game) or not bool(bunker.get("_bootstrapped")): return
	var room := 0
	for rect: Rect2 in bunker.lit_room_rects():
		# Ceiling fixtures keep their glow; the room's light is one shaped voice.
		for point in ScenarioBunkerArt.lamp_points(rect):
			_fixture(point, 138.0, WARM, 1.3, "ceiling", room)
		var depth := mini(room, ROOM_COLORS.size() - 1)
		# Deeper floors get a dimmer, colder fill: their lamps still light the
		# room, the corners between them sink further.
		_fixture(rect.get_center(), maxf(rect.size.x, rect.size.y) * .5, ROOM_COLORS[depth], lerpf(1.0, .58, float(depth) / 4.0), "room", room)
		fixtures[-1]["rect"] = rect
		room += 1
	for point: Vector2 in bunker.work_lamp_points():
		_fixture(point, 124.0, WARM, 1.1, "work", -1, .05)
	# The cable bulbs strung across an open excavation: glow only, no light
	# voice (the work lamp is the dig's light).
	if bunker.has_method("raw_rect") and "open_depths" in bunker and "excavation_depths" in bunker:
		for index in range(int(bunker.open_depths), int(bunker.excavation_depths)):
			var site: Variant = bunker.modules[index] if index < bunker.modules.size() else null
			if is_instance_valid(site) and bool(site.get("curing")): continue
			for bulb: Vector2 in ExcavationRoomArt.festoon_points(bunker.raw_rect(index)):
				_fixture(bulb, 30.0, WARM, .0, "bulb", -1, .03)
	# Doorways: warm spill at each gate, pulsing as an alarm while a wave is on.
	# At night the spill leans out of the gate onto the ground outside.
	var rounds: Node = game.get("rounds")
	var alarm := is_instance_valid(rounds) and str(rounds.get("phase")) in ["warning", "attack"]
	var lean := 22.0 * night
	for side in [-1.0, 1.0]:
		var x := (float(bunker.room_left) + 8.0 - lean) if side < 0.0 else (float(bunker.room_right) - 8.0 + lean)
		_fixture(Vector2(x, float(bunker.ground_y) - 58.0 + 26.0 * night), 96.0 + 34.0 * night, ALARM if alarm else WARM, .8 if alarm else .62 + .3 * night, "alarm" if alarm else "door")
	var tree := get_tree()
	for station: Node in tree.get_nodes_in_group("stations"):
		if not station is Node2D or not game.is_ancestor_of(station): continue
		var script: Script = station.get_script()
		var spec: Array = FURNACES.get(script.resource_path.get_file() if script != null else "", [])
		if spec.is_empty() or not bool(station.get("working")): continue
		if script.resource_path.get_file() == "station.gd" and str(station.get("kind")) != "furnace": continue
		_fixture(station.global_position + Vector2(spec[0]), 92.0, ELECTRIC if bool(spec[1]) else FIRE, .9, "fire", -1, .12)
	for prop: Node in tree.get_nodes_in_group("level_props"):
		var lamp_glow: Node2D = prop.get("glow")
		if is_instance_valid(lamp_glow) and game.is_ancestor_of(prop) and prop.is_visible_in_tree():
			_fixture(lamp_glow.global_position, 84.0, WARM, .7, "lamp")
	var perimeter: Node = game.get("perimeter")
	if is_instance_valid(perimeter):
		for yard: Node in perimeter.get_children():
			var yard_lamps: Variant = yard.get("lamps")
			if not yard_lamps is Array: continue
			for sprite: Sprite2D in yard_lamps:
				if not is_instance_valid(sprite) or not sprite.is_visible_in_tree(): continue
				var size := sprite.region_rect.size * sprite.global_scale
				_fixture(sprite.global_position + Vector2(size.x * .5, size.y * .12), 110.0, WARM, .8, "yard")

func _view_rect() -> Rect2:
	var viewport := get_viewport()
	if viewport == null: return Rect2(-100000, -100000, 200000, 200000)
	return viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect()

## Rooms nearest the view centre get their shaped light first; loose fixtures
## (doors, fires, yard lamps) fill the rest and keep at least three voices.
func select_lights() -> void:
	_selection_dirty = false
	active_fixtures.clear()
	if _reduced or not is_visible_in_tree():
		for lamp in lights: lamp.enabled = false
		return
	var center := _view.get_center()
	var rooms: Array[int] = []
	var loose: Array[int] = []
	for index in fixtures.size():
		var entry: Dictionary = fixtures[index]
		var kind := str(entry.kind)
		if kind in ["ceiling", "bulb"]: continue
		var area: Rect2 = entry.rect if entry.has("rect") else Rect2(Vector2(entry.at) - Vector2.ONE * float(entry.radius), Vector2.ONE * float(entry.radius) * 2.0)
		if not area.intersects(_view): continue
		if kind == "room": rooms.append(index)
		else: loose.append(index)
	var nearest := func(a: int, b: int) -> bool:
		return Vector2(fixtures[a].at).distance_squared_to(center) < Vector2(fixtures[b].at).distance_squared_to(center)
	rooms.sort_custom(nearest)
	loose.sort_custom(nearest)
	var room_budget := MAX_LIGHTS - mini(loose.size(), 3)
	var slot := 0
	for index in rooms:
		if slot >= room_budget: break
		_assign(slot, fixtures[index])
		active_fixtures.append(index)
		slot += 1
	for index in loose:
		if slot >= MAX_LIGHTS: break
		_assign(slot, fixtures[index])
		active_fixtures.append(index)
		slot += 1
	for index in range(slot, lights.size()): lights[index].enabled = false

func _assign(slot: int, entry: Dictionary) -> void:
	var lamp := lights[slot]
	var kind := str(entry.kind)
	if kind == "room":
		var rect: Rect2 = entry.rect
		var texture := room_light_texture(int(rect.size.y))
		lamp.texture = texture
		lamp.texture_scale = ROOM_TEXEL
		lamp.position = to_local(rect.position + Vector2(texture.get_size()) * ROOM_TEXEL * .5)
		lamp.scale = Vector2.ONE
	else:
		var pooled := kind in ["work", "yard"]
		var radius := float(entry.radius)
		lamp.texture = pool_texture() if pooled else round_texture()
		lamp.texture_scale = radius / (64.0 if pooled else 48.0)
		# The pool texture's origin sits a quarter below its top edge.
		lamp.position = to_local(Vector2(entry.at) + (Vector2(0, radius * .5) if pooled else Vector2.ZERO))
		lamp.scale = Vector2.ONE
	lamp.color = entry.color
	lamp.energy = _energy(entry, 1.0)
	lamp.set_meta("fixture", entry)
	lamp.enabled = true
	light_updates += 1

func _energy(entry: Dictionary, wave: float) -> float:
	var kind := str(entry.kind)
	# Daylight worlds already show the room at full value: lamps only accent.
	var daylight := lerpf(.34, 1.0, night)
	if kind == "fire": daylight = lerpf(.6, 1.0, night)
	# A dig's work lamp is its only light, by day as by night.
	elif kind == "work": daylight = lerpf(.75, 1.0, night)
	elif kind == "room": daylight = lerpf(.18, .92, night)
	elif kind == "door": daylight = lerpf(.30, 1.0, night)
	return float(entry.energy) * daylight * wave

# ---------------------------------------------------------------- room grade

## One multiplied light structure per lit room, from the room's own corner.
func _sync_room_grades() -> void:
	var rects: Array[Rect2] = []
	for entry: Dictionary in fixtures:
		if str(entry.kind) == "room": rects.append(entry.rect)
	while room_grades.size() < rects.size():
		var grade := Node2D.new()
		grade.name = "RoomGrade%02d" % room_grades.size()
		grade.z_as_relative = false
		grade.z_index = ROOM_GRADE_Z
		grade.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var paint := ShaderMaterial.new()
		paint.shader = RoomGrade
		grade.material = paint
		grade.draw.connect(_draw_room_grade.bind(grade))
		add_child(grade)
		room_grades.append(grade)
	var lamps := Vector3.ZERO
	for index in 3: lamps[index] = roundf(ScenarioRoomCatalog.ROOM_WIDTH * float(ScenarioBunkerArt.LAMP_FRACTIONS[mini(index, ScenarioBunkerArt.LAMP_FRACTIONS.size() - 1)]))
	for index in room_grades.size():
		var grade := room_grades[index]
		grade.visible = index < rects.size()
		if not grade.visible: continue
		var rect := rects[index]
		var depth := mini(index, ROOM_SHADES.size() - 1)
		grade.position = to_local(rect.position)
		grade.set_meta("size", rect.size)
		var paint := grade.material as ShaderMaterial
		paint.set_shader_parameter("room", rect.size)
		paint.set_shader_parameter("lamps", lamps)
		var shade: Color = ROOM_SHADES[depth]
		# The surface room's shadows take the hue of the light outside its
		# hatch and gates: cool under a night sky, warm at sunset.
		if depth == 0: shade = shade * Color.WHITE.lerp(world_hue, .32)
		paint.set_shader_parameter("shade", shade)
		paint.set_shader_parameter("lit", ROOM_LIT[depth])
		# Daylight surface rooms keep a lighter touch than the deep floors.
		paint.set_shader_parameter("strength", lerpf(.75, 1.0, maxf(night, minf(1.0, float(depth)))))
		grade.queue_redraw()

func _draw_room_grade(grade: Node2D) -> void:
	var size: Vector2 = grade.get_meta("size", Vector2.ZERO)
	if size != Vector2.ZERO: grade.draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE)

# ---------------------------------------------------------------- atmosphere

## Storm darkening follows the shower. Lightning lights only what stands under
## the sky: the painted backdrop (strongest around the bolt), the rims of the
## exterior's edges that face the bolt and the exposed ground surface. The
## bunker interior, the underground and the actor key keep their light. One
## frame at full strength, then a fast fall; never more than one flash per
## 0.5 s, none with reduced effects.
func _atmosphere(delta: float) -> void:
	var weather: Node = game.get("weather") if is_instance_valid(game) else null
	var target := 0.0
	var strike := 0.0
	if is_instance_valid(weather) and not _reduced:
		if str(weather.get("environment_weather")) in ["rain", "storm"]:
			target = clampf(float(weather.get("rain_strength")), 0.0, 1.0) * (1.0 if bool(weather.get("lightning_enabled")) else .55)
		var ambient_age := float(weather.get("lightning_age"))
		var events: Node = weather.get("storm_events")
		var strike_age := float(events.get("age")) if is_instance_valid(events) and events.has_method("visual_strength") and events.visual_strength() > 0.0 else 10.0
		var fresh := (ambient_age < _last_ambient_age and ambient_age < .1) or (strike_age < _last_strike_age and strike_age < .1)
		_last_ambient_age = ambient_age
		_last_strike_age = strike_age
		if fresh and _clock - _flash_start >= .5:
			_flash_start = _clock
			_flash_peak = 1.0 if strike_age < .1 else .85
			flashes += 1
			_aim_flash(weather, events, strike_age < .1)
		var since := _clock - _flash_start
		strike = 0.0 if since > .45 else _flash_peak * (1.0 if since < .034 else exp(-(since - .034) / .06))
		if strike < .01: strike = 0.0
	var settled := is_equal_approx(storm, target) and strike == 0.0 and flash == 0.0
	storm = move_toward(storm, target, delta * .25)
	flash = strike
	# A clear or settled sky needs no per-frame grading.
	var shown := is_visible_in_tree()
	if settled and _quiet and shown == _shown: return
	_quiet = settled
	_shown = shown
	_apply_grade()

## Where the light of a fresh strike comes from: the replicated tree strike's
## target or the ambient bolt's foot, both known to every peer.
func _aim_flash(weather: Node, events: Node, struck: bool) -> void:
	var source: Variant = events.get("bolt") if struck and is_instance_valid(events) else weather.get("bolt")
	var bolt := PackedVector2Array()
	if source is PackedVector2Array: bolt = source
	if not bolt.is_empty():
		flash_x = bolt[-1].x
		_flash_y = bolt[0].y
	elif struck and is_instance_valid(events) and events.get("target") is Vector2:
		var target: Vector2 = events.get("target")
		flash_x = target.x
		_flash_y = target.y - 400.0
	else:
		var origin: Variant = weather.get("thunder_origin")
		var foot: Vector2 = origin if origin is Vector2 else _view.get_center()
		flash_x = foot.x
		_flash_y = _view.position.y

func _apply_grade() -> void:
	var grade := ambient
	if storm > 0.0:
		grade = Color(grade.r * lerpf(1.0, .84, storm), grade.g * lerpf(1.0, .86, storm), grade.b * lerpf(1.0, .93, storm))
	var lift := actor_lift(grade)
	# The hostile crest and lamps strengthen with the dark (actor_wet.gdshader).
	WetMaterials.set_team_night(night + storm * .6)
	if not grade.is_equal_approx(_graded):
		_graded = grade
		canvas_modulate.color = grade
		var strata := _strata()
		if is_instance_valid(strata): strata.set_ambient(grade)
	# Actors keep their lifted value everywhere; lightning adds only a rim
	# from the bolt's side to those outside (actor_wet.gdshader).
	var lit := maxf(lift.r, maxf(lift.g, lift.b)) > .015
	if lit != actor_key.enabled:
		actor_key.enabled = lit
		_key_center = Vector2(INF, INF)
	if lit and not actor_key.color.is_equal_approx(Color(lift.r, lift.g, lift.b)): actor_key.color = Color(lift.r, lift.g, lift.b)
	_push_exterior()
	if flash > 0.0 or _flash_drawn: glow_layer.queue_redraw()
	_flash_drawn = flash > 0.0
	# The painted backdrop ignores the ambient (it is unshaded), so it takes the
	# storm grade here; the flash lifts it a little everywhere and strongly
	# around the bolt (BackdropGrade).
	var sky := Color(lerpf(1.0, .84, storm), lerpf(1.0, .86, storm), lerpf(1.0, .92, storm))
	if flash > 0.0: sky = Color(sky.r * (1.0 + flash * .22), sky.g * (1.0 + flash * .26), sky.b * (1.0 + flash * .34))
	# A hidden bunker (road view) leaves the backdrop as authored.
	if not is_visible_in_tree(): sky = Color.WHITE
	if is_instance_valid(backdrop_grade):
		backdrop_grade.visible = is_visible_in_tree()
		if backdrop_grade.has_method("set_flash"): backdrop_grade.set_flash(flash if is_visible_in_tree() else 0.0, Vector2(flash_x, _flash_y))
	if not sky.is_equal_approx(_sky): _tint_backdrop(sky)

func _strata() -> Node:
	return bunker.get_node_or_null("TerrainStrata") if is_instance_valid(bunker) else null

## Interior of the bunker in world space (rooms below the roof slab): the sky
## key and lightning stop at its walls.
func interior_rect() -> Rect2:
	if not is_instance_valid(bunker): return Rect2()
	var top := float(ScenarioBunker.ROOF_Y) + 17.0
	return Rect2(float(bunker.room_left), top, float(bunker.room_right) - float(bunker.room_left), 100000.0)

## Static per world: weather settled on the perimeter's upward faces.
func _configure_exterior(data: Dictionary) -> void:
	_exterior_owner = get_instance_id()
	var kind := int(Accumulation.STRATA.surface_for(data))
	var spec: Array = Accumulation.STRATA.PROFILES.get(environment_id, Accumulation.STRATA.PROFILES.sector07)
	var fence := PerimeterArt.pixel_material()
	fence.set_shader_parameter("settle_kind", kind if kind in [Accumulation.SNOW, Accumulation.WET, Accumulation.ASH, Accumulation.SAND] else 0)
	fence.set_shader_parameter("settle_tint", Accumulation.STRATA.cap_tint_for(data, kind, spec[2]))
	_pushed = Color(-1, -1, -1, -1)

## Sky key and lightning for the exterior's shaders: actors, perimeter and the
## ground surface. Sent only when a value changes (a storm or a flash).
func _push_exterior() -> void:
	var rim := sky_rim
	rim.a *= lerpf(1.0, .5, storm)
	if not is_visible_in_tree(): rim.a = 0.0
	var shown_flash := flash if is_visible_in_tree() else 0.0
	if _exterior_owner != get_instance_id(): return
	WetMaterials.set_exterior_grade(exterior_grade_for(night, storm, world_hue) if is_visible_in_tree() else Color(1, 1, 1, 0))
	if rim.is_equal_approx(_pushed) and is_equal_approx(shown_flash, _pushed_flash.x) and is_equal_approx(flash_x, _pushed_flash.y): return
	_pushed = rim
	_pushed_flash = Vector2(shown_flash, flash_x)
	WetMaterials.set_world_light(rim, key_side, interior_rect(), shown_flash, flash_x)
	var fence := PerimeterArt.pixel_material()
	fence.set_shader_parameter("sky_rim", rim)
	fence.set_shader_parameter("rim_side", key_side)
	fence.set_shader_parameter("flash", shown_flash)
	fence.set_shader_parameter("flash_x", flash_x)
	var strata := _strata()
	if is_instance_valid(strata) and strata.has_method("set_sky_rim"):
		strata.set_sky_rim(rim)
		strata.set_flash(shown_flash, flash_x)

func _tint_backdrop(sky: Color) -> void:
	_sky = sky
	for layer in _backdrop:
		if is_instance_valid(layer): layer.modulate = sky

func _exit_tree() -> void:
	# The backdrop outlives a hidden or rebuilt bunker: leave it as authored.
	if not _sky.is_equal_approx(Color.WHITE): _tint_backdrop(Color.WHITE)
	if is_instance_valid(backdrop_grade): backdrop_grade.queue_free()
	# The shared actor and perimeter materials outlive this world (menu, road
	# view): they leave with no sky key, flash or settled weather, unless a
	# newer world already owns them.
	if _exterior_owner != get_instance_id(): return
	_exterior_owner = 0
	WetMaterials.set_world_light(Color(1, 1, 1, 0), 0.0, Rect2(), 0.0, 0.0)
	WetMaterials.set_exterior_grade(Color(1, 1, 1, 0))
	var fence := PerimeterArt.pixel_material()
	fence.set_shader_parameter("sky_rim", Color(1, 1, 1, 0))
	fence.set_shader_parameter("flash", 0.0)
	fence.set_shader_parameter("settle_kind", 0)

func _process(delta: float) -> void:
	if not is_instance_valid(game) or not is_instance_valid(bunker): return
	var reduced := _wants_reduced()
	if reduced != _reduced: _apply_reduced(reduced)
	_clock += delta
	_refresh += delta
	# The periodic scans are spread over three frames instead of one spike.
	if _refresh >= REFRESH_SECONDS:
		_refresh = 0.0
		_phase = 0
	if _phase == 0:
		var dirty := _selection_dirty
		var before := fixtures.hash()
		collect_fixtures()
		if fixtures.hash() != before:
			_selection_dirty = true
			glow_layer.queue_redraw()
			_sync_room_grades()
		else:
			_selection_dirty = dirty
	elif _phase == 1:
		exclude_labels()
		mark_actors()
	elif _phase == 2:
		shadows.refresh()
		accumulation.refresh()
	_phase += 1
	_atmosphere(delta)
	var view := _view_rect()
	if not view.is_equal_approx(_view):
		# Only a move of a tenth of the view re-ranks; fixtures themselves are static.
		if _view.size == Vector2.ZERO or absf(view.size.x - _view.size.x) > 1.0 or view.position.distance_to(_view.position) > view.size.x * .1:
			_view = view
			_selection_dirty = true
	if _selection_dirty: select_lights()
	# The key reaches an eighth of the view past every edge, so it only has to
	# follow the camera in steps.
	if actor_key.enabled and (view.get_center().distance_to(_key_center) > view.size.x * .08 or absf(view.size.x - _key_width) > 1.0):
		_key_center = view.get_center()
		_key_width = view.size.x
		actor_key.position = to_local(_key_center)
		actor_key.texture_scale = maxf(view.size.x, view.size.y) / 8.0 * 1.25
	if _reduced: return
	var tick := floori(_clock * FLICKER_FPS)
	if tick == _tick: return
	_tick = tick
	var seconds := tick / FLICKER_FPS
	var redraw := false
	for lamp in lights:
		if not lamp.enabled: continue
		var entry: Dictionary = lamp.get_meta("fixture")
		var wave := 1.0
		if str(entry.kind) == "alarm":
			# One slow swell per 1.6 s: far below any photosensitivity threshold.
			wave = .72 + .28 * sin(seconds * TAU / 1.6)
			redraw = true
		elif float(entry.flicker) > 0.0:
			var phase := float(entry.at.x) * .37
			wave = 1.0 + float(entry.flicker) * (sin(seconds * 6.7 + phase) * .65 + sin(seconds * 11.3 + phase * 2.1) * .35)
			redraw = true
		else:
			continue
		lamp.energy = _energy(entry, wave)
		light_updates += 1
	# Room dust drifts on this clock too.
	if not redraw:
		for entry: Dictionary in fixtures:
			if str(entry.kind) == "room" and (entry.rect as Rect2).intersects(_view):
				redraw = true
				break
	if redraw: glow_layer.queue_redraw()

func _draw_glow() -> void:
	var seconds := 0.0 if _reduced else _tick / FLICKER_FPS
	for entry: Dictionary in fixtures:
		var kind := str(entry.kind)
		if kind == "room": continue
		var at: Vector2 = glow_layer.to_local(Vector2(entry.at)).round()
		var size := Vector2(56, 22)
		var strength := .30
		match kind:
			"work": size = Vector2(52, 22)
			"fire":
				size = Vector2(62, 46)
				strength = .34 * (1.0 + float(entry.flicker) * sin(seconds * 6.7 + float(entry.at.x) * .37))
			"alarm":
				size = Vector2(34, 26)
				strength = .30 * (.72 + .28 * sin(seconds * TAU / 1.6))
				at += Vector2(0, -6)
			"door":
				size = Vector2(30, 22)
				strength = .12
				at += Vector2(0, -6)
			"lamp": size = Vector2(36, 30)
			"yard": size = Vector2(46, 34)
			"bulb":
				size = Vector2(34, 28)
				strength = .40 * (1.0 + float(entry.flicker) * sin(seconds * 5.3 + float(entry.at.x) * .21))
				# Each bulb throws a dim pool onto the rock face below it.
				glow_layer.draw_texture(glow_texture(Vector2i(84, 64)), at + Vector2(-42, 6), Color(WARM.r, WARM.g, WARM.b, .13))
		# Underground bulbs burn the same by day and by night.
		if kind != "bulb": strength *= lerpf(.55, 1.0, night)
		var tint: Color = entry.color
		glow_layer.draw_texture(glow_texture(Vector2i(size)), at - size * .5 + Vector2(0, 4 if kind in ["ceiling", "work"] else 0), Color(tint.r, tint.g, tint.b, strength))
		# At night gates and yard lamps throw a pool onto the unlit ground.
		if night > .2 and kind in ["door", "alarm", "yard"] and is_instance_valid(bunker):
			var ground := glow_layer.to_local(Vector2(0, float(bunker.ground_y))).y
			var outward := 0.0
			if kind != "yard": outward = 34.0 if float(entry.at.x) > (float(bunker.room_left) + float(bunker.room_right)) * .5 else -34.0
			var pool := Vector2(118, 8) if kind != "yard" else Vector2(96, 8)
			var spill := (.26 if kind != "yard" else .20) * night * (strength / maxf(.001, .30 * lerpf(.55, 1.0, night)) if kind == "alarm" else 1.0)
			glow_layer.draw_texture(glow_texture(Vector2i(pool)), Vector2(roundf(at.x + outward - pool.x * .5), roundf(ground - pool.y * .5)), Color(tint.r, tint.g, tint.b, spill))
	_draw_hatch_light()
	_draw_room_dust(seconds)
	_draw_flash_wash()

## Dust motes in the lamp light of each lit room in view (ROOM_MOTES): single
## world texels that hover and drift on slow sines from the flicker clock, in
## the room's lamp colour. The room's multiplied light grade above this layer
## leaves them bright inside the cones and all but gone in the shadows.
func _draw_room_dust(seconds: float) -> void:
	if _reduced: return
	var room := 0
	for entry: Dictionary in fixtures:
		if str(entry.kind) != "room": continue
		var rect: Rect2 = entry.rect
		var depth := room
		room += 1
		if not rect.intersects(_view.grow(32.0)): continue
		var tint: Color = ROOM_COLORS[mini(depth, ROOM_COLORS.size() - 1)]
		var origin := glow_layer.to_local(rect.position)
		var count := ROOM_MOTES if depth > 0 else ROOM_MOTES >> 1
		for mote in count:
			var seed_x := fposmod(float(mote) * 0.6180339 + float(depth) * 0.37, 1.0)
			var seed_y := fposmod(float(mote) * 0.7548777 + float(depth) * 0.21, 1.0)
			var x := 34.0 + seed_x * (rect.size.x - 68.0) + sin(seconds * (.17 + seed_y * .12) + float(mote) * 2.1) * 16.0
			var y := 46.0 + seed_y * (rect.size.y - 80.0) + sin(seconds * (.23 + seed_x * .15) + float(mote) * 1.3) * 12.0
			var alpha := .55 + .35 * seed_x
			glow_layer.draw_rect(Rect2((origin + Vector2(x, y)).floor(), Vector2.ONE), Color(tint.r, tint.g, tint.b, alpha))

## Lightning on the exterior foreground. The painted backdrop takes the flash
## through its own grade; what stands in front of it under the open sky (the
## bunker's outer shell and roof, the ground surface, props, plants and the
## rear courtyard) would otherwise stay dark and look pasted on. An additive
## cool wash on this layer (z 1: below the perimeter gates and every actor,
## which take the flash in their own shaders) lifts them, strongest under the
## bolt and fading upward into the backdrop. The bunker's rooms below the
## roof slab and the ground below its first rows stay out of it. Drawn only
## on the few frames of a flash; fixed vertex buffers, no allocation.
func _draw_flash_wash() -> void:
	if flash <= .004 or _reduced or not is_instance_valid(bunker): return
	var ground := float(bunker.ground_y)
	var left := float(bunker.room_left) + 4.0
	var right := float(bunker.room_right) - 4.0
	var roof := float(ScenarioBunker.ROOF_Y) + 3.0
	var margin := _view.size.x * .15 + WASH_STRIP
	var x := floorf((_view.position.x - margin) / WASH_STRIP) * WASH_STRIP
	var end := _view.end.x + margin
	var offset := glow_layer.to_local(Vector2.ZERO)
	while x < end:
		var next := x + WASH_STRIP
		if x < left: _wash_piece(x, minf(next, left), ground + WASH_GROUND, ground, offset)
		if next > left and x < right: _wash_piece(maxf(x, left), minf(next, right), roof, ground, offset)
		if next > right: _wash_piece(maxf(x, right), next, ground + WASH_GROUND, ground, offset)
		x = next

func _wash_alpha(x: float) -> float:
	var near := 1.0 - smoothstep(0.0, 1100.0, absf(x - flash_x))
	# The ambient multiplies this layer too; the bolt is as bright by night.
	var gain := 1.0 / maxf(.7, luminance(canvas_modulate.color))
	return minf(.35, FLASH_WASH * flash * lerpf(WASH_FAR, 1.0, near) * gain)

## One vertical strip of the wash from WASH_HEIGHT above the ground line down
## to `bottom`: a ramp in from transparent, the full body, a short fade into
## the surface it ends on.
func _wash_piece(from: float, to: float, bottom: float, ground: float, offset: Vector2) -> void:
	if to - from < .5: return
	var a := _wash_alpha(from)
	var b := _wash_alpha(to)
	var top := ground - WASH_HEIGHT
	var span := WASH_HEIGHT - WASH_FULL
	var body := minf(ground - WASH_FULL, bottom - 4.0)
	var body_share := clampf((body - top) / span, 0.0, 1.0)
	var lip := bottom - 4.0
	var lip_share := clampf((lip - top) / span, 0.0, 1.0)
	_wash_band(from, to, top, body, a, b, 0.0, body_share, offset)
	_wash_band(from, to, body, lip, a, b, body_share, lip_share, offset)
	_wash_band(from, to, lip, bottom, a, b, lip_share, lip_share * .35, offset)

func _wash_band(from: float, to: float, upper_y: float, lower_y: float, a: float, b: float, upper: float, lower: float, offset: Vector2) -> void:
	if lower_y - upper_y < .5: return
	_wash_points[0] = offset + Vector2(from, upper_y)
	_wash_points[1] = offset + Vector2(to, upper_y)
	_wash_points[2] = offset + Vector2(to, lower_y)
	_wash_points[3] = offset + Vector2(from, lower_y)
	_wash_colors[0] = Color(FLASH_TINT.r, FLASH_TINT.g, FLASH_TINT.b, a * upper)
	_wash_colors[1] = Color(FLASH_TINT.r, FLASH_TINT.g, FLASH_TINT.b, b * upper)
	_wash_colors[2] = Color(FLASH_TINT.r, FLASH_TINT.g, FLASH_TINT.b, b * lower)
	_wash_colors[3] = Color(FLASH_TINT.r, FLASH_TINT.g, FLASH_TINT.b, a * lower)
	glow_layer.draw_polygon(_wash_points, _wash_colors)

## Daylight (or moonlight, or a lightning flash) falling through the roof
## hatches into the surface room, leaning away from the backdrop's key light.
func _draw_hatch_light() -> void:
	if not is_instance_valid(bunker) or not bool(bunker.get("_bootstrapped")): return
	var roof := float(ScenarioBunker.ROOF_Y)
	var floor_y := float(bunker.ground_y)
	var strength := lerpf(.11, .05, night) * lerpf(1.0, .6, storm) + flash * .28
	if strength <= .005: return
	var tint := world_hue.lerp(FLASH_TINT, clampf(flash * 1.5, 0.0, 1.0))
	var lean := -key_side * 46.0
	for passage: Variant in bunker.get("passages"):
		if not is_instance_valid(passage): continue
		var hole: Rect2 = (passage as Node).call("aperture")
		if absf(hole.position.y - roof) > 1.0: continue
		var top := glow_layer.to_local(Vector2(hole.position.x + 3.0, hole.end.y)).round()
		var width := hole.size.x - 6.0
		_shaft_points[0] = top
		_shaft_points[1] = top + Vector2(width, 0)
		_shaft_points[2] = top + Vector2(roundf(width + 22.0 + lean), floor_y - hole.end.y)
		_shaft_points[3] = top + Vector2(roundf(-22.0 + lean), floor_y - hole.end.y)
		_shaft_colors[0] = Color(tint.r, tint.g, tint.b, strength)
		_shaft_colors[1] = _shaft_colors[0]
		_shaft_colors[2] = Color(tint.r, tint.g, tint.b, strength * .30)
		_shaft_colors[3] = _shaft_colors[2]
		glow_layer.draw_polygon(_shaft_points, _shaft_colors)

## The ambient actually on the canvas: the world's ambient with the storm
## grade and any lightning flash applied.
func graded_ambient() -> Color:
	return canvas_modulate.color

func diagnostics() -> Dictionary:
	var enabled := 0
	for lamp in lights:
		if lamp.enabled: enabled += 1
	var grades := 0
	for grade in room_grades:
		if grade.visible: grades += 1
	return {"ambient":ambient, "night":night, "pool":lights.size(), "enabled":enabled, "fixtures":fixtures.size(),
		"reduced":_reduced, "excluded":_excluded, "updates":light_updates, "shadows":shadows.diagnostics(),
		"room_grades":grades, "actor_key":actor_key.enabled, "actors_marked":actors_marked, "storm":storm, "flash":flash, "flashes":flashes}
