class_name MusicBeatClock
extends RefCounted
## Presentation clock. Gameplay never reads this clock or its cosmetic events.
## Events remain pending until their sample is audible on this output device.

signal beat(bar_index: int, beat_index: int, strength: float)
signal downbeat(bar_index: int, strength: float)
signal accent(track: int, strength: float)
signal bar(index: int)
signal phrase(index: int)

const MAX_PENDING_EVENTS := 2048
const MAX_EVENTS_PER_FRAME := 256
const MAX_EVENT_AGE_SECONDS := 0.75
const KICK_DECAY := 0.18
const ACCENT_DECAY := 0.28

var bpm := 100.0
var beats_per_bar := 4
var phrase_bars := 8
var calibration_seconds := 0.0
var audible_seconds := -1.0
var audible_samples := -1.0
var beat_phase := 0.0
var beat_index := -1
var bar_index := -1
var active := false
var paused := false
var kick_pulse := 0.0
var accent_pulse := 0.0
var dropped_events := 0
var _pending: Array[Dictionary] = []
var _last_beat := -1
var _last_samples := -1
var _last_rate := -1
var _output_samples := -INF
var _kick_seconds := -INF
var _kick_strength := 0.0
var _accent_seconds := -INF
var _accent_strength := 0.0
var _has_started := false
var _kick_count := 0
var _kick_sample := -1
var _native_kick_strength := 0.0

func configure(tempo: float, meter: int = 4, length_bars: int = 8) -> void:
	bpm = clampf(tempo, 40.0, 240.0) if is_finite(tempo) else 100.0
	beats_per_bar = clampi(meter, 1, 12)
	phrase_bars = 16 if length_bars == 16 else 8
	reset()

func reset() -> void:
	audible_seconds = -1.0
	audible_samples = -1.0
	beat_phase = 0.0
	beat_index = -1
	bar_index = -1
	active = false
	kick_pulse = 0.0
	accent_pulse = 0.0
	_pending.clear()
	_last_beat = -1
	_last_samples = -1
	_last_rate = -1
	_output_samples = -INF
	_kick_seconds = -INF
	_accent_seconds = -INF
	_kick_strength = 0.0
	_accent_strength = 0.0
	_has_started = false
	_kick_count = 0
	_kick_sample = -1
	_native_kick_strength = 0.0

func set_calibration(value: float) -> void:
	if is_finite(value):
		calibration_seconds = clampf(value, -0.5, 0.5)

func set_paused(value: bool) -> void:
	paused = value
	if value:
		active = false
		kick_pulse = 0.0
		accent_pulse = 0.0

func enqueue(events: Array) -> void:
	for raw in events:
		if not raw is Dictionary or not raw.has("sample"):
			continue
		var event: Dictionary = raw
		if int(event.sample) < 0:
			continue
		if _pending.size() >= MAX_PENDING_EVENTS:
			# Preserve recent events after a stalled frame; never replay a backlog.
			_pending.pop_front()
			dropped_events += 1
		_pending.append(event)
	_pending.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sample) < int(b.sample))

