class_name DomeController
extends Node2D
## A late-wave shell built at one reachable service console. Construction uses
## buffered physical steel/glass; research points alone cannot create a dome.

const SEGMENT = preload("res://scripts/dome_segment.gd")
const DefenseArt := preload("res://scripts/defense_structure_art.gd")
const SITE := Vector2(1250, 430)
const COST := {"steel": 4, "alloy": 4, "glass": 12}
const FRAME_TIME := 1.2
const GLAZE_TIME := 2.0
const REPAIR_TIME := 0.9
const REPAIR_HP := 150.0
const ROOF_CENTER := Vector2(682.5, 245)
const ROOF_RADII := Vector2(607.5, 190)
const ROOF_PANELS := 12
const EDGES_PER_PANEL := 6
const PORT_UPPER := Vector2(1290, 310)
const PORT_LOWER := Vector2(1290, 404)
var game
var available := false
var frame_built := false
var built := false
var materials: Dictionary = {}
var transfer: Dictionary = {}
var construction := 0.0
var repair_work := 0.0
var repair_target
var segments: Array = []
var front
var fronts: Array = []
var site := SITE
var roof_center := ROOF_CENTER
var roof_radii := ROOF_RADII
var flak_port_left := FLAK_PORT_LEFT
var flak_port_right := FLAK_PORT_RIGHT
var dual_fronts := false
var flak_port_active := false
var console_layer: Node2D
var _console_signature := ""
const FLAK_PORT_LEFT := 478.0
const FLAK_PORT_RIGHT := 582.0

func configure_for_scenario(room_left: float, room_right: float, flak_x: float) -> void:
	assert(segments.is_empty(),"Configure dome placement before unlocking its physical panels")
	dual_fronts=true
	roof_center=Vector2((room_left+room_right)*0.5,245)
	roof_radii=Vector2((room_right-room_left+180.0)*0.5,190)
	site=Vector2(room_left+428,430)
	flak_port_left=flak_x-52.0
	flak_port_right=flak_x+52.0

func front_x_positions() -> Array[float]:
	if dual_fronts: return [roof_center.x-roof_radii.x,roof_center.x+roof_radii.x]
	return [PORT_UPPER.x]

func _ready() -> void:
	z_index = -3
	visible = false
	add_to_group("interactables")
	add_to_group("dome_sites")
	console_layer=Node2D.new()
	console_layer.name="DomeServiceConsole"
	console_layer.z_index=8
	console_layer.draw.connect(_draw_console)
	add_child(console_layer)
	queue_redraw()

func _process(_delta: float) -> void:
	# Replication updates parent fields and individual panes independently. Keep
	# the separate foreground cabinet fresh without rebuilding it each frame.
	var signature := "%s:%s:%s:%s:%s:%s" % [available,frame_built,built,_damaged_segment()!=null,UiArt.world_label_visible(self),LocaleText.current_locale()]
	if signature!=_console_signature:
		_console_signature=signature
		if is_instance_valid(console_layer): console_layer.queue_redraw()
	var rounds = game.get("rounds") if is_instance_valid(game) else null
	if not available and is_instance_valid(rounds) and int(rounds.wave) >= Balance.DOME_WAVE:
		unlock()
	var station = game.get("flak_station") if is_instance_valid(game) else null
	var port_needed: bool = is_instance_valid(station) and station.built
	if port_needed != flak_port_active:
		flak_port_active = port_needed
		for segment in segments:
			if not segment.front_line:
				segment.update_service_port.call_deferred(flak_port_active)
		queue_redraw()

func _requirements_met() -> bool:
	if not is_instance_valid(game):
		return false
	var rounds = game.get("rounds")
	var upgrades = game.get("upgrades")
	return is_instance_valid(rounds) and int(rounds.wave) >= Balance.DOME_WAVE and is_instance_valid(upgrades) and upgrades.has_upgrade("bunker_fortress")

func unlock() -> void:
	if available:
		return
	var rounds = game.get("rounds") if is_instance_valid(game) else null
	if not is_instance_valid(rounds):
		return
	var after_wave_fifteen: bool = int(rounds.wave) >= Balance.DOME_WAVE or (int(rounds.wave) == Balance.DOME_WAVE - 1 and str(rounds.phase) == "salvage")
	if not after_wave_fifteen:
		return
	available = true
	visible = true
	for index in ROOF_PANELS:
		_add_roof_panel(index)
	# The front is split into two physical pieces around an actual firing window.
	# Both distant and front-line enemies can be hit without ignoring any glass.
	for x in front_x_positions():
		var pane = _add_segment(Vector2(x,245),Vector2(x,430),true)
		fronts.append(pane)
	front=fronts[-1]
	queue_redraw()

