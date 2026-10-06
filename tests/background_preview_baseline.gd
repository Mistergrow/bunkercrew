extends RefCounted
## Visual control: reproduce the former enlarged framing and mild filter.

static func frame(view: Rect2, aspect: float, zoom: float) -> Rect2:
	var bottom := 494.0
	var near_zoom := maxf(1.0,zoom)
	var detail_width := lerpf(3000.0,2200.0,clampf((near_zoom-1.0)/1.5,0,1))/near_zoom
	var width := maxf(detail_width,maxf(view.size.x+128.0,(bottom-view.position.y+64.0)*aspect))
	return Rect2(clampf(720.0-width*.5,view.end.x+64.0-width,view.position.x-64.0),bottom-width/aspect,width,width/aspect)

static func show_previous(depths: Node2D, bounds: Rect2, view: Rect2, magnification: float, seconds: float) -> void:
	for surface: ShaderMaterial in depths.image_materials:
		surface.set_shader_parameter("pixel_clarity",1.0)
		surface.set_shader_parameter("detail_strength",.3)
		surface.set_shader_parameter("sample_radius",1.0)
		surface.set_shader_parameter("contour_strength",0.0)
	depths.update_view(frame(view,bounds.size.x/bounds.size.y,magnification),view,seconds,false)

static func show_current(depths: Node2D, bounds: Rect2, view: Rect2, seconds: float) -> void:
	for index in depths.image_materials.size():
		var surface: ShaderMaterial=depths.image_materials[index]
		for parameter: String in preload("res://scripts/parallax_catalog.gd").IMAGE_STYLES[index]:
			surface.set_shader_parameter(parameter,preload("res://scripts/parallax_catalog.gd").IMAGE_STYLES[index][parameter])
	depths.update_view(bounds,view,seconds,false)
