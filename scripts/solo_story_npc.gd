extends Node2D
## A visible encounter, never a player, damage target or simulated extra ally.
## The director owns choices, supplies and persistent recruitment.
const PoseArt := preload("res://scripts/worker_pose_art.gd")
const Personality := preload("res://scripts/worker_personality.gd")
var game: Node
var director: Node
var character_id := ""
var site_id := ""
var facing := 1.0
var pose: Dictionary = {}
var idle_clock := WorkerIdleClock.new()
var elapsed := 0.0

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("solo_story_npcs")
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_mode = Node.PROCESS_MODE_PAUSABLE
	idle_clock.configure(character_id.hash()+site_id.hash(),character_id)
	pose=Personality.stance(PoseArt.neutral(),character_id)
	queue_redraw()

func can_interact(player: Node) -> bool:
	if not is_instance_valid(game) or game.is_queued_for_deletion() or not is_instance_valid(director) or director.is_queued_for_deletion(): return false
	if not CharacterCatalog.contains(character_id) or not bool(director.get("enabled")): return false
	if not is_instance_valid(player) or player.is_queued_for_deletion() or player.get("game")!=game: return false
	if not player.has_method("can_act") or not player.can_act(): return false
	if not "players" in game or player not in game.players: return false
	if game.has_method("can_affect_world") and not game.can_affect_world(): return false
	if not player is Node2D or not is_visible_in_tree(): return false
	return player.global_position.distance_to(global_position)<=64.0

func interaction_point() -> Vector2:
	return global_position-Vector2(0,18)

func interaction_title() -> String:
	return str(CharacterCatalog.data(character_id).title)

func prompt(_player: Node) -> String:
	return LocaleText.text(str(CharacterCatalog.data(character_id).detail))

func action_hint(_player: Node) -> String:
	return str(director.encounter_hint(character_id)) if is_instance_valid(director) and director.has_method("encounter_hint") else ""

func interaction_progress(_player: Node) -> float:
	return 0.0

func work_uses_real_time() -> bool:
	return true

func interact(player: Node, _delta: float) -> bool:
	if not can_interact(player) or not director.has_method("open_encounter"): return false
	facing=1.0 if player.global_position.x>=global_position.x else -1.0
	idle_clock.cancel()
	return bool(director.open_encounter(character_id,player,self))

func _process(delta: float) -> void:
	if not is_finite(delta) or delta<=0.0: return
	elapsed=fposmod(elapsed+minf(delta,.25),3600.0)
	idle_clock.tick(minf(delta,.25),true)
	if not idle_clock.gesture.is_empty():
		pose=PoseArt.sample(idle_clock.gesture,idle_clock.progress(),0.0,Vector2(24,-13),character_id)
	else:
		pose=Personality.stance(PoseArt.neutral(),character_id)
		pose.head_shift=Vector2(0,sin(elapsed*2.2)*.35)
		pose.shoulder.y+=sin(elapsed*1.7)*.35
		pose.continuous=true
	queue_redraw()

func _draw() -> void:
	if not CharacterCatalog.contains(character_id) or pose.is_empty(): return
	draw_set_transform(Vector2.ZERO,0.0,Vector2(facing,1.0))
	PoseArt.draw_identity_pose(self,pose,character_id)
	draw_set_transform(Vector2.ZERO)
