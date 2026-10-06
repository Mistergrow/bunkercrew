extends RefCounted
## Native pixel geometry for flexible cloth, reeds and machinery. Static
## supports stay fixed while only their exposed moving parts follow the wind.
const SurfaceArt := preload("res://scripts/station_surface_art.gd")
const Industrial := preload("res://scripts/industrial_prop_art.gd")
const Fixture := preload("res://scripts/scenery_fixture_art.gd")

static func wind(time: float,phase: float,strength: float) -> float:
	return (sin(time*.83+phase)*.62+sin(time*1.57+phase*.43)*.25+sin(time*2.31+phase)*.13)*strength

static func draw(canvas: Node2D,entry: Dictionary,time: float,motion: float,strength: float) -> void:
	canvas.draw_set_transform(entry.position)
	var tint: Color = entry.tint
	var accent: Color = entry.accent
	if bool(entry.get("charred",false)):
		tint = tint.darkened(.52)
		accent = accent.darkened(.52)
	elif bool(entry.get("burning",false)):
		tint = tint.darkened(.28)
		accent = accent.darkened(.28)
	var phase: float = entry.phase
	var gust := wind(time,phase,motion*strength)
	var flexible_motion := motion*clampf(strength,.03,1.0)
	match str(entry.kind):
		"windsock": _windsock(canvas,tint,accent,time,phase,gust,motion,strength)
		"fan": _fan(canvas,tint,accent,time,phase,entry.position)
		"cable": _cable(canvas,tint,accent,time,phase,gust)
		"bollard": _bollard(canvas,tint,accent,time,phase,gust)
		"ore_cart": Fixture.cart(canvas,tint,accent,time,phase,gust)
		"tape": _tape(canvas,tint,accent,time,phase,gust,flexible_motion)
		"vines": _vines(canvas,tint,entry.foliage,time,phase,gust,flexible_motion)
		"signal": _signal(canvas,tint,accent,time,phase,gust)
		"pipe": _pipe(canvas,tint,accent,time,phase,gust)
		"grass","frost_grass","reeds","brush": _growth(canvas,str(entry.kind),tint,time,phase,gust,flexible_motion)
		"tree": _fallback_tree(canvas,entry,time,gust)
		"rubble": _rubble(canvas,tint,phase)
		"generator","pump","transformer","relay_antenna","crane_hook","cargo_beacon": Fixture.draw(canvas,entry.kind,tint,accent,time,phase,gust,entry.position,motion)
	canvas.draw_set_transform(Vector2.ZERO)

static func _line(canvas: Node2D,a: Vector2,b: Vector2,color: Color,width: float=1.0) -> void:
	canvas.draw_line(a.round(),b.round(),color,width,false)

static func _poly(canvas: Node2D,points: Array,color: Color) -> void:
	var vertices := PackedVector2Array()
	for point: Vector2 in points: vertices.append(point.round())
	canvas.draw_colored_polygon(vertices,color)

static func _disc(canvas: Node2D,at: Vector2,radius: float,color: Color) -> void:
	var points: Array = []
	for corner in 8: points.append(at+Vector2.from_angle(TAU*corner/8)*radius)
	_poly(canvas,points,color)

static func _post(canvas: Node2D,x: float,height: float,color: Color,width: float=5.0) -> void:
	SurfaceArt.face(canvas,Rect2(x-width*.5,-height,width,height),color.darkened(.16),3)
	SurfaceArt.face(canvas,Rect2(x-7,-5,14,5),color.darkened(.22),2)
	for bolt in [-4,3]:
		canvas.draw_rect(Rect2(x+bolt,-3,2,1),Color("b29f7f"))

static func _windsock(canvas: Node2D,tint: Color,_accent: Color,time: float,phase: float,gust: float,motion: float,strength: float) -> void:
	Industrial.windsock(canvas,tint,time,phase,gust,motion,strength)