func advance(mixed: int, rate: int, since_mix: float, latency: float, events: Array = [], enabled: bool = true) -> void:
	if paused:
		return
	if rate <= 0 or mixed < 0 or not is_finite(since_mix) or not is_finite(latency):
		active = false
		kick_pulse = 0.0
		accent_pulse = 0.0
		return
	if (_last_samples >= 0 and mixed < _last_samples) or (_last_rate > 0 and rate != _last_rate):
		reset()
	_last_samples = mixed
	_last_rate = rate
	enqueue(events)
	# Compute the equivalent latency formula in samples first to preserve exact
	# integer boundaries (seconds/rate round trips can lose a fraction of a sample).
	# Mixer timing and the native counter are published separately. A block can
	# reset since_mix just before its new counter is visible. Preserve forward
	# output time in that interval; calibration still shifts it independently.
	var output_samples := float(mixed)+(maxf(since_mix,0.0)-maxf(latency,0.0))*float(rate)
	_output_samples = maxf(_output_samples,output_samples)
	audible_samples = _output_samples-calibration_seconds*float(rate)
	var hearing_time := audible_samples/float(rate)
	# Audio output must have mixed a block before its extrapolated time is valid.
	active = enabled and mixed > 0 and hearing_time >= 0.0
	audible_seconds = hearing_time
	var period := 60.0 / bpm * float(rate)
	var whole_beat := int(floor(audible_samples/period)) if hearing_time >= 0.0 else -1
	if whole_beat>=0:
		# The synth triggers on llround(beat * samples_per_beat), including
		# tempos whose period is fractional. Respect that exact integer sample.
		if roundf(float(whole_beat+1)*period)<=audible_samples:
			whole_beat+=1
		elif roundf(float(whole_beat)*period)>audible_samples:
			whole_beat-=1
		var start := roundf(float(whole_beat)*period)
		var end := roundf(float(whole_beat+1)*period)
		beat_phase=clampf((audible_samples-start)/maxf(end-start,1.0),0.0,1.0)
	else:
		beat_phase=0.0
	beat_index = whole_beat % beats_per_bar if whole_beat >= 0 else -1
	bar_index = floori(float(whole_beat)/float(beats_per_bar)) if whole_beat >= 0 else -1
	if active and whole_beat != _last_beat:
		# Ordinary frames emit every boundary; a hitch emits only the current one.
		# This keeps reconnect/seek/calibration from flooding animation callbacks.
		if not _has_started or whole_beat > _last_beat:
			beat.emit(bar_index, beat_index, 1.0)
			if beat_index == 0:
				downbeat.emit(bar_index, 1.0)
				bar.emit(bar_index)
				if bar_index % phrase_bars == 0:
					phrase.emit(floori(float(bar_index)/float(phrase_bars)))
		_has_started = true
	_last_beat = maxi(_last_beat, whole_beat)
	var dispatched := 0
	while not _pending.is_empty() and float(_pending[0].sample) <= audible_samples:
		var event: Dictionary = _pending.pop_front()
		var event_time := float(event.sample) / float(rate)
		if not active or hearing_time - event_time > MAX_EVENT_AGE_SECONDS or dispatched >= MAX_EVENTS_PER_FRAME:
			dropped_events += 1
			continue
		if str(event.get("kind", "hit")) not in ["hit","interlude"]:
			continue # Grid events come from the sample clock and are never duplicated.
		var strength := clampf(float(event.get("strength", 1.0)), 0.0, 1.0)
		var track := int(event.get("track", -1))
		if track == 0:
			_kick_count+=1
			_kick_sample=int(event.sample)
			_native_kick_strength=strength
			_kick_strength = maxf(strength,_envelope(event_time,_kick_seconds,_kick_strength,KICK_DECAY))
			_kick_seconds = event_time
		if bool(event.get("accent", false)):
			_accent_strength = maxf(strength,_envelope(event_time,_accent_seconds,_accent_strength,ACCENT_DECAY))
			_accent_seconds = event_time
			accent.emit(track, strength)
		dispatched += 1
	kick_pulse = _envelope(hearing_time, _kick_seconds, _kick_strength, KICK_DECAY) if active else 0.0
	accent_pulse = _envelope(hearing_time, _accent_seconds, _accent_strength, ACCENT_DECAY) if active else 0.0

func _envelope(now: float, start: float, strength: float, decay: float) -> float:
	if start == -INF or now < start:
		return 0.0
	return exp(-(now - start) / decay) * strength

func pending_count() -> int:
	return _pending.size()

func next_beat_sample(rate: int) -> int:
	return next_beat_after_sample(maxf(audible_samples,0.0),rate,bpm)

static func next_beat_after_sample(sample: float, rate: int, tempo: float) -> int:
	var period := 60.0 / tempo * float(rate)
	var next := floorf(maxf(sample,0.0)/period)+1.0
	var result := int(roundf(next*period))
	# A rounded native boundary can lie just before the fractional mathematical
	# beat. Scheduling at that sample must still choose the following beat.
	if float(result)<=sample:
		result=int(roundf((next+1.0)*period))
	return result

func frame() -> Dictionary:
	return {"active":active,"bpm":bpm,"beat_period_seconds":60.0/bpm,"phase":beat_phase,"beat_pulse":kick_pulse,"accent_pulse":accent_pulse,"bar":bar_index,"beat":beat_index,"beat_counter":bar_index*beats_per_bar+beat_index if bar_index>=0 else -1,"audible_seconds":audible_seconds,"last_kick_seconds":_kick_seconds if is_finite(_kick_seconds) else -1.0,"last_kick_sample":_kick_sample,"last_kick_strength":_native_kick_strength,"kick_timestamp":_kick_seconds if active else -INF,"kick_strength":_native_kick_strength if active else 0.0,"kick_count":_kick_count}
