extends SceneTree
const Transport := preload("res://scripts/network_transport.gd")
class SlowJob extends Transport.RouterMappingJob:
	func run() -> void: OS.delay_msec(350)
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures+=1; push_error(label)
func run() -> void:
	var transport=Transport.new()
	root.add_child(transport)
	await process_frame
	var job=SlowJob.new()
	transport._jobs.append(job)
	check(job.thread.start(job.run)==OK,"Fixture starts a real delayed worker")
	var before=Time.get_ticks_usec()
	transport.free()
	check(Time.get_ticks_usec()-before<100000,"Leaving a room does not wait for native router work")
	var cleanup=root.get_node("RouterMappingCleanup")
	check(cleanup.jobs.size()==1 and job.stopped(),"Persistent cleanup retains and cancels the worker")
	await create_timer(.5,true).timeout
	check(cleanup.jobs.is_empty() and not job.thread.is_started(),"Finished workers are joined and released")
	print("ROUTER CLEANUP: 4 checks, %d failures"%failures)
	quit(1 if failures else 0)