static func _fan(canvas: Node2D,tint: Color,accent: Color,time: float,phase: float,origin: Vector2 = Vector2.ZERO) -> void:
	# Cast cabinet, recessed intake and a darker side face share the machinery
	# atlas. The rotor turns inside that recess, behind the fixed safety grid.
	canvas.draw_rect(Rect2(-30,-74,60,74),SurfaceArt.INK)
	SurfaceArt.face(canvas,Rect2(24,-70,6,67),tint.darkened(.32),2)
	SurfaceArt.panel(canvas,Rect2(-28,-72,52,66),tint,3)
	SurfaceArt.face(canvas,Rect2(-30,-74,59,3),tint.lightened(.18),4)
	_line(canvas,Vector2(24,-69),Vector2(24,-6),Color("20251d"))
	var center := Vector2(0,-43)
	_disc(canvas,center,25,Color("1b211b"))
	var rim := PackedVector2Array()
	for corner in 12:
		rim.append((center+Vector2.from_angle(TAU*corner/12.0)*24).round())
	SurfaceArt.polygon(canvas,rim,tint.lightened(.15),5)
	_disc(canvas,center+Vector2(0,1),21,Color("24291f"))
	_disc(canvas,center+Vector2(1,2),19,Color("121a16"))
	var blade_shape := PackedVector2Array([Vector2(3,-2),Vector2(11,-5),Vector2(18,-3),Vector2(18,3),Vector2(15,7),Vector2(6,4)])
	for blade in 4:
		var angle := time*2.8+phase+blade*PI*.5
		canvas.draw_set_transform(origin+center+Vector2(1,2),angle)
		canvas.draw_colored_polygon(blade_shape,Color("0d1512"))
		canvas.draw_set_transform(origin+center,angle)
		SurfaceArt.polygon(canvas,blade_shape,tint.lightened(.09),1)
		_line(canvas,Vector2(5,-2),Vector2(11,-4),Color("a59877"))
		_line(canvas,Vector2(11,-4),Vector2(17,-2),Color("a59877"))
		_line(canvas,Vector2(7,4),Vector2(15,6),Color("313b2b"))
	canvas.draw_set_transform(origin)
	for bar in [-12,0,12]:
		_line(canvas,Vector2(bar+1,-61),Vector2(bar+1,-25),Color("111b15"),2)
		_line(canvas,Vector2(-18,-42+bar),Vector2(18,-42+bar),Color("111b15"),2)
		_line(canvas,Vector2(bar,-61),Vector2(bar,-25),Color("706f57"))
		_line(canvas,Vector2(-18,-43+bar),Vector2(18,-43+bar),Color("706f57"))
	_disc(canvas,center,5,Color("23281e"))
	_disc(canvas,center,3,accent.darkened(.26))
	canvas.draw_rect(Rect2(center+Vector2(-2,-2),Vector2(2,1)),accent.lightened(.3))
	canvas.draw_rect(Rect2(center,Vector2(1,2)),Color("3f3824"))
	for x in [-18,-10,-2,6,14]:
		canvas.draw_rect(Rect2(x,-15,4,5),Color("17211a"))
		canvas.draw_rect(Rect2(x,-10,4,1),Color("85816a"))
	for chip in [Vector2(-27,-28),Vector2(-26,-8),Vector2(18,-69),Vector2(22,-22),Vector2(8,-7)]:
		canvas.draw_rect(Rect2(chip,Vector2(3,2)),Color("765035"))
		canvas.draw_rect(Rect2(chip+Vector2(0,1),Vector2(1,2)),Color("45372a"))
	SurfaceArt.face(canvas,Rect2(-34,-5,68,5),tint.darkened(.1),6)
	for x in [-27,22]:
		canvas.draw_rect(Rect2(x,-3,4,2),Color("3d3528"))
		canvas.draw_rect(Rect2(x,-3,2,1),Color("b29a70"))

static func _cable(canvas: Node2D,tint: Color,_accent: Color,time: float,phase: float,gust: float) -> void:
	Industrial.cable_posts(canvas,tint)
	for wire in 2:
		var previous := Vector2(-42.5+wire*15,-95)
		for segment in range(1,13):
			var t := float(segment)/12
			var point := Vector2(-42.5+wire*15+t*70,-95+sin(t*PI)*(18.0+gust*3)+sin(time*1.8+phase+t*4)*sin(t*PI)*absf(gust)*1.7)
			_line(canvas,previous,point,tint.darkened(.61),2 if wire==0 else 1)
			previous=point

