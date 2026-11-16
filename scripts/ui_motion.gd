class_name UiMotion
extends RefCounted
## One place for interface motion: durations, easing and the reduced-effects
## fallback. Motion is presentation only. It never delays focus, input or state:
## callers read a 0..1 progress value while drawing and everything is already
## interactive at progress 0.
##
## Reduced effects (Options > "Effekte reduzieren" / F3) make every helper return
## its settled value, so screens appear instantly and nothing pulses.
## Script-driven runs (tests, galleries, capture tools started with --script)
## default to the settled state too, which keeps pinned stills deterministic;
## they opt in with `UiMotion.force(true)` or the `--ui-motion` user argument.

const QUICK := 0.12 ## Press feedback, focus glide.
const BASE := 0.16 ## Panels, pages, toasts entering.
const SLOW := 0.22 ## Large surfaces and leaving toasts.
const STAGE := 0.07 ## Stagger between rows of a staged reveal.
const COUNT := 0.6 ## Value count-up on result screens.
const PULSE_PERIOD := 1.6 ## Slow warning pulse: 0.625 Hz, far below strobe range.
const SLIDE := 8.0 ## Travel of an entering surface in design pixels.

static var reduced := false
static var _forced := -1
static var _automation := -1
static var _manual_clock := -1.0
## Capture tools slow every motion uniformly to photograph it frame by frame.
static var time_scale := 1.0


## Tests and capture tools select real motion (true), settled output (false) or
## the automatic default again (null).
static func force(value: Variant) -> void:
	_forced = -1 if value == null else int(bool(value))


static func enabled() -> bool:
	if _forced >= 0: return _forced == 1
	if reduced: return false
	if _automation < 0:
		var loop := Engine.get_main_loop()
		var scripted: bool = loop != null and loop.get_script() != null and "--ui-motion" not in OS.get_cmdline_user_args()
		_automation = 1 if scripted or DisplayServer.get_name() == "headless" else 0
	return _automation == 0


## Capture tools step a manual clock for evenly spaced frame sequences.
static func set_manual_clock(seconds: float) -> void:
	_manual_clock = seconds


static func now() -> float:
	return _manual_clock if _manual_clock >= 0.0 else Time.get_ticks_usec()/1000000.0*time_scale


static func ease_out(value: float) -> float:
	var inverse := 1.0-clampf(value,0.0,1.0)
	return 1.0-inverse*inverse*inverse


static func ease_in_out(value: float) -> float:
	value = clampf(value,0.0,1.0)
	return value*value*(3.0-2.0*value)


## Linear 0..1 since `started`; 1 when motion is off.
static func linear(started: float, duration: float = BASE, delay: float = 0.0) -> float:
	if not enabled() or duration <= 0.0: return 1.0
	return clampf((now()-started-delay)/duration,0.0,1.0)


## Eased 0..1 since `started`; 1 when motion is off.
static func progress(started: float, duration: float = BASE, delay: float = 0.0) -> float:
	return ease_out(linear(started,duration,delay))


static func running(started: float, duration: float = BASE, delay: float = 0.0) -> bool:
	return enabled() and now()-started < duration+delay


## Frame-rate independent settle toward a moving target, used for focus markers
## and bars. Retargeting mid-flight is seamless; it snaps when motion is off.
static func approach(current: float, target: float, delta: float, duration: float = QUICK) -> float:
	if not enabled() or duration <= 0.0 or absf(target-current) < 0.5: return target
	return lerpf(current,target,1.0-exp(-delta*time_scale*4.6/duration))


static func approach_ratio(current: float, target: float, delta: float, duration: float = BASE) -> float:
	if not enabled() or duration <= 0.0 or absf(target-current) < 0.002: return target
	return lerpf(current,target,1.0-exp(-delta*time_scale*4.6/duration))


static func approach_rect(current: Rect2, target: Rect2, delta: float, duration: float = QUICK) -> Rect2:
	if not enabled() or not current.has_area(): return target
	return Rect2(Vector2(approach(current.position.x,target.position.x,delta,duration),approach(current.position.y,target.position.y,delta,duration)),
		Vector2(approach(current.size.x,target.size.x,delta,duration),approach(current.size.y,target.size.y,delta,duration)))


## Displayed value for a count-up that began at `started`.
static func count(from: float, to: float, started: float, duration: float = COUNT, delay: float = 0.0) -> float:
	return lerpf(from,to,progress(started,duration,delay))


## Slow 0..1 warning pulse. Constant 0 when motion is off, so the warning state
## stays readable through colour alone.
static func pulse(period: float = PULSE_PERIOD) -> float:
	if not enabled(): return 0.0
	return 0.5-0.5*cos(now()*TAU/maxf(period,1.0))


## Fade a freshly opened surface in. Controls stay interactive throughout and
## keep their layout rectangle; a second call restarts cleanly.
static func fade_in(control: CanvasItem, duration: float = BASE, delay: float = 0.0) -> void:
	if not is_instance_valid(control): return
	if control.has_meta("ui_motion_fade"):
		var previous: Variant = control.get_meta("ui_motion_fade")
		if previous is Tween and previous.is_valid(): previous.kill()
	if not enabled() or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	control.modulate.a = 0.0
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.set_speed_scale(time_scale)
	if delay > 0.0: tween.tween_interval(delay)
	tween.tween_property(control,"modulate:a",1.0,duration)
	control.set_meta("ui_motion_fade",tween)


