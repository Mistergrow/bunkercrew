extends RefCounted
## Authored side-view modules share one pixel-coverage shader. All source regions
## retain their aspect ratio; moving panels crop through their fixed guide base.
const ATLAS=preload("res://assets/perimeter/components_v2.png")
const COMPACT=preload("res://assets/perimeter/components_v3.png")
const C=preload("res://scripts/perimeter_catalog.gd")
const PIXEL_SHADER=preload("res://shaders/perimeter_pixel.gdshader")
const COURTYARD=preload("res://scripts/courtyard_art_catalog.gd")
const INK=Color("202a2a")
const EDGE=Color("a9b0a0")
const GATES={
	1:{"region":Rect2(121,94,239,374),"leaf":Rect2(145,111,97,306)},
	2:{"region":Rect2(504,88,240,380),"leaf":Rect2(529,112,101,303)},
	3:{"region":Rect2(852,85,255,383),"leaf":Rect2(879,109,101,306)},
}
const BASES=[Rect2(27,211,348,175),Rect2(413,211,353,175)]
const HEAD=Rect2(808,193,351,181)
const HEAD_ANCHOR=Vector2(876,329)
const HEAD_SCALE=45.0/282.0
const WRECK=Rect2(1171,716,346,216)
static var _pixel_material: ShaderMaterial

static func pixel_material() -> ShaderMaterial:
	if _pixel_material==null:
		_pixel_material=ShaderMaterial.new()
		_pixel_material.shader=PIXEL_SHADER
	return _pixel_material

static func _paint(node: CanvasItem,region: Rect2,at: Vector2,pixel_scale: float,tint: Color=Color.WHITE) -> void:
	if not region.has_area(): return
	node.draw_texture_rect_region(ATLAS,Rect2(at,region.size*pixel_scale),region,tint)

static func _condition(site: Node2D) -> Color:
	var health:=clampf(site.hp/maxf(1,site.max_hp),0,1)
	var tint:=Color.WHITE.lerp(Color(.78,.76,.70),1-health)
	if site.hit_flash>0: tint=tint.lightened(.16)
	return tint

static func draw_site(site: Node2D) -> void:
	site.draw_rect(Rect2(-38,-1,76,3),Color(0,0,0,.25))
	if site.tier==0:
		_empty(site)
		return
	if site.role=="fence": _fence(site)
	else: _tower(site)
	if site.hp<site.max_hp or site.cure>0:
		var top: float=-82 if site.role=="fence" else -63
		Art.bar(site,Rect2(-24,top,48,3),site.hp/maxf(1,site.max_hp),Art.AMBER if site.cure>0 else Art.RED)
	if site.work>0:
		Art.bar(site,Rect2(-22,-15,44,3),site.work/float(site.next_spec().time),Art.CYAN)

static func _empty(site: Node2D) -> void:
	if site.ruined:
		if site.role=="fence":
			# Torn mesh stays low enough to clear the nearby gun's firing lane.
			var rubble_size:=COURTYARD.module_size(COURTYARD.RUBBLE,15.0)
			site.draw_texture_rect_region(COURTYARD.ATLAS,Rect2(Vector2(-rubble_size.x*.5,-rubble_size.y),rubble_size),COURTYARD.RUBBLE,_condition(site))
		else:
			var pixel_scale:=68.0/WRECK.size.x
			_paint(site,WRECK,Vector2(-34,-WRECK.size.y*pixel_scale),pixel_scale)
	else:
		for x in [-26,24]:
			site.draw_rect(Rect2(x,-11,3,11),INK)
			site.draw_rect(Rect2(x+1,-10,1,8),Color("928b6d"))
		for index in 6: site.draw_rect(Rect2(-23+index*9,-2,4,1),Color("929581"))
	var count:=0
	for value in site.materials.values(): count+=int(value)
	for index in mini(count,6):
		site.draw_rect(Rect2(-20+index*7,-9,6,5),Color("53645b"))
		site.draw_rect(Rect2(-19+index*7,-9,4,1),EDGE)