func _add_roof_panel(index: int) -> void:
	var points := PackedVector2Array()
	var normals := PackedVector2Array()
	for edge in EDGES_PER_PANEL + 1:
		var angle := PI + PI * float(index * EDGES_PER_PANEL + edge) / float(ROOF_PANELS * EDGES_PER_PANEL)
		points.append(roof_center+Vector2(cos(angle),sin(angle))*roof_radii)
		# Analytic normals match at shared ends, so adjacent physical curved strips
		# meet cleanly and both springing points finish exactly at roof height245.
		normals.append(Vector2(-roof_radii.x*sin(angle),roof_radii.y*cos(angle)).normalized().orthogonal())
	var segment = SEGMENT.new()
	segment.game = game
	segment.controller = self
	segment.name = "DomeRoof%02d" % (index + 1)
	segment.service_port = flak_port_active
	segment.configure_curve(points, normals, index)
	add_child(segment)
	segments.append(segment)

func _add_segment(from: Vector2, to: Vector2, ground_front: bool = false):
	var segment = SEGMENT.new()
	segment.game = game
	segment.controller = self
	segment.name = "DomeFront" if ground_front else "DomePane%02d" % (segments.size() + 1)
	segment.configure(from, to, segments.size(), ground_front)
	add_child(segment)
	segments.append(segment)
	return segment

func interaction_point() -> Vector2:
	return to_global(site-Vector2(0,26))

func can_interact(_player) -> bool:
	return available

func _damaged_segment():
	for pane in fronts:
		if is_instance_valid(pane) and pane.needs_repair(): return pane
	if is_instance_valid(front) and front.needs_repair(): return front
	for segment in segments:
		if segment.needs_repair():
			return segment
	return null

func _frame_materials_ready() -> bool:
	return int(materials.get("steel", 0)) >= int(COST.steel) and int(materials.get("alloy", 0)) >= int(COST.alloy)

func prompt(player) -> String:
	if not available:
		return LocaleText.format("GLASKUPPEL · ab Welle %d + Technik FESTUNG", Balance.DOME_WAVE)
	if not _requirements_met():
		var wave: int = game.rounds.wave
		return LocaleText.format("GLASKUPPEL · ab Welle %d · T: FESTUNG · Bedarf 4 Stahl + 4 Panzerstahl + 12 Glas", Balance.DOME_WAVE) if wave < Balance.DOME_WAVE else LocaleText.text("GLASKUPPEL · T: FESTUNG · Bedarf 4 Stahl + 4 Panzerstahl + 12 Glas")
	if built:
		var damaged = _damaged_segment()
		if damaged != null:
			return LocaleText.format("GLASKUPPEL · %s %d/%d · Reparatur: 1 Glas", [LocaleText.text("Front") if damaged.front_line else LocaleText.format("Feld %02d", (damaged.panel_index + 1)), ceil(damaged.hp), ceil(damaged.max_hp)])
		return LocaleText.text("GLASKUPPEL · beide Fronten intakt · Schussöffnungen frei") if dual_fronts else LocaleText.text("GLASKUPPEL · Front 1200/1200 · Schussöffnung frei · intakt")
	if not frame_built and _frame_materials_ready():
		return LocaleText.text("GLASKUPPEL · halten: Panzergerüst errichten · danach 12 Glas")
	if frame_built and int(materials.get("glass", 0)) >= int(COST.glass):
		return LocaleText.text("GLASKUPPEL · halten: Glasfelder montieren · Front 1200 Haltbarkeit")
	return LocaleText.format("GLASKUPPEL · Stahl %d/4 · Panzerstahl %d/4 · Glas %d/12 · halten: einfüllen%s", [materials.get("steel", 0), materials.get("alloy", 0), materials.get("glass", 0), LocaleText.text(" · Glas mitbringen") if frame_built and int(player.inventory.get("glass", 0)) == 0 else ""])

func interaction_progress(_player) -> float:
	if built:
		return repair_work / REPAIR_TIME
	return construction / (GLAZE_TIME if frame_built else FRAME_TIME)

func cover_height(x: float) -> float:
	# Weather asks for the first intact pane above a column. Polygon intersections
	# keep open ports and broken fields permeable without a physics query per drop.
	var cover := INF
	for segment in segments:
		if not segment.is_blocking():
			continue
		for vertices: PackedVector2Array in segment.polygons:
			for index in vertices.size():
				var a: Vector2 = segment.to_global(vertices[index])
				var b: Vector2 = segment.to_global(vertices[(index + 1) % vertices.size()])
				if x < minf(a.x, b.x) or x > maxf(a.x, b.x):
					continue
				if is_equal_approx(a.x, b.x):
					cover = minf(cover, minf(a.y, b.y))
				else:
					cover = minf(cover, lerpf(a.y, b.y, (x - a.x) / (b.x - a.x)))
	return cover

