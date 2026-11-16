class_name WeaponEffectArt
extends RefCounted
## Shared pixel silhouettes for the actual articulated weapon mouths. These
## helpers only draw: recoil, ammunition and swept damage stay with each gun.

static func reduced(game: Node) -> bool:
	return is_instance_valid(game) and "weather" in game and is_instance_valid(game.weather) and game.weather.reduced_effects

static func recover_recoil(value: float, delta: float, rate: float = 18.0) -> float:
	var remaining := maxf(0.0,value)*exp(-maxf(0.0,delta)*rate)
	return 0.0 if remaining<0.04 else remaining

const STRUCK := Color(1.16,1.13,1.07)
const STRUCK_FADE := Color(1.07,1.05,1.02)
## Silhouette flash of a struck machine or soldier; workers flash red.
const STRUCK_RIM := Color(1.0,.95,.80)
const HURT_RIM := Color(1.0,.40,.30)

static func hit_tint(hit_flash: float, quiet: bool = false) -> Color:
	## One hit read for every enemy class from its replicated 0.2 s hit timer:
	## a mild lift that keeps every texel of detail (no flat fill); the flash
	## itself is the silhouette rim from strike().
	if hit_flash > .13: return STRUCK_FADE if quiet else STRUCK
	return STRUCK_FADE if hit_flash > .08 and not quiet else Color.WHITE

static func strike_rim(hit_flash: float, quiet: bool = false, rim: Color = STRUCK_RIM) -> Color:
	## Instance value for the actor shader's `struck` rim: full for the first
	## frames of the 0.2 s timer, half for the next, then off. Reduced effects
	## keep only the half-strength first step.
	if hit_flash > .13: return Color(rim,.5 if quiet else 1.0)
	if hit_flash > .08 and not quiet: return Color(rim,.5)
	return Color(rim,0.0)

static func strike(item: CanvasItem, hit_flash: float, quiet: bool = false, rim: Color = STRUCK_RIM, lift: bool = true) -> void:
	## Shows the hit on one actor part: silhouette rim (actor_wet.gdshader) and
	## the mild hit_tint() lift. Writes the instance value only when it changes.
	if not is_instance_valid(item): return
	if lift: item.modulate = hit_tint(hit_flash,quiet)
	var value := strike_rim(hit_flash,quiet,rim)
	var current: Variant = item.get_instance_shader_parameter(&"struck")
	if current == null and value.a <= 0.0: return
	if current is Color and current == value: return
	item.set_instance_shader_parameter(&"struck",value)

static func hit_pop(hit_flash: float, quiet: bool = false) -> float:
	## Tiny visual-only swell on the first frames of a hit; never on collision.
	return 1.0 if quiet or hit_flash <= .15 else 1.0+.05*(hit_flash-.15)/.05

const SEEN := &"muzzle_seen"
const EMBER := Color("d9582a")
const AMBER := Color("f5a648")
const HOT := Color("fff0b9")
const WHITE := Color("fffdf0")
const COLD_EMBER := Color("5a78c8")
const COLD_AMBER := Color("abbed8")
const COLD_HOT := Color("e0f6f0")
static var _petal := PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
const PixelArt := preload("res://scripts/pixel_effect_art.gd")

static func _draw_petal(node: CanvasItem, tip: Vector2, facing: float, angle: float, length: float, width: float, color: Color, grid: bool = false) -> void:
	# A teardrop on whole pixels; the reused buffer keeps sustained fire free of
	# per-frame allocations. On a grid layer it is rasterised per world texel,
	# so a turned barrel's flash steps like the rest of the art.
	if length < 2.0 or width < 1.0: return
	var forward := Vector2.from_angle(angle)
	var mirror := Vector2(facing,1)
	if grid:
		PixelArt.grid_petal(node,tip+(forward*-1.0)*mirror,tip+(forward*length)*mirror,width,color)
		return
	var side := forward.orthogonal()*width*.5
	_petal[0] = (tip+(forward*-1.0)*mirror).round()
	_petal[1] = (tip+(forward*length*.30+side)*mirror).round()
	_petal[2] = (tip+(forward*length)*mirror).round()
	_petal[3] = (tip+(forward*length*.30-side)*mirror).round()
	if _petal[1] == _petal[3] or _petal[0] == _petal[2]:
		node.draw_line(_petal[0],_petal[2],color,1,false)
		return
	node.draw_colored_polygon(_petal,color)