static func _bollard(canvas: Node2D,tint: Color,accent: Color,time: float,phase: float,gust: float) -> void:
	Fixture.bollard(canvas,tint,accent,time,phase,gust)

static func _tape(canvas: Node2D,tint: Color,accent: Color,time: float,phase: float,gust: float,motion: float) -> void:
	for x in [-39,39]: _post(canvas,x,49,tint,4)
	for band in 2:
		var previous := Vector2(-39,-44+band*16)
		for segment in range(1,14):
			var t := float(segment)/13
			var point := Vector2(-39+t*78,-44+band*16+sin(t*PI)*(6+gust*3)+sin(time*3.0+phase-t*9)*sin(t*PI)*2*motion)
			var color := accent if segment%2==0 else tint.darkened(.54)
			_poly(canvas,[previous,point,point+Vector2(0,5),previous+Vector2(0,5)],color)
			previous=point

static func _vines(canvas: Node2D,tint: Color,leaf: Color,time: float,phase: float,gust: float,motion: float) -> void:
	for x in [-34,34]: _post(canvas,x,87,tint,5)
	SurfaceArt.face(canvas,Rect2(-39,-88,78,8),tint.darkened(.1),4)
	_line(canvas,Vector2(-34,-77),Vector2(34,-10),tint.darkened(.37),3)
	for strand in 6:
		var x := -31.0+strand*12
		var length := 26+strand%3*16
		var previous := Vector2(x,-82)
		for joint in range(1,7):
			var t := joint/6.0
			var point := Vector2(x+sin(t*3+time*1.25+phase+strand)*t*4*motion+gust*t*7,-82+t*length)
			_line(canvas,previous,point,leaf.darkened(.3),2)
			var side := -1 if joint%2 else 1
			var leaf_color:=leaf.darkened(.10+(strand%3)*.08)
			_poly(canvas,[point,point+Vector2(side*2,-3),point+Vector2(side*5,-4),point+Vector2(side*8,-1),point+Vector2(side*6,2),point+Vector2(side*3,3)],leaf_color)
			_line(canvas,point,point+Vector2(side*5,0),leaf_color.darkened(.25))
			canvas.draw_rect(Rect2((point+Vector2(side*3,-2)).round(),Vector2(2,1)),leaf_color.lightened(.13))
			previous=point

static func _signal(canvas: Node2D,tint: Color,_accent: Color,time: float,phase: float,_gust: float) -> void:
	Fixture.rail_signal(canvas,tint,time,phase)

static func _pipe(canvas: Node2D,tint: Color,_accent: Color,time: float,phase: float,gust: float) -> void:
	Industrial.pipe(canvas,tint,time,phase,gust)

