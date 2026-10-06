extends SceneTree
## Every permitted identity/contact list must survive the profile's own reader.
const Hub := preload("res://scripts/social_hub.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(value: bool,label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func contact_rows(count: int,offset: int) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for index in count:
		var code := ""
		var value := offset+index
		for _character in 12:
			code += Hub.FRIEND_ALPHABET[value%Hub.FRIEND_ALPHABET.length()]
			value = floori(float(value)/Hub.FRIEND_ALPHABET.length())
		rows.append({"code":code,"name":"🎧".repeat(24)})
	return rows

func run() -> void:
	check("--no-profile-save" in OS.get_cmdline_user_args(),"Fixture never uses a real player profile")
	var base := "res://artifacts/final-hardening-20261004/network/social-profile-capacity-%d.json" % OS.get_process_id()
	var hub := Hub.new()
	hub.settings_path = base
	root.add_child(hub)
	hub.display_name = "🎧".repeat(24)
	hub.server_url = "wss://crew0.example/social"
	var contacts := {"friends":contact_rows(Hub.MAX_FRIENDS,0),"requests":contact_rows(Hub.MAX_REQUESTS,64),"outgoing_requests":contact_rows(Hub.MAX_REQUESTS,96),"blocked":contact_rows(128,128)}
	for index in 8:
		hub._identities["wss://crew%d.example/social" % index] = {"secret":"a".repeat(64),"code":"ABCDEFGHJKLM","contacts":contacts.duplicate(true)}
	check(Hub.valid_name(hub.display_name) and hub._identities.size()==8,"Fixture uses all eight supported identities and valid 96-byte names")
	for key: String in contacts:
		var limit := Hub.MAX_FRIENDS if key=="friends" else 128 if key=="blocked" else Hub.MAX_REQUESTS
		var rows: Array[Dictionary] = hub._read_rows(contacts[key],limit,false)
		check(not (rows.size()==1 and rows[0].has("invalid")),"Each full contact list satisfies its actual reader")
	check(hub._save_profile(),"Legal profile writes through the actual private atomic writer")
	var file := FileAccess.open(base,FileAccess.READ)
	var bytes := file.get_length()
	file.close()
	print("SOCIAL_PROFILE_CAPACITY_BYTES ",bytes)
	check(bytes<=Hub.MAX_PROFILE_BYTES,"Every supported maximum profile fits its read limit")
	var recovered := hub._read_profile(base)
	check(not recovered.is_empty() and recovered.get("identities",{})==hub._identities,"Written Unicode contacts and credentials round-trip exactly")
	var fresh := Hub.new()
	fresh.settings_path = base
	root.add_child(fresh)
	check(fresh._identities==hub._identities and fresh.display_name==hub.display_name,"A fresh actual Hub restores every supported service identity")
	var oversized := FileAccess.open(base,FileAccess.WRITE)
	oversized.store_string(" ".repeat(Hub.MAX_PROFILE_BYTES+1))
	oversized.close()
	check(hub._read_profile(base).is_empty(),"Oversized hostile files remain bounded before JSON parsing")
	await preload("res://tests/scene_cleanup.gd").free_scene(fresh,self)
	await preload("res://tests/scene_cleanup.gd").free_scene(hub,self)
	for suffix in ["",".bak",".tmp",".bak.tmp"]:
		if FileAccess.file_exists(base+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(base+suffix))
	print("SOCIAL PROFILE CAPACITY: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
