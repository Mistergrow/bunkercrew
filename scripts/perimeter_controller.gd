class_name PerimeterController
extends Node2D
## Persistent sites are created in a deterministic order before either player.
const SITE=preload("res://scenes/perimeter_site.tscn")
var game: Node
var layout: ScenarioCombat
var sites: Array[Node2D]=[]
var _bootstrapped:=false

func bootstrap(owner_game: Node) -> void:
	if _bootstrapped: return
	game=owner_game
	layout=ScenarioCombat.for_game(game)
	if layout==null and is_instance_valid(game.get("core")):
		# Classic keeps its original enemy and air-lane rules. This private
		# footprint only locates the same outer sites on the existing east road.
		layout=ScenarioCombat.new()
		layout.configure("left",float(game.world_left),float(game.world_right),430.0,67.0,802.0,float(game.core.position.x))
	if layout==null: return
	_bootstrapped=true
	var sides: Array[int]=[]
	sides.assign([-1,1] if layout.position_mode=="center" else ([-1] if layout.position_mode=="right" else [1]))
	for side in sides:
		var edge: float=layout.bunker_right if side>0 else layout.bunker_left
		for entry in PerimeterCatalog.SITES:
			var point:=Vector2(edge+side*float(entry.distance),layout.ground_y)
			# Current layouts have at least650px outdoors on each active front.
			# Reject invalid future layouts instead of moving a site into a bunker.
			if not layout.field_position_allowed(point.x,44.0): continue
			var site=SITE.instantiate()
			site.name="%s_%s"%["East" if side>0 else "West",entry.id]
			site.game=game
			site.role=entry.role
			site.side=side
			site.slot_index=sites.size()
			site.position=to_local(game.to_global(point))
			if site.role=="fence":
				# Configure only this new site. Re-bootstrap and authoritative
				# snapshot application must never resurrect a destroyed fence.
				site.tier=PerimeterCatalog.STARTER_FENCE_TIER
				site.max_hp=float(PerimeterCatalog.spec("fence",site.tier).hp)
				site.hp=site.max_hp
			add_child(site)
			sites.append(site)
	var courtyard=preload("res://scripts/courtyard_art.gd").new()
	courtyard.configure(self)
	add_child(courtyard)

func enter_road_view() -> void:
	# Keep permanent defense records for snapshots without letting their old
	# drawing, gate simulation or colliders enter the separate convoy road.
	hide()
	for site in sites:
		site.set_physics_process(false)
		site.sync_replica()

func air_defense_ready() -> bool:
	# Ground outposts never unlock air waves; the bunker flak retains that role.
	return false
