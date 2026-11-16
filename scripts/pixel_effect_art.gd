extends RefCounted
## Small authored pixel silhouettes shared by combat dust and machine exhaust.
## Drawing only: owners retain their lifetime, movement and particle budgets.
const PUFFS := [
	[Vector2(-6,-2),Vector2(-4,-2),Vector2(-4,-4),Vector2(-1,-4),Vector2(-1,-5),Vector2(2,-5),Vector2(2,-3),Vector2(5,-3),Vector2(5,-1),Vector2(6,-1),Vector2(6,2),Vector2(4,2),Vector2(4,4),Vector2(0,4),Vector2(0,5),Vector2(-3,5),Vector2(-3,3),Vector2(-5,3),Vector2(-5,1),Vector2(-6,1)],
	[Vector2(-6,-1),Vector2(-5,-1),Vector2(-5,-3),Vector2(-2,-3),Vector2(-2,-5),Vector2(1,-5),Vector2(1,-4),Vector2(4,-4),Vector2(4,-2),Vector2(6,-2),Vector2(6,1),Vector2(5,1),Vector2(5,3),Vector2(2,3),Vector2(2,5),Vector2(-1,5),Vector2(-1,4),Vector2(-4,4),Vector2(-4,2),Vector2(-6,2)],
	[Vector2(-6,-3),Vector2(-3,-3),Vector2(-3,-5),Vector2(0,-5),Vector2(0,-4),Vector2(3,-4),Vector2(3,-2),Vector2(5,-2),Vector2(5,0),Vector2(6,0),Vector2(6,3),Vector2(3,3),Vector2(3,5),Vector2(0,5),Vector2(0,4),Vector2(-3,4),Vector2(-3,2),Vector2(-5,2),Vector2(-5,0),Vector2(-6,0)],
]
const SHOCK_RADIUS := [.91,1.03,.98,1.11,.88,1.02,.95,1.07,.90,1.04,.97,1.09]

static func puff(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, detail: bool = true) -> void:
	if radius <= 0.0 or color.a <= 0.0: return
	var point := center.round()
	if radius < 2.5:
		node.draw_rect(Rect2(point-Vector2.ONE,Vector2(2,2)),color)
		return
	var shape := PackedVector2Array()
	for corner: Vector2 in PUFFS[posmod(variant,PUFFS.size())]:
		var vertex := (point+corner*(radius/6.0)).round()
		if shape.is_empty() or shape[-1] != vertex: shape.append(vertex)
	node.draw_colored_polygon(shape,color)
	if not detail: return
	# Sparse opaque-looking facets within a transparent silhouette, aligned to
	# the same pixel grid as armor and stone. No circular soft brush overlays.
	var fleck := Vector2(maxf(1.0,roundf(radius*.58)),maxf(1.0,roundf(radius*.22)))
	node.draw_rect(Rect2((point+Vector2(-radius*.42,-radius*.47)).round(),fleck),Color(color.lightened(.12),color.a*.32))
	node.draw_rect(Rect2((point+Vector2(radius*.06,radius*.28)).round(),fleck),Color(color.darkened(.22),color.a*.30))

