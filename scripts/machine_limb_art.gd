extends RefCounted
const Atlas := preload("res://scripts/machine_limb_atlas.gd")
static var baking := false
## Pixel-built industrial steel. Facets, wear and joints share the painted
## chassis' warm olive/bronze range; every detail is fixed in limb coordinates.
const INK := Color("171a16")
const SHADOW := Color("303126")
const STEEL := Color("66654b")
const WARM := Color("867650")
const EDGE := Color("b4a581")
const RUST := Color("59402b")

static func point(origin: Vector2, along: Vector2, across: Vector2, x: float, y: float) -> Vector2:
	return (origin+along*x+across*y).round()

static var _plate_cache: Dictionary = {}

static func _face_texture(length: int, width: int, grain_seed: int, far_side: bool) -> Texture2D:
	grain_seed = posmod(grain_seed,5)
	var key := "%d:%d:%d:%s" % [length,width,grain_seed%5,far_side]
	if _plate_cache.has(key): return _plate_cache[key]
	if not baking:
		var cached := Atlas.part("plate:"+key)
		if cached!=null:
			_plate_cache[key]=cached
			return cached
	var pixels := Image.create(length+4,width+4,false,Image.FORMAT_RGBA8)
	var darkening := 0.23 if far_side else 0.0
	for x in length:
		for y in width:
			var cut := mini(mini(x,length-1-x),mini(y,width-1-y))
			if (x<2 or x>=length-2) and (y<2 or y>=width-2): continue
			var hash_value := posmod(x*73+y*151+grain_seed*31,997)
			var grain := float(hash_value%17-8)/100.0
			var crosslight := sin(float(y)/maxf(1,width-1)*PI)*0.16-float(y)/width*0.13
			var face := STEEL.lightened(crosslight+grain)
			if y<width/2.0: face = face.lerp(WARM,0.18)
			if cut==0: face = INK.lightened(grain*0.25)
			elif y==1: face = EDGE.darkened(0.15+float(hash_value%5)*0.07)
			elif y==width-2: face = SHADOW.lightened(grain)
			elif x==1 or x==length-2: face = WARM.darkened(0.24)
			elif hash_value%13==0: face = SHADOW.lightened(0.08)
			elif hash_value%19==0: face = WARM.lightened(0.14)
			elif posmod(int(floor(x/5.0))*31+int(floor(y/3.0))*19+grain_seed,29)==0:
				face = face.lerp(RUST,0.48)
			pixels.set_pixel(x+2,y+2,face.darkened(darkening))
	# A narrow inset seam and two tiny fastener wells, baked once per segment.
	var seam := int(round(length*0.44))
	for y in range(3,width-2):
		pixels.set_pixel(seam+2,y+2,INK)
		pixels.set_pixel(seam+1,y+2,WARM.darkened(darkening+0.12))
	for x in [4,length-5]:
		var y := int(floor(width/2.0))
		for dx in 3:
			for dy in 3: pixels.set_pixel(clampi(x+dx+1,0,length+3),clampi(y+dy+1,0,width+3),INK)
		pixels.set_pixel(x+2,y+2,EDGE.darkened(darkening))
	var texture := ImageTexture.create_from_image(pixels)
	_plate_cache[key] = texture
	return texture

static func plate(canvas: Node2D, start: Vector2, end: Vector2, width: float, grain_seed: int, far_side: bool = false) -> void:
	var axis := end-start
	var length := axis.length()
	if length<5.0: return
	var segment_length := maxi(8,int(round(length/4.0))*4)
	var segment_width := maxi(6,int(round(width)))
	var texture := _face_texture(segment_length,segment_width,grain_seed,far_side)
	var normal := axis.normalized().orthogonal()
	var vertical := 1.0 if normal.dot(Vector2(-0.6,-0.8))>=0 else -1.0
	canvas.draw_set_transform(start.round(),axis.angle(),Vector2(1,vertical))
	canvas.draw_texture_rect(texture,Rect2(-2,-width*0.5-2,length+4,width+4),false)
	canvas.draw_set_transform(Vector2.ZERO)

static func piston(canvas: Node2D, start: Vector2, end: Vector2, far_side: bool = false) -> void:
	var offset := end-start
	var length := offset.length()
	if not baking and length>=5:
		var cached := Atlas.part("piston:%d:%s"%[maxi(8,roundi(length/4)*4),far_side])
		if cached!=null:
			var normal := offset.normalized().orthogonal()
			canvas.draw_set_transform(start.round(),offset.angle(),Vector2(1,-1 if normal.x>0 else 1))
			canvas.draw_texture_rect(cached,Rect2(-2,-5,length+4,10),false)
			canvas.draw_set_transform(Vector2.ZERO)
			return
	var axis := offset.normalized()
	var side := axis.orthogonal()
	if side.x>0: side = -side
	var sleeve := start.lerp(end,0.58)
	var darkening := 0.28 if far_side else 0.0
	canvas.draw_line(start.round(),end.round(),INK,5)
	canvas.draw_line(start.round(),sleeve.round(),WARM.darkened(darkening+0.20),4)
	canvas.draw_line((start+side).round(),(sleeve+side).round(),EDGE.darkened(darkening+0.10),1)
	canvas.draw_line(sleeve.round(),end.round(),Color("8b8c73").darkened(darkening),2)
	canvas.draw_line((sleeve+side).round(),(end+side).round(),Color("c7bea2").darkened(darkening),1)
	canvas.draw_line((sleeve-side*2).round(),(sleeve+side*2).round(),INK,2)

