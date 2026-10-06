extends SceneTree
## Pure authored timeline and native atlas availability; no scene/profile state.
const CinematicArt := preload("res://scripts/travel_cinematic_art.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args(): quit(2); return
	for id in ["signal","storm","supply"]:
		var context: Dictionary={"id":id,"duration":8.0,"character_id":"rika","crew_ids":["rika","branko","ivo","selma"]}
		var unchanged:=context.duplicate(true)
		for elapsed in [-2.0,0.0,1.6,2.4,3.2,4.8,7.9,8.0,12.0,INF,NAN]:
			var normal:=CinematicArt.sample(context,elapsed)
			var reduced:=CinematicArt.sample(context,elapsed,true)
			check(is_finite(float(normal.time)) and float(normal.time)>=0 and float(normal.time)<=8,"Finite bounded clock %s %s"%[id,elapsed])
			check(float(normal.camera_zoom)>=1 and float(normal.camera_zoom)<=1.028 and Vector2(normal.camera_shift).length()<12,"Restrained camera %s %s"%[id,elapsed])
			check(reduced.camera_zoom==1.0 and reduced.camera_shift==Vector2.ZERO and reduced.rain_count<normal.rain_count and reduced.smoke_count<normal.smoke_count,"Reduced presentation holds camera and budgets %s %s"%[id,elapsed])
		check(context==unchanged,"Sampling never mutates shared cinematic context "+id)
	check(CinematicArt.sample({"id":"signal","duration":8},1).power==0 and CinematicArt.sample({"id":"signal","duration":8},4).power==1,"Signal lights power only after visible tuning")
	check(CinematicArt.sample({"id":"signal","duration":8},3).lock==0 and CinematicArt.sample({"id":"signal","duration":8},4).lock==1,"Signal locks after tuning")
	check(CinematicArt.sample({"id":"storm","duration":8},.8).strike==0 and CinematicArt.sample({"id":"storm","duration":8},1.024).strike>.9 and CinematicArt.sample({"id":"storm","duration":8},3).strike==0,"Lightning is one bounded readable cue")
	check(CinematicArt.sample({"id":"storm","duration":8},1).fire==0 and CinematicArt.sample({"id":"storm","duration":8},4).fire==1,"Tree ignition follows strike rather than preceding it")
	check(CinematicArt.sample({"id":"storm","duration":8},1.024,true).strike<.34,"Reduced effects attenuate lightning")
	check(CinematicArt.sample({"id":"supply","duration":8},1).power==0 and CinematicArt.sample({"id":"supply","duration":8},2.5).power==1,"Supply generator powers before shutter completes")
	check(CinematicArt.sample({"id":"supply","duration":8},2).shutter==0 and CinematicArt.sample({"id":"supply","duration":8},5).shutter==1,"Storage shutter has anticipation and finite opening")
	check(CinematicArt._crew({"crew_ids":["rika","branko","ivo","selma","oskar"]})==["rika","branko","ivo","selma"],"Only four actual selected crew identities are drawn")
	check(CinematicArt._crew({"character_id":"nora"})==["nora"] and CinematicArt._crew({"character_id":"bad"})==["mara"],"Solo selection is exact and corrupt identity has safe fallback")
	var actual: Dictionary={"character_id":"branko","crew_ids":["mara","branko","ivo","mara"]}
	var untouched:=actual.duplicate(true)
	check(CinematicArt._crew(actual)==["branko","mara","ivo","mara"] and actual==untouched,"Actual P2 driver leads the cab/scene without mutating or losing duplicate real crew")
	check(CinematicArt._crew({"character_id":"mara","crew_ids":["branko","mara","mara","ivo"]})==["mara","branko","mara","ivo"],"Only the first matching driver occurrence moves forward")
	check(CinematicArt._crew({"character_id":"nora","crew_ids":["mara","ivo"]})==["mara","ivo"],"Missing driver identity never invents an extra crew member")
	check(CinematicArt.sample({"id":"bad","duration":INF},1).id=="signal" and CinematicArt.sample({"duration":NAN},1).duration==8.0,"Malformed display context has finite duration and safe story fallback")
	for environment: String in CinematicArt.Parallax.PROFILES:
		check(CinematicArt.Parallax.available(environment),"All destination depth plates available "+environment)
	for texture: Texture2D in [CinematicArt.HULL,CinematicArt.PARTS,CinematicArt.LANDMARKS,CinematicArt.DEPOT,CinematicArt.METAL,CinematicArt.VERGE,CinematicArt.DEAD_TREE,CinematicArt.CHARRED_TREE,CinematicArt.CONIFER]:
		check(texture!=null and texture.get_width()>0 and texture.get_height()>0,"Authored shared texture available "+texture.resource_path)
	print("TRAVEL CINEMATIC ART: %d/%d passed"%[checks-failures,checks])
	quit(0 if failures==0 else 1)