static func glow(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	# Several smaller patches keep an explosion's halo granular at world scale;
	# stretching one tiny silhouette would create conspicuous giant pixel blocks.
	var offsets: Array[Vector2] = [Vector2(-.30,-.12),Vector2(.13,-.24),Vector2(.25,.19)]
	for index in offsets.size():
		puff(node,center+offsets[index]*radius,radius*.38,Color(color,color.a*.70),variant+index,false)
	puff(node,center,radius*.28,Color(color,color.a*1.10),variant+1,false)

static func shockwave(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	if radius <= 0.0 or color.a <= 0.0: return
	# Broken, uneven pressure fronts keep the impact readable without a smooth
	# UI-like circular outline floating over the world.
	for index in 6:
		var angle := float(index)*TAU/6.0+float(posmod(variant,3))*.19
		var first: Vector2 = center+Vector2.from_angle(angle)*radius*SHOCK_RADIUS[index*2]
		var middle: Vector2 = center+Vector2.from_angle(angle+.21)*radius*SHOCK_RADIUS[index*2+1]
		var last: Vector2 = center+Vector2.from_angle(angle+.42)*radius*SHOCK_RADIUS[(index*2+2)%SHOCK_RADIUS.size()]
		node.draw_polyline(PackedVector2Array([first.round(),middle.round(),last.round()]),color,1.0,false)

const BLOB_EDGE := [0.0,-.10,.06,-.04,.11,-.08,.03,.09,-.12,.05,-.02,.08,-.07,.10,-.05,.02]

static func blob(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, thin: float = 0.0) -> void:
	# A large rounded mass built from two-pixel rows with an uneven edge. Unlike
	# puff() it keeps native pixel granularity at fireball and smoke-column size.
	# thin 0..1 removes that share of its rows.
	if radius <= 0.0 or color.a <= 0.004: return
	if radius < 5.0:
		puff(node,center,radius,color,variant,false)
		return
	var origin := (center*.5).round()*2.0
	var rows := int(radius*.5)
	for row in range(-rows,rows):
		var y := (float(row)+.5)*2.0
		var chord := sqrt(maxf(0.0,radius*radius-y*y))
		var left := roundf(-chord*(1.0+float(BLOB_EDGE[posmod(row*3+variant*5,16)]))*.5)*2.0
		var right := roundf(chord*(1.0+float(BLOB_EDGE[posmod(row*5+variant*7+3,16)]))*.5)*2.0
		if right-left < 2.0: continue
		# Dissolve by dropping whole pixel rows instead of a soft alpha ramp.
		if thin > 0.0 and float(posmod(row*7+variant*3,8)) < thin*8.0: continue
		node.draw_rect(Rect2(origin.x+left,origin.y+float(row)*2.0,right-left,2.0),color)

static var _additive: CanvasItemMaterial

static func additive_material() -> CanvasItemMaterial:
	# One shared unlit additive material for every hot effect layer.
	if _additive == null:
		_additive = CanvasItemMaterial.new()
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _additive

static var _unlit: CanvasItemMaterial

static func unlit_material() -> CanvasItemMaterial:
	# Normal blending without ambient or point lights, for small self-lit bits.
	if _unlit == null:
		_unlit = CanvasItemMaterial.new()
		_unlit.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	return _unlit

## Grid shapes: one quad per shape, rasterised by shaders/pixel_effect_grid*.
## Silhouettes step in whole world texels (the size of an actor texel) at any
## camera zoom and dissolve texel by texel in a 4x4 ordered-dither order. The
## drawing node must carry grid_material(); its other drawing passes through.
const GRID_LIT := "lit"
const GRID_UNLIT := "unlit"
const GRID_ADD := "add"
static var _grid_materials: Dictionary = {}
# One reused quad: drawing copies it, so no per-shape allocation in _draw().
static var _quad_points := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
static var _quad_colors := PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
static var _quad_uvs := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
const _CORNERS := [Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]

## True when `node` draws through a shader that rasterises grid shapes (the
## grid layers and the actor material); other nodes keep the polygon helpers.
const GRID_SHADERS := ["res://shaders/pixel_effect_grid.gdshader", "res://shaders/pixel_effect_grid_unlit.gdshader", "res://shaders/pixel_effect_grid_add.gdshader", "res://shaders/actor_wet.gdshader", "res://shaders/actor_wreck.gdshader"]

static func supports_grid(node: CanvasItem) -> bool:
	var surface := node.material as ShaderMaterial
	return surface != null and surface.shader != null and GRID_SHADERS.has(surface.shader.resource_path)

## A small drifting smoke puff on the grid where the node supports it, the
## polygon puff() elsewhere. age 0..1 tears it into dithered wisps as it rises.
static func smoke_puff(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int, age: float, warmth: float = 0.0, shear: float = 0.0) -> void:
	if supports_grid(node):
		grid_smoke(node,center,maxf(radius,1.5),Color(smoke_tone(color),clampf(color.a*1.5,.4,.92)),variant,smoothstep(.18,1.0,age),warmth,shear)
	else:
		puff(node,center,radius,color,variant,false)

## The sky of the current world tints all smoke a little (smoke_tone), so a
## plume over a frozen yard reads cold and one over a canyon warm instead of
## the same neutral grey everywhere. Set once per world from its catalog sky.
static var _sky_hue := Color(1,1,1)
static var _night_lift := 1.0
static var _night := 0.0

## sky: the catalog sky key; ambient: the world's ambient (WorldLighting). A
## dark ambient lifts smoke values so a night plume still reads lighter than
## the painted night sky (fires and the city glow light it), and turns up the
## additive fire glow, which daylight would wash out.
static func set_atmosphere(sky: Color, ambient: Color = Color.WHITE) -> void:
	var peak := maxf(.001,maxf(sky.r,maxf(sky.g,sky.b)))
	var hue := Color(sky.r/peak,sky.g/peak,sky.b/peak)
	# Equal luminance: the tint moves hue, never the value of the smoke.
	var light := maxf(.05,hue.r*.299+hue.g*.587+hue.b*.114)
	_sky_hue = Color(hue.r/light,hue.g/light,hue.b/light)
	var level := clampf(ambient.r*.299+ambient.g*.587+ambient.b*.114,.2,1.0)
	_night_lift = clampf(pow(1.0/level,.52),1.0,1.7)
	_night = clampf((1.0-level)/.56,0.0,1.0)

## 0 in daylight, 1 under the darkest night ambient.
static func night() -> float:
	return _night

## Reads the sky of the world a game is showing (scenario options), neutral
## when there is none (menus, stubs, galleries).
static func atmosphere_from(game: Node) -> void:
	var sky := Color(.8,.8,.8)
	var ambient := Color.WHITE
	if is_instance_valid(game):
		var options: Variant = game.get("scenario_options")
		if options is Dictionary and (options as Dictionary).has("environment"):
			var data: Dictionary = ScenarioCatalog.environment(str(options.environment))
			sky = Color(str(data.get("sky_color","#cccccc")))
			ambient = load("res://scripts/world_lighting.gd").ambient_for(data)
	set_atmosphere(sky,ambient)

static func smoke_tone(base: Color, share: float = .30) -> Color:
	var tinted := Color(base.r*_sky_hue.r,base.g*_sky_hue.g,base.b*_sky_hue.b)
	return Color(clampf(lerpf(base.r,tinted.r,share)*_night_lift,0.0,1.0),clampf(lerpf(base.g,tinted.g,share)*_night_lift,0.0,1.0),clampf(lerpf(base.b,tinted.b,share)*_night_lift,0.0,1.0),base.a)

## Horizontal wind at a point of the world a node belongs to (px/s), 0
## without weather or with reduced effects. Sample it once per effect.
static func wind_x(game: Node, at: Vector2) -> float:
	if not is_instance_valid(game): return 0.0
	var weather: Variant = game.get("weather")
	if not is_instance_valid(weather) or weather.get("reduced_effects") == true or not weather.has_method("wind_at"): return 0.0
	var wind: Variant = weather.wind_at(at)
	return clampf(float(wind.x),-160.0,160.0) if wind is Vector2 else 0.0

static func grid_material(kind: String = GRID_LIT) -> ShaderMaterial:
	if not _grid_materials.has(kind):
		var path := "res://shaders/pixel_effect_grid%s.gdshader" % ("_unlit" if kind == GRID_UNLIT else "_add" if kind == GRID_ADD else "")
		var result := ShaderMaterial.new()
		result.shader = load(path)
		_grid_materials[kind] = result
	return _grid_materials[kind]

## One quad spanning center +- axis_x +- axis_y; the shader evaluates the shape
## in that frame at every world texel centre it covers. level 0..15 is the
## shape's own parameter (heat, fire light, ring thickness).
static func _grid_quad(node: CanvasItem, center: Vector2, axis_x: Vector2, axis_y: Vector2, color: Color, variant: int, shape: int, thin: float, level: int = 0) -> void:
	if color.a <= 0.004 or thin >= 1.0: return
	_grid_emit(node,center,axis_x,axis_y,color,variant,shape,clampi(int(roundf(clampf(thin,0.0,1.0)*16.0)),0,16),level)

static func _grid_emit(node: CanvasItem, center: Vector2, axis_x: Vector2, axis_y: Vector2, color: Color, variant: int, shape: int, step: int, level: int) -> void:
	var code := Vector2(float(posmod(variant,64)+64*clampi(level,0,15))*4.0,float(16+shape*32+clampi(step,0,31))*4.0)
	for index in 4:
		var corner: Vector2 = _CORNERS[index]
		_quad_points[index] = center+axis_x*corner.x+axis_y*corner.y
		_quad_uvs[index] = code+corner
		_quad_colors[index] = color
	node.draw_primitive(_quad_points,_quad_colors,_quad_uvs)

## blob() on the texel grid; thin 0..1 dissolves that share of its texels.
static func grid_blob(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, thin: float = 0.0) -> void:
	if radius <= 0.0: return
	_grid_quad(node,center,Vector2(radius,0),Vector2(0,radius),color,variant,0,thin)

## grid_blob() with separate horizontal and vertical radii (ground marks).
static func grid_oval(node: CanvasItem, center: Vector2, radii: Vector2, color: Color, variant: int = 0, thin: float = 0.0) -> void:
	if radii.x <= 0.0 or radii.y <= 0.0: return
	_grid_quad(node,center,Vector2(radii.x,0),Vector2(0,radii.y),color,variant,0,thin)

## puff() on the texel grid: a lumpier edge with a lit and a shaded facet.
static func grid_puff(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, thin: float = 0.0) -> void:
	if radius <= 0.0: return
	if radius < 2.5:
		node.draw_rect(Rect2(center.floor()-Vector2.ONE,Vector2(2,2)),color)
		return
	_grid_quad(node,center,Vector2(radius,0),Vector2(0,radius),color,variant,1,thin)

## A straight streak from one texel centre to another, one texel per column or
## row at width 1 (no smooth sub-texel diagonal).
static func grid_line(node: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float = 1.0, thin: float = 0.0) -> void:
	var a := from.floor()+Vector2(.5,.5)
	var b := to.floor()+Vector2(.5,.5)
	var span := b-a
	var length := span.length()
	if length < .5:
		var size := maxf(1.0,roundf(width))
		node.draw_rect(Rect2(from.floor(),Vector2(size,size)),color)
		return
	var along := span/length
	var half := maxf(width*.5,.5*maxf(absf(along.x),absf(along.y)))
	_grid_quad(node,(a+b)*.5,along*(length*.5+.5),along.orthogonal()*half,color,0,2,thin)

## A debris shard: a diamond along `axis` with half-width `side` texels.
static func grid_shard(node: CanvasItem, center: Vector2, axis: Vector2, side: float, color: Color, thin: float = 0.0) -> void:
	var length := axis.length()
	if length < .75:
		node.draw_rect(Rect2(center.floor(),Vector2.ONE),color)
		return
	_grid_quad(node,center.floor()+Vector2(.5,.5),axis+axis/length*.5,axis.orthogonal()/length*maxf(side,.75),color,0,3,thin)

## glow() on the texel grid.
const GLOW_OFFSETS := [Vector2(-.30,-.12),Vector2(.13,-.24),Vector2(.25,.19)]

static func grid_glow(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	for index in GLOW_OFFSETS.size():
		grid_blob(node,center+GLOW_OFFSETS[index]*radius,radius*.38,Color(color,color.a*.70),variant+index)
	grid_blob(node,center,radius*.28,Color(color,color.a*1.10),variant+1)

## Cel-shaded mass for smoke and dust: a bumpy silhouette in three hard tones
## derived from `color` (lit cap, body, shaded crescent, deep rim below), lit
## from the upper left. warmth 0..1 keeps a fire glow on its underside; thin
## tears it apart in clusters, rim first. squash < 1 flattens it (ground dust).
static func grid_cel(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, thin: float = 0.0, warmth: float = 0.0, squash: float = 1.0) -> void:
	if radius <= 0.0: return
	if radius < 2.0:
		node.draw_rect(Rect2(center.floor(),Vector2.ONE),color)
		return
	_grid_quad(node,center,Vector2(radius,0),Vector2(0,radius*squash),color,variant,4,thin,int(roundf(clampf(warmth,0.0,1.0)*15.0)))

## Fire mass on the fixed flame ramp (white, yellow, amber, orange, red, ember);
## heat 1 is a fresh fireball with a white heart, 0 a dying red-black ember.
## Draw it on an unlit or additive grid layer: fire is its own light.
static func grid_fire(node: CanvasItem, center: Vector2, radius: float, heat: float, alpha: float = 1.0, variant: int = 0, thin: float = 0.0) -> void:
	if radius <= 0.0: return
	if radius < 1.5:
		node.draw_rect(Rect2(center.floor(),Vector2.ONE),Color(Color("ffe08a"),alpha))
		return
	_grid_quad(node,center,Vector2(radius,0),Vector2(0,radius),Color(1,1,1,alpha),variant,5,thin,int(roundf(clampf(heat,0.0,1.0)*15.0)))

## Pressure ring: a slightly wobbling annulus `width` texels thick.
static func grid_ring(node: CanvasItem, center: Vector2, radius: float, width: float, color: Color, variant: int = 0, thin: float = 0.0, squash: float = 1.0) -> void:
	if radius < 2.0: return
	var level := int(roundf((clampf(width/radius,0.045,.72)/.045)-1.0))
	_grid_quad(node,center,Vector2(radius,0),Vector2(0,radius*squash),color,variant,6,thin,level)

## Flame tongue from `base` to `tip`, widest a third of the way out.
static func grid_petal(node: CanvasItem, base: Vector2, tip: Vector2, width: float, color: Color) -> void:
	var span := tip-base
	var length := span.length()
	if length < 1.5 or width < .75:
		grid_line(node,base,tip,color)
		return
	_grid_quad(node,(base+tip)*.5,span*.5,span.orthogonal()/length*maxf(width*.5,.6),color,0,7,0.0)

## Smoke on the texel grid: a lobed puff of billows with a lit edge on the sky
## side, a shaded underside, a translucent dithered rim, and warmth 0..1 of
## fire light from below. fade 0..1 tears it into dithered wisps (it does not
## shrink); shear leans its top downwind by that share of the radius. Draw it
## on a lit layer so the world's ambient and the fire lights reach it.
const SHAPE_SMOKE := 8
const SHAPE_FLAME := 9
const SHAPE_HALO := 10

static func grid_smoke(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, fade: float = 0.0, warmth: float = 0.0, shear: float = 0.0, squash: float = 1.0) -> void:
	if radius <= 0.0 or color.a <= 0.004 or fade >= .98: return
	if radius < 1.5:
		if fade < .5: node.draw_rect(Rect2(center.floor(),Vector2.ONE),color)
		return
	# A strong shear turns the round billows into slanted slabs: the lean
	# stays a hint, the drift itself carries the wind.
	_grid_emit(node,center,Vector2(radius,0),Vector2(-clampf(shear,-.16,.16)*radius,radius*squash),color,variant,SHAPE_SMOKE,int(roundf(clampf(fade,0.0,1.0)*31.0)),int(roundf(clampf(warmth,0.0,1.0)*15.0)))

## Flames: a procedural flipbook on the grid, from `base` up to `height`
## texels, `width` texels across, its tip displaced `lean` texels sideways.
## frame steps the 32-frame loop (flame_frame()); heat 0..1 shrinks and
## reddens a dying fire. Draw it on an unlit or additive layer.
const FLAME_FPS := 12.0

static func grid_flame(node: CanvasItem, base: Vector2, width: float, height: float, heat: float, frame: int, variant: int = 0, lean: float = 0.0, alpha: float = 1.0) -> void:
	if height < 1.5 or width < 1.0 or alpha <= 0.004: return
	if height < 3.0:
		node.draw_rect(Rect2(base.floor()-Vector2(0,1),Vector2.ONE),Color(Color("ffb648"),alpha))
		return
	var quad := flame_quad(base,width,height,lean)
	_grid_emit(node,quad.origin,quad.x,quad.y,Color(1,1,1,alpha),variant,SHAPE_FLAME,posmod(frame,32),int(roundf(clampf(heat,0.0,1.0)*15.0)))

## A flame's quad as centre (origin) and half axes (x across, y toward the
## base): its lower edge lies on `base` (a flame never reaches below what
## burns), its tip `lean` texels aside. A value type: no allocation per flame.
static func flame_quad(base: Vector2, width: float, height: float, lean: float) -> Transform2D:
	return Transform2D(Vector2(width*.5,0),Vector2(-lean*.5,height*.5),base+Vector2(lean*.5,-height*.5))

## The flipbook frame for an effect clock; each source offsets its phase.
static func flame_frame(clock: float, phase: int = 0) -> int:
	return floori(clock*FLAME_FPS)+phase*11

## Additive glow in three dithered bands (no smooth gradient); additive layer.
## squash < 1 flattens it (a pool of light on the ground).
static func grid_halo(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0, squash: float = 1.0) -> void:
	if radius < 2.0 or color.a <= 0.004: return
	_grid_emit(node,center,Vector2(radius,0),Vector2(0,radius*squash),color,variant,SHAPE_HALO,0,0)

## shockwave() as stepped texel streaks.
static func grid_shockwave(node: CanvasItem, center: Vector2, radius: float, color: Color, variant: int = 0) -> void:
	if radius <= 0.0 or color.a <= 0.0: return
	for index in 6:
		var angle := float(index)*TAU/6.0+float(posmod(variant,3))*.19
		var first: Vector2 = center+Vector2.from_angle(angle)*radius*SHOCK_RADIUS[index*2]
		var middle: Vector2 = center+Vector2.from_angle(angle+.21)*radius*SHOCK_RADIUS[index*2+1]
		var last: Vector2 = center+Vector2.from_angle(angle+.42)*radius*SHOCK_RADIUS[(index*2+2)%SHOCK_RADIUS.size()]
		grid_line(node,first,middle,color)
		grid_line(node,middle,last,color)