func interact(player, delta: float) -> void:
	if not is_instance_valid(player) or not is_finite(delta) or delta <= 0.0 or not available or not _requirements_met():
		return
	if built:
		_repair(player, delta)
		return
	if not frame_built and _frame_materials_ready():
		construction += delta
		if construction >= FRAME_TIME:
			frame_built = true
			construction = 0.0
			for segment in segments:
				segment.set_frame()
			preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
	elif frame_built and int(materials.get("glass", 0)) >= int(COST.glass):
		construction += delta
		var pane_count := mini(segments.size(), int(construction / GLAZE_TIME * segments.size()))
		for index in pane_count:
			segments[index].glaze()
		if construction >= GLAZE_TIME:
			built = true
			construction = 0.0
			preload("res://scripts/spatial_sound.gd").emit(game,"produce",interaction_point())
			game.notify(LocaleText.text("Glaskuppel geschlossen · Dachgeschütz durch die offene Schießscharte ausrichten."))
	else:
		_deposit(player, delta)
	queue_redraw()

func _deposit(player, delta: float) -> void:
	var id: int = player.get_instance_id()
	transfer[id] = float(transfer.get(id, 0.0)) + delta
	if transfer[id] < Balance.TRANSFER_TIME:
		return
	for kind: String in ["steel", "alloy", "glass"]:
		if int(materials.get(kind, 0)) < int(COST[kind]) and player.take_item(kind, 1):
			materials[kind] = int(materials.get(kind, 0)) + 1
			transfer[id] = 0.0
			preload("res://scripts/spatial_sound.gd").emit(game,"build",interaction_point())
			return

func _repair(player, delta: float) -> void:
	var damaged = _damaged_segment()
	if damaged == null:
		repair_work = 0.0
		repair_target = null
		return
	if damaged != repair_target:
		repair_work = 0.0
		repair_target = damaged
	if int(player.inventory.get("glass", 0)) < 1:
		return
	repair_work += delta
	if repair_work < REPAIR_TIME:
		return
	if not player.take_item("glass", 1):
		return
	repair_work = 0.0
	damaged.repair(REPAIR_HP)
	preload("res://scripts/spatial_sound.gd").emit(game,"build",damaged.interaction_point())
	game.fx(damaged.interaction_point(), Color("a3baba"), 9)
	queue_redraw()

func _draw() -> void:
	if not available:
		return
	if not frame_built:
		return
	# Modular arenas stand on level ground, so both springing points receive a
	# full-height front and foundation. The original hillside keeps its roof seat.
	if not dual_fronts: _foundation(Rect2(45,239,60,18))
	for x in front_x_positions():
		_draw_ground_front(x)
	if flak_port_active:
		for x in [flak_port_left,flak_port_right]:
			var normalized := clampf((x-roof_center.x)/roof_radii.x,-1.0,1.0)
			var roof_y := roof_center.y-roof_radii.y*sqrt(1.0-normalized*normalized)
			DefenseArt.Surface.panel(self,Rect2(x-4,roof_y-13,8,29),Color("697262"),2)
			for y in [-7,7]: DefenseArt.bolt(self,Vector2(x,roof_y+y))

func _draw_console() -> void:
	if not available: return
	DefenseArt.dome_console(console_layer,site,frame_built,built,_damaged_segment()!=null)
	if UiArt.world_label_visible(self):
		UiArt.world_label(console_layer,site+Vector2(0,-146),"GLASKUPPEL","",UiArt.MUTED)

func _draw_ground_front(center_x: float) -> void:
	_foundation(Rect2(center_x-22,423,50,16))
	for x in [center_x-12,center_x+10]:
		for section in [Vector2(245,PORT_UPPER.y-5),Vector2(PORT_LOWER.y+5,423)]:
			DefenseArt.beam(self,Vector2(x,section.x),Vector2(x,section.y),6,2)
	for at in [Vector2(center_x,PORT_UPPER.y),Vector2(center_x,PORT_LOWER.y)]:
		DefenseArt.beam(self,at-Vector2(16,0),at+Vector2(16,0),8,3)
		for side in [-1,1]: DefenseArt.bolt(self,at+Vector2(11*side,0))

func _foundation(rect: Rect2) -> void:
	DefenseArt.Surface.panel(self,rect,Color("636956"),2)