static func _layered_petal(node: CanvasItem, tip: Vector2, facing: float, angle: float, length: float, width: float, stage: int, alpha: float, electric: bool, grid: bool = false) -> void:
	# stage 2: ignition with a white-hot heart, 1: burning, 0: dying ember.
	_draw_petal(node,tip,facing,angle,length,width,Color(COLD_EMBER if electric else EMBER,alpha),grid)
	if stage >= 1: _draw_petal(node,tip,facing,angle,length*.76,width*.64,Color(COLD_AMBER if electric else AMBER,alpha),grid)
	if stage >= 2: _draw_petal(node,tip,facing,angle,length*.50,maxf(1.0,width*.34),Color(COLD_HOT if electric else HOT,alpha),grid)

static func muzzle(node: CanvasItem, tip: Vector2, remaining: float, duration: float, facing: float = 1.0, strength: float = 1.0, tick: int = 0, quiet: bool = false, electric: bool = false, via: Transform2D = Transform2D.IDENTITY) -> void:
	## Layered pixel flash at a weapon mouth. `via` is the draw transform the
	## caller has set on `node` (identity when it draws in plain node space).
	if remaining<=0 or duration<=0: return
	var feel: Node2D = null
	if not quiet and node.is_inside_tree(): feel = preload("res://scripts/combat_feel.gd").of(node)
	var seen: Vector2 = node.get_meta(SEEN,Vector2(-1,0))
	if feel != null and (int(seen.x)!=tick or remaining>seen.y+.02):
		# A replicated shot counter or a restarted flash timer is one discharge:
		# the same on host and guests. Light, smoke and kick hang on this edge.
		var world: Transform2D = node.get_global_transform()*via
		feel.shot(node,world*tip,world.basis_xform(Vector2(facing,0)).normalized(),strength,electric,duration,tick,facing)
	node.set_meta(SEEN,Vector2(tick,remaining))
	# In a game the flash is emissive: the shared unlit layer draws and animates
	# it above the night ambient. Without one it is drawn right here.
	if feel != null and feel.track(node,tip,via): return
	draw_flash(node,tip,clampf(remaining/duration,0,1),facing,strength,tick,quiet,electric)

## Size of every muzzle flash relative to its family's authored tongues.
const FLASH_SCALE := 1.3

