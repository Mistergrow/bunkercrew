extends Node2D
## Paid underground bays continue the original floor's architecture and material.
var site
var lining

func _ready() -> void:
	z_index = -1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

func _process(_delta: float) -> void:
	queue_redraw()

func panel() -> Rect2:
	return Rect2(-106,-196,minf(260,1195-(site.position.x-106)),192)

func _draw() -> void:
	if not is_instance_valid(site) or not is_instance_valid(lining) or not site.excavated():
		return
	var shift := Vector2.ZERO
	if is_instance_valid(site.game) and is_instance_valid(site.game.scenery):
		shift = (site.game.scenery.offset*0.72).round()
	var area := panel()
	var displayed_tier: int = lining.target_tier if lining.curing_remaining>0 else lining.tier
	var wetness: float = lining.curing_remaining/float(lining.spec().cure_time)
	var texture_size := BunkerArchitecture.REAR.get_size()
	# Three independently paid slices assemble into the same wall as upstairs.
	var region := Rect2((site.position.x+area.position.x-444)/751*texture_size.x,0,area.size.x/751*texture_size.x,texture_size.y)
	draw_set_transform(-shift)
	if displayed_tier>0:
		BunkerArchitecture.rear_wall(self,area,region,wetness)
	elif not lining.materials.is_empty() or lining.construction>0:
		for x in range(int(area.position.x)+15,int(area.end.x)-10,23):
			draw_line(Vector2(x,-182),Vector2(x,-9),Color("242724"),3)
			draw_line(Vector2(x-1,-182),Vector2(x-1,-9),Color("a3916c"),1)
		for y in range(-177,-9,24):
			draw_line(Vector2(area.position.x+10,y),Vector2(area.end.x-10,y),Color("776d53"),2)
	if lining.construction>0 and lining.curing_remaining<=0:
		var fill: float = clampf(lining.construction/float(lining.spec().build_time),0,1)
		var fill_area := Rect2(area.position+Vector2(0,area.size.y*(1-fill)),Vector2(area.size.x,area.size.y*fill))
		var fill_region := Rect2(region.position+Vector2(0,region.size.y*(1-fill)),Vector2(region.size.x,region.size.y*fill))
		BunkerArchitecture.rear_wall(self,fill_area,fill_region,1.0)
	if displayed_tier>0:
		# Attached utility run, inset shadow and clamps reuse upstairs colors.
		var top := -175.0
		draw_line(Vector2(area.position.x,top),Vector2(area.end.x,top),Color("181e20"),8)
		draw_line(Vector2(area.position.x,top-2),Vector2(area.end.x,top-2),Color("6b6751"),2)
		for x in range(int(area.position.x)+12,int(area.end.x),60):
			draw_rect(Rect2(x,top-4,4,10),Color("a28a5b"))
	draw_set_transform(Vector2.ZERO)
	if displayed_tier>0:
		BunkerArchitecture.concrete(self,Rect2(area.position.x,-196,area.size.x,16))
		BunkerArchitecture.concrete(self,Rect2(area.position.x,-180,15,180))
		if site.position.x>1000:
			BunkerArchitecture.concrete(self,Rect2(area.end.x-15,-180,15,180))
		if displayed_tier==2:
			# Reinforcement is seated in existing supports instead of a second frame.
			draw_rect(Rect2(area.position.x+5,-178,5,176),Color("343c35"))
			draw_line(Vector2(area.position.x+5,-177),Vector2(area.position.x+5,-3),Color("87917b"),1)
			for y in range(-163,-5,31):
				draw_rect(Rect2(area.position.x+6,y,3,3),Color("b5af8f"))
