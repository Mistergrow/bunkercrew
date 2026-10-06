extends SceneTree
## Public audible cursor stays stable across mixer-block publication races.
const Clock := preload("res://scripts/music_beat_clock.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var clock := Clock.new()
	clock.configure(128.0)
	clock.advance(12000,48000,.019,.1,[{"sample":7600,"track":0,"strength":.8,"kind":"hit"}])
	var first: Dictionary = clock.frame()
	check(first.active and first.kick_count==1,"A real audible kick is consumed exactly once")
	check(first.bpm==128.0 and is_equal_approx(first.beat_period_seconds,60.0/128.0),"Presentation carries score tempo independently of drum spacing")
	clock.advance(12000,48000,.001,.1)
	var raced: Dictionary = clock.frame()
	check(raced.audible_seconds>=first.audible_seconds and raced.phase>=first.phase,"A mixer interpolation reset cannot rewind the visible beat")
	check(raced.beat_pulse<=first.beat_pulse and raced.kick_count==1,"The publication race cannot amplify or replay the heard kick")
	clock.advance(13024,48000,.001,.1)
	check(clock.frame().audible_seconds>raced.audible_seconds,"The next published audio block resumes forward presentation")
	var before := clock.audible_seconds
	clock.set_calibration(.05)
	clock.advance(13024,48000,.001,.1)
	check(is_equal_approx(clock.audible_seconds,before-.05),"Adding calibration moves the image by the requested delay")
	clock.set_calibration(-.05)
	clock.advance(13024,48000,.001,.1)
	check(is_equal_approx(clock.audible_seconds,before+.05),"Negative calibration advances the image without changing audio")
	clock.set_calibration(0.0)
	clock.set_paused(true)
	before=clock.audible_seconds
	clock.advance(20000,48000,.01,.1)
	check(clock.audible_seconds==before and not clock.frame().active,"Pause freezes the cursor and suppresses visible accents")
	clock.set_paused(false)
	clock.advance(14048,48000,.001,.1)
	check(clock.active and clock.frame().kick_count==1,"Resume keeps the same session without repeating its first kick")
	clock.advance(0,48000,0.0,.1)
	check(not clock.active and clock.frame().kick_count==0 and clock.audible_seconds<0.0,"A new playback clears the old cursor and hit identity")
	clock.advance(9600,48000,0.0,.1,[{"sample":0,"track":0,"kind":"hit","strength":.9}])
	clock.advance(9600,96000,0.0,.1)
	check(clock.frame().kick_count==0 and is_zero_approx(clock.audible_seconds),"A changed source rate cannot reuse old sample positions")
	for tempo in [90.0,128.0,147.0]:
		var sparse := Clock.new()
		sparse.configure(tempo)
		var rate := 48000
		var gap := roundi(8.0*60.0/tempo*rate)
		sparse.advance(1,rate,0.0,0.0,[{"sample":0,"track":0,"strength":.8,"kind":"hit"},{"sample":gap,"track":0,"strength":.8,"kind":"hit"}])
		var middle := roundi(gap*.5)
		sparse.advance(middle,rate,0.0,0.0)
		check(is_equal_approx(sparse.frame().beat_period_seconds,60.0/tempo) and sparse.frame().kick_count==1,"Sparse %.0f BPM music retains its authored tempo through a drum break" % tempo)
		check(sparse.frame().beat_pulse<.001 and sparse.frame().last_kick_sample==0,"Only an inaudible residual envelope remains during the drum break at %.0f BPM" % tempo)
		sparse.advance(gap,rate,0.0,0.0)
		check(sparse.frame().kick_count==2 and sparse.frame().last_kick_sample==gap,"The actual kick returning after a break is sample-aligned at %.0f BPM" % tempo)
	print("MUSIC BEAT CONTINUITY: %d/%d checks passed" % [checks-failures,checks])
	quit(1 if failures else 0)
