class_name CampaignSalvage
extends Node2D
## Route data is separate from carried materials and the bunker technology tree.
## Each wave has one deterministic envelope; only its real pickup can claim it.
var game: Node
var claim_id := ""
var drop_id := ""
var amount := 1
var elapsed := 0.0
var fall_speed := 0.0
var collected := false
const PICKUP_ART = preload("res://scripts/pickup_art.gd")
var _last_indicator := -1

static func drop_for_enemy(owner_game: Node, enemy: Node2D) -> CampaignSalvage:
	var state := CampaignBonus._state(owner_game)
	if state == null or not state.mission_running or not is_instance_valid(enemy): return null
	var wave: int = int(enemy.wave)
	var boss: bool = bool(enemy.get_meta("final_boss", false))
	if not boss and not bool(enemy.elite) and wave % 3 != 0: return null
	var key := "boss" if boss else "wave_%02d" % wave
	var count := 3 if boss else 1
	if not state.reserve_drop(key, count): return null
	var pickup := CampaignSalvage.new()
	pickup.game = owner_game
	pickup.claim_id = state.mission_id
	pickup.drop_id = key
	pickup.amount = count
	var x: float = enemy.global_position.x
	if "world_left" in owner_game and "world_right" in owner_game:
		x = clampf(x, float(owner_game.world_left)+24, float(owner_game.world_right)-24)
	pickup.position = Vector2(x, enemy.global_position.y-18)
	owner_game.add_child(pickup)
	return pickup

static func recover_remaining(owner_game: Node) -> int:
	# Called only by the verified victory path, before committing the campaign.
	# These are actual previously spawned drops, not a victory currency grant.
	if not is_instance_valid(owner_game) or not owner_game.is_inside_tree(): return 0
	var total := 0
	for pickup in owner_game.get_tree().get_nodes_in_group("campaign_salvage"):
		if pickup.game == owner_game and pickup.collect(false): total += pickup.amount
	return total

func _ready() -> void:
	add_to_group("campaign_salvage")
	z_index = 6
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	material = PICKUP_ART.cutout_material()

func _process(delta: float) -> void:
	elapsed += delta
	var indicator := PICKUP_ART.indicator_state(elapsed,2)
	if indicator != _last_indicator:
		_last_indicator = indicator
		queue_redraw()

func _physics_process(delta: float) -> void:
	if collected: return
	var state := CampaignBonus._state(game)
	if state == null or not state.mission_running or state.mission_id != claim_id:
		queue_free()
		return
	fall_speed = minf(fall_speed + 1050.0 * delta, 650.0)
	var to := global_position + Vector2(0, fall_speed * delta)
	var hit := get_world_2d().direct_space_state.intersect_ray(PhysicsRayQueryParameters2D.create(global_position-Vector2(0,2), to+Vector2(0,1), 1|2))
	if hit.is_empty(): global_position = to
	else:
		global_position.y = hit.position.y-0.5
		fall_speed = 0.0
	for player in get_tree().get_nodes_in_group("players"):
		if not is_instance_valid(player) or player.is_queued_for_deletion() or player.get("game")!=game: continue
		if player.has_method("is_downed") and player.is_downed(): continue
		var target: Vector2 = player.global_position-Vector2(0,20)
		if (global_position-Vector2(0,12)).distance_to(target) > 72.0: continue
		var ray := PhysicsRayQueryParameters2D.create(global_position-Vector2(0,12),target,1|2)
		if get_world_2d().direct_space_state.intersect_ray(ray).is_empty():
			collect()
			return

func collect(feedback: bool = true) -> bool:
	var state := CampaignBonus._state(game)
	if collected or state == null or state.mission_id != claim_id or not state.collect_salvage(drop_id,amount): return false
	collected = true
	if feedback:
		if game.has_method("fx"): game.fx(global_position-Vector2(0,12),Color("d9bd75"),5)
		preload("res://scripts/spatial_sound.gd").emit(game,"pickup",global_position-Vector2(0,12))
		if game.has_method("notify"): game.notify(LocaleText.format("+%d Bergungsdaten · Reisevorrat nach dem Sieg gesichert", amount))
	queue_free()
	return true

func _draw() -> void:
	# Recovered data stays in a physical field recorder. A worn identification
	# band distinguishes it from ordinary technology without floating labels.
	PICKUP_ART.draw_world(self,"core",2,Vector2.ZERO,0,PICKUP_ART.indicator_state(elapsed,2))
	draw_rect(Rect2(-7,-11,2,8),Color("bd9d61"))
	draw_rect(Rect2(-7,-9,2,2),Color("ddd0a5"))
