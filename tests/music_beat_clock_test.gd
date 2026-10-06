extends SceneTree
const Clock := preload("res://scripts/music_beat_clock.gd")
const Calibration := preload("res://scripts/music_calibration.gd")
var checks := 0
var failures := 0
var counts := {"beat":0,"downbeat":0,"bar":0,"phrase":0,"accent":0}

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func run() -> void:
	var clock := Clock.new()
	clock.configure(120.0,4,8)
	clock.beat.connect(func(_a: int,_b: int,_s: float) -> void: counts.beat+=1)
	clock.downbeat.connect(func(_a: int,_s: float) -> void: counts.downbeat+=1)
	clock.bar.connect(func(_a: int) -> void: counts.bar+=1)
	clock.phrase.connect(func(_a: int) -> void: counts.phrase+=1)
	clock.accent.connect(func(_a: int,_s: float) -> void: counts.accent+=1)
	clock.advance(2400,48000,0.0,0.1,[{"sample":0,"track":0,"strength":0.8,"accent":true,"kind":"hit"}])
	check(not clock.active and counts.beat==0 and counts.accent==0 and clock.pending_count()==1,"A mixed kick remains pending while the output buffer is not yet audible")
	clock.advance(4800,48000,0.0,0.1)
	check(clock.active and counts.beat==1 and counts.downbeat==1 and counts.bar==1 and counts.phrase==1 and counts.accent==1,"The first downbeat and native accent dispatch when sample zero becomes audible")
	check(is_equal_approx(clock.kick_pulse,0.8),"Envelope starts at the native hit strength")
	check(clock.frame().kick_count==1 and clock.frame().last_kick_sample==0 and clock.frame().last_kick_strength==0.8,"Presentation exposes the audible native kick identity and actual strength")
	clock.advance(9600,48000,0.0,0.1)
	check(absf(clock.kick_pulse-0.8*exp(-0.1/clock.KICK_DECAY))<0.00001,"Analytical decay follows elapsed audible time instead of frame count")
	check(counts.beat==1,"Frames inside the same beat do not duplicate signals")
	clock.advance(24000,48000,0.0,0.1,[{"sample":24000,"track":0,"strength":1.0,"accent":false}])
	check(clock.pending_count()==1 and counts.beat==1,"The next mixed beat still waits for output latency")
	clock.advance(28800,48000,0.0,0.1)
	check(counts.beat==2 and clock.beat_index==1 and is_zero_approx(clock.beat_phase),"Second audible beat is sample-aligned after latency compensation")
	clock.set_calibration(0.15)
	clock.advance(43200,48000,0.02,0.1)
	check(absf(clock.audible_seconds-0.67)<0.000001,"Calibration subtracts extra output delay while including since-last-mix interpolation")
	clock.set_calibration(NAN)
	check(is_equal_approx(clock.calibration_seconds,0.15),"Invalid calibration cannot corrupt the presentation clock")
	clock.set_paused(true)
	var paused_time := clock.audible_seconds
	clock.advance(48000,48000,0.04,0.1)
	check(not clock.active and clock.kick_pulse==0.0 and clock.audible_seconds==paused_time,"Pause freezes the hearing cursor and clears visible pulses")
	clock.set_paused(false)
	clock.advance(48000,48000,0.0,0.1,[],false)
	check(not clock.active and clock.accent_pulse==0.0,"Muted music emits no rhythm movement")
	clock.set_calibration(0.0)
	var before: int = counts.beat
	clock.advance(48000*80,48000,0.0,0.1)
	check(counts.beat-before<=1,"A long stall or reconnect emits no history of missed beats")
	clock.advance(0,48000,0.0,0.1)
	check(clock.pending_count()==0 and not clock.active,"A sample counter reset starts a clean session without stale events")
	clock.advance(100,0,0.0,0.1)
	check(not clock.active,"An unavailable mixer rate disables presentation safely")
	var flood: Array = []
	for index in 3000:
		flood.append({"sample":index+48000,"track":0,"strength":1.0,"accent":true})
	clock.advance(1,48000,0.0,0.0,flood)
	check(clock.pending_count()<=clock.MAX_PENDING_EVENTS,"Pending mixer events stay bounded under a flood")
	check(clock.dropped_events>=952,"Dropped events are recorded instead of growing memory indefinitely")
	clock.advance(480000,48000,0.0,0.0)
	check(clock.pending_count()==0 and clock.kick_pulse==0.0,"Old native hits are discarded after a hitch and cannot resurrect a pulse")
	var fractional := Clock.new()
	fractional.configure(104.0)
	var observed := [0]
	fractional.beat.connect(func(_a: int,_b: int,_s: float) -> void: observed[0]+=1)
	var rate := 44100
	fractional.advance(1,rate,0.0,0.0)
	for index in range(1,16):
		var boundary := int(roundf(float(index)*60.0/104.0*float(rate)))
		fractional.advance(boundary-1,rate,0.0,0.0)
		check(observed[0]==index,"Fractional-period beat %d cannot dispatch one sample early"%index)
		fractional.advance(boundary,rate,0.0,0.0)
		check(observed[0]==index+1 and fractional.beat_phase<0.0001,"Fractional-period beat %d dispatches on its exact native integer sample"%index)
		check(fractional.next_beat_sample(rate)==int(roundf(float(index+1)*60.0/104.0*float(rate))),"Scheduling after native boundary %d chooses the following exact integer beat"%index)
	for fps in [30,60,144]:
		var sampled := Clock.new()
		sampled.configure(120.0)
		var beat_times: Array[float] = []
		var cursor := [0.0]
		sampled.beat.connect(func(_a: int,_b: int,_s: float) -> void: beat_times.append(cursor[0]))
		for frame in fps*5+1:
			var seconds := float(frame)/float(fps)
			cursor[0] = seconds
			sampled.advance(int(round((seconds+0.1)*48000.0)),48000,0.0,0.1)
		check(beat_times.size()==11,"%d FPS observes all eleven boundaries in five seconds"%fps)
		var worst := 0.0
		for index in beat_times.size():
			worst=maxf(worst,absf(beat_times[index]-float(index)*0.5))
		check(worst<=1.0/float(fps)+1.0/48000.0,"%d FPS visual dispatch is within one frame of the sample boundary"%fps)
	var taps := Calibration.new()
	taps.begin(100.0)
	for index in 12:
		check(taps.tap(float(index)*0.6+0.180+float(index%3-1)*0.004),"Calibration accepts independent beat tap %d"%index)
	var result := taps.result()
	check(bool(result.ready) and absf(float(result.seconds)-0.18)<0.006,"Bluetooth-sized extra delay is recovered robustly from taps")
	check(float(result.jitter)<0.01 and float(result.confidence)>0.85,"Steady taps receive a useful confidence estimate")
	check(not taps.tap(taps.previous_tap+0.01),"A double tap is ignored")
	taps.offsets.append(-0.25)
	check(absf(float(taps.result().seconds)-0.18)<0.006,"A single mistaken tap does not distort the median calibration")
	taps.begin()
	check(not taps.result().ready,"Clearing calibration requires a fresh complete measurement")
	print("MUSIC BEAT CLOCK: %d/%d checks passed"%[checks-failures,checks])
	quit(1 if failures else 0)
