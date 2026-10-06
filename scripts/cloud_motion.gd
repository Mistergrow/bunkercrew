extends RefCounted
## Cloud height has its own steady airflow. Ground weather adds a bounded,
## slowly responding drift; it never stops or reverses the distant sky.
const CAMERA_DEPTH := [0.12,0.38,0.72]
const GUST_GAIN := [0.08,0.18,0.32]
const RESPONSE_SECONDS := [7.0,4.0,2.0]
var gust_response := PackedFloat64Array([0.0,0.0,0.0])
var wind_distance := PackedFloat64Array([0.0,0.0,0.0])

func advance(delta: float,speeds: Array,weather: Node) -> void:
	if delta<=0.0: return
	for depth in 3:
		var target := 0.0
		if is_instance_valid(weather):
			if weather.has_method("gust_at"):
				target=clampf(float(weather.gust_at(Vector2(400+depth*310,-120-depth*180))),0,1)
			elif weather.has_method("wind_strength"):
				target=clampf(float(weather.wind_strength()),0,1)
		# Exact integral of this exponential filter over the frame interval.
		# This keeps displacement stable across 30/60/144 Hz presentation.
		var response: float=RESPONSE_SECONDS[depth]
		var weight := 1.0-exp(-delta/response)
		var integral := target*delta+(gust_response[depth]-target)*response*weight
		wind_distance[depth]+=float(speeds[depth])*float(GUST_GAIN[depth])*integral
		gust_response[depth]=lerpf(gust_response[depth],target,weight)

func reset() -> void:
	gust_response.fill(0.0)
	wind_distance.fill(0.0)

static func camera_offset(depth: int,camera_delta_x: float) -> float:
	# A moving camera reveals foreground faster than the high cloud sheet.
	return camera_delta_x*(1.0-float(CAMERA_DEPTH[depth]))
