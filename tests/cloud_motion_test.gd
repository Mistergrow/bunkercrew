extends SceneTree
const Motion := preload("res://scripts/cloud_motion.gd")
class WeatherProbe extends Node:
	var strength := 0.0
	func gust_at(_point: Vector2) -> float: return strength
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1
	print("CLOUD MOTION %s: %s"%["PASS" if value else "FAIL",label])
func run() -> void:
	var weather := WeatherProbe.new()
	root.add_child(weather)
	var motion := Motion.new()
	var rates := [3.3,13.5,42.0]
	motion.advance(3,rates,weather)
	check(motion.wind_distance==PackedFloat64Array([0,0,0]),"calm leaves the three steady altitude drifts intact")
	weather.strength=1
	motion.advance(3,rates,weather)
	for depth in 3:
		check(motion.gust_response[depth]>0 and motion.gust_response[depth]<1,"layer%d wind response ramps instead of jumping"%depth)
		check(motion.wind_distance[depth]>0 and motion.wind_distance[depth]<rates[depth]*Motion.GUST_GAIN[depth]*3,"layer%d gust contribution stays bounded"%depth)
		var fine := Motion.new()
		for step in 180: fine.advance(1.0/60.0,rates,weather)
		check(absf(fine.wind_distance[depth]-motion.wind_distance[depth])<.00001,"layer%d 60Hz displacement matches analytical 3s integration"%depth)
	var saved := motion.wind_distance.duplicate()
	motion.advance(0,rates,weather)
	check(saved==motion.wind_distance,"zero/pause delta leaves every cloud distance unchanged")
	for depth in 3:
		var screen_motion := Motion.camera_offset(depth,100)-100
		check(is_equal_approx(screen_motion,-100*Motion.CAMERA_DEPTH[depth]),"layer%d camera pan follows its distinct screen-space depth"%depth)
	motion.reset()
	check(motion.wind_distance==PackedFloat64Array([0,0,0]) and motion.gust_response==PackedFloat64Array([0,0,0]),"new scene resets wind phase/filter")
	weather.queue_free()
	await process_frame
	print("CLOUD MOTION %d/%d"%[checks-failures,checks])
	quit(1 if failures else 0)
