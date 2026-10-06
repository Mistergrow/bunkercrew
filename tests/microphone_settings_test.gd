extends SceneTree
const FakeInput := preload("res://tests/microphone_check_test.gd").FakeInput
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks += 1
	print("MIC SETTINGS %s: %s" % ["PASS" if value else "FAIL",label])
	if not value: failures += 1
func run() -> void:
	if not OS.get_environment("XDG_DATA_HOME").begins_with("/tmp/lastshift-microphone-settings-"):
		push_error("Run in isolated XDG_DATA_HOME=/tmp/lastshift-microphone-settings-...")
		quit(2)
		return
	var mic := FakeInput.new()
	root.add_child(mic)
	mic.set_process(false)
	mic.set_device("Test microphone")
	mic.set_input_gain(1.75)
	check(FileAccess.file_exists("user://microphone.cfg"),"Device and gain settings persist in isolated profile")
	var restored := FakeInput.new()
	root.add_child(restored)
	restored.set_process(false)
	check(restored.selected_device=="Test microphone" and restored.input_gain==1.75,"New backend restores selected device and gain")
	check(not restored.capturing and restored.opened==0,"Restoring settings never activates input")
	var config := ConfigFile.new()
	config.load("user://microphone.cfg")
	check(config.get_section_keys("microphone").size()==2 and config.has_section_key("microphone","device") and config.has_section_key("microphone","gain"),"Saved config contains only device/gain, never recorded samples or active ownership")
	config.set_value("microphone","gain",INF)
	config.set_value("microphone","device","missing device")
	config.save("user://microphone.cfg")
	var invalid := FakeInput.new()
	root.add_child(invalid)
	check(invalid.input_gain==1.0 and invalid.selected_device=="Default" and not invalid.capturing,"Invalid or missing saved device/gain safely fall back while inactive")
	mic.queue_free()
	restored.queue_free()
	invalid.queue_free()
	await process_frame
	print("Microphone settings: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