static func _growth(canvas: Node2D,kind: String,tint: Color,time: float,phase: float,gust: float,motion: float) -> void:
	var reeds := kind=="reeds"
	var brush := kind=="brush"
	for blade in (9 if reeds else 13):
		# Independent deterministic values prevent regular blade heights and
		# spacing. Each tuft grows from three small roots, with open gaps.
		var growth_seed := int(phase*901.0)+blade*7339
		var spread := _growth_hash(growth_seed+119)
		var length := _growth_hash(growth_seed+8317)
		var lean := _growth_hash(growth_seed+2731)
		var x := -16.0+float(blade%3)*17.0+(spread-.5)*7.0
		var root := Vector2(x,-float(blade%2))
		var height := (24.0+length*25.0) if reeds else (12.0+length*22.0) if brush else (9.0+length*27.0)
		var splay := (lean-.5)*(10.0 if reeds else 26.0)
		var tip_x := clampf(x+splay+gust*(7 if reeds else 5)+sin(time*2.0+float(growth_seed))*(.8+length)*motion,-28,28)
		var mid := Vector2(lerpf(x,tip_x,.35),-height*.51)
		var tip := Vector2(tip_x,-height)
		var color := tint.darkened(.05+spread*.24)
		if reeds:
			_line(canvas,root,mid,color.darkened(.2),2)
			_line(canvas,mid,tip,color)
			var head_top := tip+Vector2((lean-.5)*2,-4-length*4)
			_line(canvas,tip,head_top,Color("716346").lerp(color,.2),3)
			_line(canvas,head_top,head_top+Vector2(0,-3),color.darkened(.3))
			var side := -1.0 if blade%2 else 1.0
			var leaf_tip := Vector2(clampf(mid.x+side*(5+spread*5)+gust, -28,28),mid.y-7-length*5)
			_poly(canvas,[root.lerp(mid,.7),mid+Vector2(side*2,0),leaf_tip],color)
		elif brush:
			_line(canvas,root,mid,color.darkened(.18),2)
			_line(canvas,mid,tip,color)
			for fork in 2:
				var at := mid.lerp(tip,.15+fork*.42)
				var side := -1.0 if (blade+fork)%2 else 1.0
				var twig := Vector2(clampf(at.x+side*(4+spread*5)+gust*.8,-29,29),at.y-4-length*5)
				_line(canvas,at,twig,color)
				_line(canvas,twig,twig+Vector2(-side*2,-3),color.darkened(.12))
		else:
			# Narrow bent leaves taper to distinct tips; their roots remain fixed.
			_poly(canvas,[root+Vector2(-1,0),mid+Vector2(-1-spread,0),tip,mid+Vector2(1,0),root+Vector2(1,0)],color)
			if blade%3==1: _line(canvas,root,mid,color.darkened(.25))
			if kind=="frost_grass":
				_line(canvas,tip,tip.lerp(mid,.15),Color("c4d5d9"))
	for clump in 3:
		var x := -16.0+clump*17.0
		_poly(canvas,[Vector2(x-5,0),Vector2(x-3,-2),Vector2(x,-1),Vector2(x+2,-3),Vector2(x+5,0)],tint.darkened(.4+clump*.05))

static func _growth_hash(growth_seed: int) -> float:
	var value := posmod(growth_seed,65521)
	value = posmod(value*25173+13849,65521)
	value = value^(value>>7)
	return float(posmod(value*17431+7219,65521))/65520.0

static func _rubble(canvas: Node2D,tint: Color,phase: float) -> void:
	for index in 7:
		var x := -25+index*8
		var height := 3+posmod(index*13+int(phase),7)
		_poly(canvas,[Vector2(x,0),Vector2(x+2,-height),Vector2(x+7,-height-1),Vector2(x+11,-2),Vector2(x+9,0)],tint.darkened(.28+index%2*.12))
		_line(canvas,Vector2(x+2,-height),Vector2(x+7,-height-1),tint.darkened(.08))

static func _fallback_tree(canvas: Node2D,entry: Dictionary,_time: float,gust: float) -> void:
	# A missing optional image still has a deliberate silhouette in the editor.
	# Release art uses the shared textured mesh and the same anchored motion.
	var height: float = entry.size.y
	var tint: Color = entry.tint
	var middle := Vector2(gust*1.5,-height*.52)
	var top := Vector2(gust*6,-height)
	_line(canvas,Vector2.ZERO,middle,tint.darkened(.58),7)
	_line(canvas,middle,top,tint.darkened(.4),3)
	for branch in 6:
		var t := .32+branch*.09
		var origin := Vector2(gust*t*t*6,-height*t)
		var direction := -1 if branch%2 else 1
		var tip := origin+Vector2(direction*(33-branch*2),-height*.12)
		_line(canvas,origin,tip,tint.darkened(.46),2)
		if entry.get("family",entry.tree)=="conifer":
			_poly(canvas,[origin+Vector2(0,-height*.25),origin+Vector2(34-branch*2,0),origin+Vector2(-34+branch*2,0)],tint.darkened(.29+branch*.025))
		elif entry.get("family",entry.tree) in ["broadleaf","deciduous"]:
			_disc(canvas,tip,24-branch,tint.darkened(.13+branch*.035))