static var _joint_cache: Dictionary = {}
static var _foot_cache: Dictionary = {}

static func joint(canvas: Node2D, at: Vector2, radius: float, far_side: bool = false) -> void:
	var key := "%s:%s" % [radius,far_side]
	var r := int(ceil(radius))
	if not _joint_cache.has(key) and not baking:
		var cached := Atlas.part("joint:"+key)
		if cached!=null: _joint_cache[key]=cached
	if not _joint_cache.has(key):
		var pixels := Image.create(r*2+3,r*2+3,false,Image.FORMAT_RGBA8)
		var darkening := 0.25 if far_side else 0.0
		for dx in range(-r,r+1):
			for dy in range(-r,r+1):
				if abs(dx)+abs(dy)>r*1.5: continue
				var radial := Vector2(dx,dy).length()/float(r)
				var grain := float(posmod(dx*31+dy*67,13)-6)/120.0
				var light := clampf(float(-dx-dy)/float(r*1.42),-1.0,1.0)
				var copper := Color("936e3d").lightened(maxf(0,light)*0.30+grain)
				copper = copper.darkened(maxf(0,-light)*0.55+darkening)
				var tint := INK
				# Separate load-bearing rim, recessed race, inner bearing and hub.
				# The lower-right races stay dark like the original painted hull.
				if radial<0.93 and radial>=0.74: tint = copper
				elif radial<0.74 and radial>=0.58: tint = Color("23251e").lightened(grain*0.4)
				elif radial<0.58 and radial>=0.30: tint = copper.darkened(0.08)
				elif radial<0.30: tint = Color("292d24")
				if radial>0.76 and radial<0.92 and dx+dy<-r*0.8:
					tint = Color("c3a56b").darkened(darkening+absf(grain))
				if dx==0 and dy==0: tint = Color("8c805d").darkened(darkening)
				if dx==-1 and dy==-1: tint = Color("c2b187").darkened(darkening)
				pixels.set_pixel(dx+r+1,dy+r+1,tint)
		_joint_cache[key] = ImageTexture.create_from_image(pixels)
	canvas.draw_texture(_joint_cache[key],at.round()-Vector2(r+1,r+1))

static func foot(canvas: Node2D, at: Vector2, heavy: bool, far_side: bool = false) -> void:
	var key := "%s:%s" % [heavy,far_side]
	var half := 8 if heavy else 7
	if not _foot_cache.has(key) and not baking:
		var cached := Atlas.part("foot:"+key)
		if cached!=null: _foot_cache[key]=cached
	if not _foot_cache.has(key):
		var pixels := Image.create(half*2+3,10,false,Image.FORMAT_RGBA8)
		var darkening := 0.25 if far_side else 0.0
		for dx in range(-half,half+1):
			for dy in range(-4,4):
				if dy<-1 and (dx<-half+3 or dx>3): continue
				if dy==-1 and (dx<-half+1 or dx>half-2): continue
				var grain := float(posmod(dx*71+dy*137,19)-9)/85.0
				var tint := STEEL.lightened(grain).darkened(darkening)
				if dy==-4 or dy==3 or abs(dx)==half: tint = INK
				elif dy==-3: tint = EDGE.darkened(darkening+0.18+grain)
				elif dy>=0: tint = WARM.darkened(darkening+0.25-grain)
				if dy>=1 and posmod(dx,4)<2: tint = INK
				if posmod(dx*31+dy*7,17)==0 and dy>-3: tint = RUST
				pixels.set_pixel(dx+half+1,dy+5,tint)
		_foot_cache[key] = ImageTexture.create_from_image(pixels)
	canvas.draw_texture(_foot_cache[key],at.round()-Vector2(half+1,5))

static func skid(canvas: Node2D, from: Vector2, to: Vector2) -> void:
	plate(canvas,from,to,6,71)
	for amount in [0.15,0.70]:
		var at := from.lerp(to,amount).round()
		canvas.draw_line(at+Vector2(0,-2),at+Vector2(2,-9),INK,5)
		canvas.draw_line(at+Vector2(0,-2),at+Vector2(2,-9),WARM,2)