static func _fence(site: Node2D) -> void:
	var spec: Dictionary=GATES[site.tier]
	var region: Rect2=spec.region
	var leaf: Rect2=spec.leaf
	var pixel_scale:=70.0/region.size.y
	var origin:=Vector2(-region.size.x*pixel_scale*.5,-70)
	var tint:=_condition(site)
	# The diagonal heel leans toward the bunker, away from the approaching enemy.
	site.draw_set_transform(Vector2.ZERO,0,Vector2(-float(site.side),1))
	var strips: Array[Rect2]=[
		Rect2(region.position,Vector2(region.size.x,leaf.position.y-region.position.y)),
		Rect2(Vector2(region.position.x,leaf.position.y),Vector2(leaf.position.x-region.position.x,leaf.size.y)),
		Rect2(Vector2(leaf.end.x,leaf.position.y),Vector2(region.end.x-leaf.end.x,leaf.size.y)),
		Rect2(Vector2(region.position.x,leaf.end.y),Vector2(region.size.x,region.end.y-leaf.end.y)),
	]
	for strip in strips:
		_paint(site,strip,origin+(strip.position-region.position)*pixel_scale,pixel_scale,tint)
	# The moving leaf descends through its guide. Its original pixel spacing is
	# constant: the part below the base is clipped rather than squeezed smaller.
	var descent:=roundf(leaf.size.y*clampf(site.gate_amount,0,1))
	var leaf_tint:=tint.darkened(.17) if site.cure>0 else tint
	# The reinforced opening belongs to the moving insert. Source pixels keep
	# their native pitch while both solid sections descend into the guide base.
	var port_top:=region.position.y+(C.FENCE_PORT_TOP+70.0)/pixel_scale
	var port_bottom:=region.position.y+(C.FENCE_PORT_BOTTOM+70.0)/pixel_scale
	for section: Rect2 in [Rect2(leaf.position,Vector2(leaf.size.x,port_top-leaf.position.y)),Rect2(Vector2(leaf.position.x,port_bottom),Vector2(leaf.size.x,leaf.end.y-port_bottom))]:
		section.size.y=minf(section.size.y,leaf.end.y-descent-section.position.y)
		_paint(site,section,origin+(section.position-region.position+Vector2(0,descent))*pixel_scale,pixel_scale,leaf_tint)
	# Existing steel texture caps the cut edges; attached to the leaf, never a
	# screen-space black rectangle or a free-floating vector door handle.
	var trim:=Rect2(879,109,101,9)
	for edge_y: float in [port_top-9,port_bottom]:
		if edge_y+descent+9<=leaf.end.y:
			_paint(site,trim,origin+Vector2(leaf.position.x-region.position.x,edge_y-region.position.y+descent)*pixel_scale,pixel_scale,tint)
	site.draw_set_transform(Vector2.ZERO)

static func _tower(site: Node2D) -> void:
	var region: Rect2=BASES[clampi(site.slot_index%3,0,1)]
	var pixel_scale:=52.0/region.size.x
	site.draw_set_transform(Vector2.ZERO,0,Vector2(-float(site.side),1))
	site.draw_texture_rect_region(COMPACT,Rect2(Vector2(-26,-region.size.y*pixel_scale),region.size*pixel_scale),region,_condition(site))
	site.draw_set_transform(Vector2.ZERO)

static func draw_barrel(site: Node2D) -> void:
	if site.tier==0 or site.role=="fence": return
	var barrel: Node2D=site.barrel
	barrel.draw_texture_rect_region(COMPACT,Rect2((HEAD.position-HEAD_ANCHOR)*HEAD_SCALE-Vector2(site.recoil,0),HEAD.size*HEAD_SCALE),HEAD,_condition(site))
	WeaponEffectArt.muzzle(barrel,C.MUZZLE-Vector2(site.recoil,0),site.flash,.085,1,.65,site.shot_serial,WeaponEffectArt.reduced(site.game))