## Bring a freshly opened surface in: it fades in while it travels `travel`
## design pixels into its rest position, eased out (cubic), on whole design
## pixels. Panels rise from below, a new page slides in from the side.
## Controls are interactive and focusable from the first frame (only their
## drawing travels); a second call restarts from the rest position. With
## motion off (reduced effects, scripted runs) it is settled at once.
static func enter(control: CanvasItem, travel: Vector2 = Vector2(0,SLIDE*2.0), duration: float = SLOW, delay: float = 0.0) -> void:
	if not is_instance_valid(control): return
	var rest := _settle(control)
	if not enabled() or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	control.set_meta("ui_motion_rest",rest)
	control.modulate.a = 0.0
	_place(control,rest,travel)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_speed_scale(time_scale)
	tween.set_parallel(true)
	tween.tween_property(control,"modulate:a",1.0,duration*0.75).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_method(func(offset: Vector2): _place(control,rest,offset),travel,Vector2.ZERO,duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.chain().tween_callback(func(): _arrive(control,rest))
	control.set_meta("ui_motion_fade",tween)


## The mirror of enter() for a surface that is leaving: it fades out while it
## sinks `travel` design pixels (eased in), then `done` runs (usually
## queue_free). With motion off `done` runs at once. `host` owns the tween when
## the leaving control itself no longer processes.
static func leave(control: CanvasItem, done: Callable, travel: Vector2 = Vector2(0,SLIDE), duration: float = BASE, host: Node = null) -> void:
	if not is_instance_valid(control): return
	var rest := _settle(control)
	if not enabled() or not control.is_inside_tree():
		done.call()
		return
	control.set_meta("ui_motion_rest",rest)
	var tween := (host if is_instance_valid(host) else control).create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_speed_scale(time_scale)
	tween.set_parallel(true)
	tween.tween_property(control,"modulate:a",0.0,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_method(func(offset: Vector2): _place(control,rest,offset),Vector2.ZERO,travel,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(done)
	control.set_meta("ui_motion_fade",tween)


## Bring an opaque surface in without a fade, for surfaces that rest over the
## live match: hidden until `delay` has passed, then fully opaque from its first
## visible frame while it rises `travel` design pixels into place (eased out,
## whole design pixels). No word on it is ever drawn semi-transparent over the
## scene. Controls are focusable from the first frame; with motion off it is
## settled at once.
static func rise(control: CanvasItem, travel: Vector2 = Vector2(0,SLIDE*2.0), duration: float = SLOW, delay: float = 0.0) -> void:
	if not is_instance_valid(control): return
	var rest := _settle(control)
	if not enabled() or not control.is_inside_tree():
		control.modulate.a = 1.0
		return
	control.set_meta("ui_motion_rest",rest)
	control.modulate.a = 0.0 if delay > 0.0 else 1.0
	_place(control,rest,travel)
	var tween := control.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_speed_scale(time_scale)
	if delay > 0.0:
		tween.tween_interval(delay)
		tween.tween_callback(func():
			if is_instance_valid(control): control.modulate.a = 1.0)
	tween.tween_method(func(offset: Vector2): _place(control,rest,offset),travel,Vector2.ZERO,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func(): _arrive(control,rest))
	control.set_meta("ui_motion_fade",tween)


## The mirror of rise(): the surface stays fully opaque while it sinks
## `travel` design pixels (eased in), then `done` runs (usually queue_free).
## With motion off `done` runs at once. `host` owns the tween when the leaving
## control itself no longer processes.
static func sink(control: CanvasItem, done: Callable, travel: Vector2 = Vector2(0,SLIDE), duration: float = QUICK, host: Node = null) -> void:
	if not is_instance_valid(control): return
	var rest := _settle(control)
	if not enabled() or not control.is_inside_tree():
		done.call()
		return
	control.set_meta("ui_motion_rest",rest)
	control.modulate.a = 1.0
	var tween := (host if is_instance_valid(host) else control).create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_speed_scale(time_scale)
	tween.tween_method(func(offset: Vector2): _place(control,rest,offset),Vector2.ZERO,travel,duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_callback(done)
	control.set_meta("ui_motion_fade",tween)


## Stops a running enter/leave of `control`, puts it back on its rest
## position and returns that position.
static func _settle(control: CanvasItem) -> Vector2:
	if control.has_meta("ui_motion_fade"):
		var previous: Variant = control.get_meta("ui_motion_fade")
		if previous is Tween and previous.is_valid(): previous.kill()
		control.remove_meta("ui_motion_fade")
	var rest: Vector2 = control.get("position")
	if control.has_meta("ui_motion_rest"):
		rest = control.get_meta("ui_motion_rest")
		control.remove_meta("ui_motion_rest")
	control.set("position",rest)
	return rest


static func _arrive(control: CanvasItem, rest: Vector2) -> void:
	if not is_instance_valid(control): return
	control.remove_meta("ui_motion_fade")
	control.remove_meta("ui_motion_rest")
	control.set("position",rest)


static func _place(control: CanvasItem, rest: Vector2, offset: Vector2) -> void:
	if is_instance_valid(control): control.set("position",rest+offset.round())


## Staged reveal alpha for row `index` of a sequence started at `started`.
static func stage(started: float, index: int, duration: float = BASE, step: float = STAGE) -> float:
	return progress(started,duration,index*step)


## Draw offset of an entering row: starts SLIDE below/right and settles at zero.
static func slide(amount: float, reveal: float) -> float:
	return roundf(amount*(1.0-reveal))


static func faded(color: Color, reveal: float) -> Color:
	return Color(color,color.a*reveal)
