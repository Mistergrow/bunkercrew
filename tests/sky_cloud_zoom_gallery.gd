extends "res://tests/sky_cloud_zoom_test.gd"
## Native before/after frames use the same real owner, held clock and camera.
var phase := "baseline"
var captures: Array[Dictionary]=[]

func capture(environment: String,pose: Dictionary,mode: String) -> void:
	var name: String=environment+"-"+str(pose.id)+"-"+mode
	var rendered:=await picture()
	check(rendered.get_size()==SCREEN and rendered.save_png(output_directory+phase+"/"+name+".png")==OK,name+": exact native frame is saved")
	captures.append({"world":environment,"pose":pose.id,"mode":mode,"file":phase+"/"+name+".png","resolution":[SCREEN.x,SCREEN.y],"clock":CLOCK,"geometry":geometry(pose),"renderer":RenderingServer.get_video_adapter_name()})

func gallery_world(environment: String) -> void:
	await world(environment)
	for pose: Dictionary in POSES:
		await stage(pose)
		await capture(environment,pose,"standard")
	await key(KEY_F3)
	for pose: Dictionary in [POSES[1],POSES[2]]:
		await stage(pose)
		await capture(environment,pose,"reduced")
		check(not sky.is_visible_in_tree(),environment+" "+str(pose.id)+": reduced capture contains no added light/cloud overlay")
	await key(KEY_F3)
	check(await Cleanup.free_scene(game,self),environment+": native gallery scene retires cleanly")
	game=null

func write_gallery() -> void:
	var entries:=captures.duplicate()
	var other: String="baseline" if phase=="final" else "final"
	var previous_path: String=output_directory+other+"/report.json"
	if FileAccess.file_exists(previous_path):
		var previous=JSON.parse_string(FileAccess.get_file_as_string(previous_path))
		if previous is Dictionary: entries.append_array(previous.get("captures",[]))
	var html: String="<!doctype html><html lang='de'><meta charset='utf-8'><meta name='viewport' content='width=device-width'><title>Bunkercrew · Wolken und Kamerazoom</title><style>body{background:#111b20;color:#dedacb;font:16px system-ui;margin:24px}a{color:#dbb371}nav{position:sticky;top:0;background:#111b20;padding:8px}select{padding:8px;background:#27352f;color:#dedacb;margin:4px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(480px,1fr));gap:24px}figure{margin:0}img{width:100%;display:block}figcaption{padding:8px 0}figure[hidden]{display:none}</style><h1>Bunkercrew · Wolken bei Zoom und Kamerabewegung</h1><p>Echte Godot-Szenen von Sektor 07 und Aschewerk mit angehaltenen Simulations-, Wind- und Wolkenuhren. Native 1280×720-Bilder mit tatsächlichem WeatherSky und SkyTraffic. Standard und F3 getrennt; Kamera und Quellkoordinaten sind im Prüfbericht dokumentiert.</p><nav><select id='world' onchange='filter()'><option>sector07</option><option>ash_foundry</option></select><select id='mode' onchange='filter()'><option>standard</option><option>reduced</option></select><select id='pose' onchange='filter()'><option>normal085</option><option>wide060</option><option>close125</option><option>pan-left</option><option>pan-zoom-right</option><option>sky085</option></select><a href='"+phase+"/report.json'>Zustände und Geometrie</a></nav><main>"
	for entry: Dictionary in entries:
		html+="<figure data-world='%s' data-mode='%s' data-pose='%s'><a href='%s'><img loading='lazy' src='%s' alt='%s'></a><figcaption>%s · %s · %s · %s</figcaption></figure>"%[entry.world,entry.mode,entry.pose,entry.file,entry.file,entry.pose,entry.world,entry.pose,entry.mode,str(entry.file).get_slice("/",0)]
	html+="</main><script>function filter(){document.querySelectorAll('figure').forEach(e=>e.hidden=e.dataset.world!==world.value||e.dataset.mode!==mode.value||e.dataset.pose!==pose.value)}filter()</script></html>"
	FileAccess.open(output_directory+"index.html",FileAccess.WRITE).store_string(html)

func _run() -> void:
	if "--no-profile-save" not in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless": quit(2);return
	output_directory="res://artifacts/sky-cloud-zoom-20261005/gallery/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): phase=argument.trim_prefix("--phase=")
	if phase not in ["baseline","final"]: quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory+phase))
	setup()
	for environment: String in ["sector07","ash_foundry"]: await gallery_world(environment)
	FileAccess.open(output_directory+phase+"/report.json",FileAccess.WRITE).store_string(JSON.stringify({"phase":phase,"checks":checks,"failures":failures,"captures":captures,"prepared":"Actual one-player missions, real active WeatherSky/SkyTraffic and Camera2D, 1280x720 native SubViewport. Same held scene clock8, wind and real geometry updates at zoom.60/.85/1.15/1.25, horizontal+vertical movement, Standard/F3 separately. No node/material/atlas substitute. Muted unsaved private profile, stopped waves; screenshots are prepared presentation states and not a performance benchmark."},"  "))
	write_gallery()
	view.queue_free()
	await frames()
	print("SKY CLOUD ZOOM GALLERY %s: %d/%d checks; %d captures"%[phase,checks-failures,checks,captures.size()])
	quit(1 if failures else 0)
