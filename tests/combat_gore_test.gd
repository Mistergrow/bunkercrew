extends "res://tests/ground_abilities_test.gd"
const Gore=preload("res://scripts/combat_gore.gd")
class GoreArena extends Arena:
	var combat_gore: Node2D
	var players: Array=[]
	var weather: Node
	func combat_contact(actor,applied,incapacitated):
		var event: Dictionary=combat_gore.make_event(actor,applied,incapacitated)
		combat_gore.present(event,actor,str(actor.get_meta("network_entity_id","")))
class WeatherProbe extends Node:
	var reduced_effects:=false
	var rain_strength:=0.0
	func exposure_at(_at,_actor=null): return 0.0

func run():
	InputSetup.install()
	arena=GoreArena.new()
	root.add_child(arena)
	arena.weather=WeatherProbe.new()
	arena.add_child(arena.weather)
	arena.combat_gore=Gore.new()
	arena.combat_gore.game=arena
	arena.add_child(arena.combat_gore)
	var effects=arena.combat_gore
	effects.set_physics_process(false)
	blocker(Rect2(0,430,1500,35))
	blocker(Rect2(650,190,24,240))
	var player=worker(1,Vector2(350,430))
	player.set_meta("network_entity_id","player:1")
	arena.players.append(player)
	var soldier=preload("res://scenes/ground_infantry.tscn").instantiate()
	soldier.kind="rifle_guard"
	soldier.game=arena
	soldier.position=Vector2(570,430)
	soldier.set_meta("network_entity_id","test:soldier")
	arena.add_child(soldier)
	soldier.set_physics_process(false)
	await frames(3)
	check(effects.level==2,"New profiles enable full effects without changing match rules")
	var rig: Dictionary=Gore._rig(soldier)
	var point: Vector2=rig[8].tip
	ImpactBurst.contact(arena,soldier,point,Vector2.LEFT,Vector2.RIGHT,1.0,"cannon")
	var origin: Vector2=soldier.global_position
	soldier.take_damage(999)
	check(soldier.gore_mask==8 and effects.parts.size()==1,"Precise fatal leg hit separates the selected native limb once")
	check(Vector2(effects.parts[0].point).distance_to(Vector2(rig[8].joint).lerp(rig[8].tip,.5))<.01,"Detached fragment begins at the original joint and foot, without relocation")
	var start_point: Vector2=effects.parts[0].point
	effects._physics_process(1.0/60.0)
	check(Vector2(effects.parts[0].point).distance_to(start_point)>.5,"A boot at actual floor contact launches naturally instead of freezing inside support")
	var corpse=get_nodes_in_group("infantry_remains")[0]
	check(corpse.gore_mask==8 and corpse.get_meta("combat_actor_id")=="test:soldier","Corpse retains hidden limb and stable network identity")
	var drops_before: int=arena.drops.scrap
	soldier.take_damage(999)
	check(effects.parts.size()==1 and arena.drops.scrap==drops_before,"Repeated terminal damage cannot duplicate parts or loot")
	await frames(1)
	check(corpse.global_position==origin,"Body collapse stays at the actual defeat position")
	effects.set_level(1)
	check(effects.parts.is_empty() and effects.level==1,"Blood-only mode immediately clears separated parts")
	effects.set_level(0)
	check(effects.particles.is_empty() and effects.stains.is_empty(),"Off immediately clears human spray and stains")
	check(Gore.visible_mask(player)==0,"Off keeps player anatomy complete")
	effects.set_level(2)
	var second:=GoreArena.new()
	root.add_child(second)
	second.combat_gore=Gore.new()
	second.combat_gore.game=second
	second.add_child(second.combat_gore)
	var other_burst:=ImpactBurst.new()
	other_burst.surface_material="flesh"
	second.add_child(other_burst)
	effects.set_level(0)
	check(not other_burst.retired,"Another world's local option cannot retire this peer's existing blood")
	effects.set_level(2)
	await preload("res://tests/scene_cleanup.gd").free_scene(second,self)
	var p_rig: Dictionary=Gore._rig(player)
	ImpactBurst.contact(arena,player,p_rig[2].tip,Vector2.LEFT,Vector2.RIGHT,1.0,"cannon")
	player.take_damage(999,Vector2.RIGHT)
	check(player.is_downed() and player.gore_mask>0 and Gore.visible_mask(player)>0,"Actual player knockout uses cosmetic limb mask while medical KO remains intact")
	check(effects.parts.size()==1 and int(effects.parts[0].player_id)==1,"Player piece remains associated with its recoverable owner")
	player.medical.state="wounded"
	player._restore_from_aid(.35)
	check(player.hp>0 and player.gore_mask==0 and effects.parts.is_empty(),"Recovery restores full anatomy and removes the old owner fragment")
	check(Gore.visible_mask(player)==0 and effects.mask_for_id("player:1")==0,"Recovery removes pending cosmetic masks as well")
	var blood_before: int=effects.particles.size()
	player.take_damage(10)
	check(effects.particles.size()==blood_before,"Invulnerability emits no fake accepted-damage blood")
	var event:={"material":"flesh","point":Vector2(600,385),"direction":Vector2.RIGHT,"strength":2.0,"part":2,"joint":Vector2(598,380),"tip":Vector2(617,395),"character":"infantry","front":true,"facing":1.0,"player_id":0}
	var player_event: Dictionary=event.duplicate()
	player_event.character="mara"
	player_event.player_id=1
	effects.present(player_event,player,"player:1")
	check(player.gore_mask==0 and effects.parts.is_empty() and effects.pending_player_parts.has(1),"Event before KO snapshot buffers a descriptor without changing the living player's mask")
	player.medical.state="downed"
	player.hp=0
	player.gore_mask=2
	effects.sync_actor(player)
	check(effects.parts.size()==1 and effects.pending_player_parts.is_empty(),"Matching authoritative KO snapshot releases exactly one pending native part")
	effects.sync_actor(player)
	check(effects.parts.size()==1,"Repeated snapshots cannot replay the pending fragment")
	player.medical.state="wounded"
	player.hp=35
	player.gore_mask=0
	effects.sync_actor(player)
	check(effects.parts.is_empty(),"Recovery snapshot removes the old part without a local medical action")
	effects.present(player_event,player,"player:1")
	effects._physics_process(.8)
	check(effects.parts.is_empty() and effects.pending_player_parts.is_empty() and player.gore_mask==0,"Late old event cannot dismember a recovered player and expires promptly")
	for index in 600: effects.present(event,null,"test:soldier")
	check(effects.particles.size()<=Gore.MAX_PARTICLES and effects.parts.size()==Gore.MAX_PARTS,"A 600-hit MG stress burst respects global particle and part caps")
	check(corpse.gore_mask&2,"Late terminal event updates an already reconstructed corpse")
	var clock: float=effects.elapsed
	effects.set_physics_process(true)
	paused=true
	for index in 3: await process_frame
	check(effects.elapsed==clock,"Pause holds cosmetic clocks and fragment poses")
	paused=false
	effects.set_physics_process(false)
	for index in 240: effects._physics_process(1.0/60.0)
	check(effects.collision_count>0 and not effects.stains.is_empty(),"Real wall/floor sweeps stop fragments and create supported stains")
	check(effects.parts.all(func(part):return Vector2(part.point).x<650 and Vector2(part.point).y<430),"Fragments remain on the near side of wall and above supporting floor")
	check(effects.stains.size()<=Gore.MAX_STAINS,"Decal pool remains bounded after the full salve settles")
	arena.weather.reduced_effects=true
	for index in 30: effects.present(event)
	effects._physics_process(.016)
	check(effects.parts.size()<=4 and effects.particles.size()<=64 and effects.stains.size()<=20,"Reduced-effects mode shrinks every active pool")
	var oil: Dictionary=event.duplicate()
	oil.material="oil"
	oil.part=0
	effects.set_level(0)
	effects.present(oil)
	check(effects.particles.size()>0 and effects.particles.all(func(bit):return bit.material=="oil"),"Machines keep dark oil contacts, never human red blood, in Off mode")
	effects.clear()
	check(effects.parts.is_empty() and effects.particles.is_empty() and effects.pending_masks.is_empty(),"World reset releases all transient visuals and cached masks")
	check(await preload("res://tests/scene_cleanup.gd").free_scene(arena,self),"Gore arena releases without live audio or physics objects")
	print("COMBAT GORE: ",checks-failures," passed / ",failures," failed")
	quit(1 if failures else 0)