static func draw_flash(node: CanvasItem, tip: Vector2, life: float, facing: float, strength: float, tick: int, quiet: bool, electric: bool, grid: bool = false) -> void:
	## grid: `node` carries PixelEffectArt.grid_material(), so the tongues are
	## drawn as texel-grid shapes (the shared flash layer of combat_feel.gd).
	# Ignition for the first third, a burning body, then a short ember: the
	# white heart lives two to three frames at 60 FPS.
	var stage := 2 if life>.62 else (1 if life>.28 else 0)
	# FLASH_SCALE: the flashes read at the game's zoom, a third larger than
	# the barrel-sized tongues they were, each family keeping its shape.
	var size := sqrt(strength)*FLASH_SCALE*(0.62 if quiet else 1.0)*(1.0 if stage==2 else (.80 if stage==1 else .48))
	var alpha := 1.0 if stage>0 else smoothstep(0.0,.28,life)*.85+.15
	var vary := 1.0+float(tick%3)*.13
	var lean := .10 if tick%2==0 else -.10
	if strength>=1.1:
		# Cannon class: a long lance with muzzle-brake jets to both sides.
		if not quiet:
			_layered_petal(node,tip,facing,PI*.5+lean,18.0*size,7.0*size,stage,alpha,electric,grid)
			_layered_petal(node,tip,facing,-PI*.5+lean,(18.0-float(tick%3)*2.0)*size,7.0*size,stage,alpha,electric,grid)
			if stage>0:
				_layered_petal(node,tip,facing,.62,13.0*size,5.0*size,stage,alpha,electric,grid)
				_layered_petal(node,tip,facing,-.62,13.0*size,5.0*size,stage,alpha,electric,grid)
		_layered_petal(node,tip,facing,0.0,44.0*size*vary,10.0*size,stage,alpha,electric,grid)
	elif strength>=.9:
		# Shotgun class: a broad bloom of three tongues.
		if not quiet:
			_layered_petal(node,tip,facing,.42+lean,23.0*size,9.0*size,stage,alpha,electric,grid)
			_layered_petal(node,tip,facing,-.42+lean,23.0*size*vary,9.0*size,stage,alpha,electric,grid)
			if stage>0:
				_layered_petal(node,tip,facing,1.25,9.0*size,5.0*size,stage,alpha,electric,grid)
				_layered_petal(node,tip,facing,-1.25,9.0*size,5.0*size,stage,alpha,electric,grid)
		_layered_petal(node,tip,facing,0.0,32.0*size*vary,11.0*size,stage,alpha,electric,grid)
	else:
		# Rifle class: a narrow spike with two short uneven side flames.
		if not quiet and stage>0:
			_layered_petal(node,tip,facing,.92+lean,13.0*size*vary,6.0*size,stage,alpha,electric,grid)
			_layered_petal(node,tip,facing,-.92+lean,(13.0-float(tick%3)*2.0)*size,6.0*size,stage,alpha,electric,grid)
		_layered_petal(node,tip,facing,0.0,31.0*size*vary,8.0*size,stage,alpha,electric,grid)
	if electric:
		# The cold family keeps a forked discharge instead of a powder heart.
		var reach := 22.0*size
		for sign_side: float in [1.0,-1.0]:
			var bend := tip+Vector2(facing*reach*.35,sign_side*3.0)
			var kink := tip+Vector2(facing*reach*.6,-sign_side*2.0)
			var end := tip+Vector2(facing*reach,sign_side*5.0)
			if grid:
				PixelArt.grid_line(node,tip,bend,Color(COLD_HOT,alpha))
				PixelArt.grid_line(node,bend,kink,Color(COLD_HOT,alpha))
				PixelArt.grid_line(node,kink,end,Color(COLD_HOT,alpha))
			else:
				node.draw_polyline(PackedVector2Array([tip.round(),bend.round(),kink.round(),end.round()]),Color(COLD_HOT,alpha),1,false)
	if stage==2 and not quiet and not electric:
		# Ignition star: short hot spikes across the bore for the first frames,
		# the stepped four-point flare of a pixel-art discharge.
		var spike := (6.0 if strength<.9 else (8.0 if strength<1.1 else 11.0))*size
		_draw_petal(node,tip+Vector2(facing*3.0,0),facing,PI*.5,spike,2.0,Color(HOT,alpha),grid)
		_draw_petal(node,tip+Vector2(facing*3.0,0),facing,-PI*.5,spike,2.0,Color(HOT,alpha),grid)
	if stage==2 and not quiet:
		var heart := 3.0 if strength<1.1 else 4.0
		if grid:
			PixelArt.grid_line(node,tip+Vector2(facing*(2.0-heart*.5),0),tip+Vector2(facing*(2.0+heart*.5),0),WHITE,heart)
		else:
			node.draw_rect(Rect2((tip+Vector2(facing*2.0,0)-Vector2(heart,heart)*.5).round(),Vector2(heart,heart)),WHITE)

static func tracer(node: CanvasItem, direction: Vector2, length: float, quiet: bool = false, heavy: bool = false) -> void:
	## Tapered streak with a hot head. The dark under-stroke keeps it legible
	## in front of bright skies, the pale head in front of dark ones. Tracers
	## glow (the projectile leaves the ambient and point lights) and step in
	## world texels like the actors they fly past.
	if length<=0.0: return
	if node.material==null: node.material = PixelArt.grid_material(PixelArt.GRID_UNLIT)
	var tail := -direction*length
	var body := 3.0 if heavy else 2.0
	var head := body+1.0
	if node.material != PixelArt.grid_material(PixelArt.GRID_UNLIT):
		if length>4.0:
			node.draw_line(tail*.62,Vector2.ZERO,Color(.13,.06,.04,.50 if quiet else .62),body+2.0,false)
			node.draw_line(tail,tail*.5,Color(.91,.50,.22,.70),1,false)
			node.draw_line(tail*.58,Vector2.ZERO,Color("ee9a42"),body,false)
		node.draw_line(-direction*minf(length,9.0 if heavy else 7.0),Vector2.ZERO,Color("ffe9ad"),body,false)
		node.draw_rect(Rect2((-direction*head*.5-Vector2(head,head)*.5).round(),Vector2(head,head)),Color("fffbe8"))
		return
	if length>4.0:
		PixelArt.grid_line(node,tail*.62,Vector2.ZERO,Color(.13,.06,.04,.50 if quiet else .62),body+2.0)
		PixelArt.grid_line(node,tail,tail*.5,Color(.91,.50,.22,.70),1.0)
		PixelArt.grid_line(node,tail*.58,Vector2.ZERO,Color("ee9a42"),body)
	PixelArt.grid_line(node,-direction*minf(length,9.0 if heavy else 7.0),Vector2.ZERO,Color("ffe9ad"),body)
	PixelArt.grid_line(node,-direction*head,Vector2.ZERO,Color("fffbe8"),head)
