class_name MusicCalibration
extends RefCounted
## Tap against the audible click. This estimates extra output delay; it never
## opens a microphone or changes game timing. AudioServer latency is the baseline.

const MIN_TAPS := 8
const MAX_TAPS := 24
const MAX_OFFSET := 0.5
const MAX_JITTER := 0.080
var tempo := 100.0
var offsets: Array[float] = []
var previous_tap := -INF

func begin(bpm: float = 100.0) -> void:
	tempo = clampf(bpm, 60.0, 160.0) if is_finite(bpm) else 100.0
	offsets.clear()
	previous_tap = -INF

func tap(clock_seconds: float) -> bool:
	if not is_finite(clock_seconds) or clock_seconds < 0.0:
		return false
	var interval := 60.0 / tempo
	if previous_tap != -INF and clock_seconds - previous_tap < interval * 0.45:
		return false
	previous_tap = clock_seconds
	# Signed nearest-beat residual avoids selecting the adjacent beat. Users hear
	# the delayed transient after its baseline visual/AudioServer timestamp.
	var residual := clock_seconds - roundf(clock_seconds / interval) * interval
	offsets.append(clampf(residual, -MAX_OFFSET, MAX_OFFSET))
	if offsets.size() > MAX_TAPS:
		offsets.pop_front()
	return true

func result() -> Dictionary:
	if offsets.is_empty():
		return {"ready":false,"count":0,"seconds":0.0,"jitter":0.0,"confidence":0.0}
	var center := _median(offsets)
	var deviations: Array[float] = []
	for value in offsets:
		deviations.append(absf(value-center))
	var jitter := _median(deviations) * 1.4826
	var clean: Array[float] = []
	var threshold := maxf(0.035, jitter * 3.0)
	for value in offsets:
		if absf(value-center) <= threshold:
			clean.append(value)
	return {"ready":clean.size()>=MIN_TAPS and jitter<=MAX_JITTER,"count":offsets.size(),"accepted":clean.size(),"seconds":clampf(_median(clean),-MAX_OFFSET,MAX_OFFSET),"jitter":jitter,"confidence":clampf(1.0-jitter/MAX_JITTER,0.0,1.0)}

func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var middle := floori(float(sorted.size())*0.5)
	return sorted[middle] if sorted.size()%2 else (sorted[middle-1]+sorted[middle])*0.5
