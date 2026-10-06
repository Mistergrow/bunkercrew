class_name BossMachine
extends SiegeMachine
## The final siege commander retains the same articulated chassis and real rays.
## Below half health its exposed drive trades its opening cadence for a salvo.
const TITLE := "MUTTERMASCHINE"
const HEALTH_MULTIPLIER := 1.65
var overdrive := false
var phase_flash := 0.0

func _ready() -> void:
	kind = "siege"
	elite = true
	super._ready()
	max_hp *= HEALTH_MULTIPLIER
	hp = max_hp
	profile.label = TITLE
	profile.scrap = 8
	profile.cores = 10
	set_meta("final_boss", true)
	set_meta("boss_phase", 1)
	set_meta("boss_title", TITLE)

func _physics_process(delta: float) -> void:
	phase_flash = maxf(0.0, phase_flash-delta)
	if not dead and not overdrive and hp <= max_hp*0.5:
		overdrive = true
		phase_flash = 1.4
		set_meta("boss_phase", 2)
		profile.cooldown = 2.7
		profile.burst = 2
		profile.burst_gap = 0.70
		profile.windup = 1.8
		# A longer visible charge precedes two real, independently blocked shots.
		if is_instance_valid(game) and "combat_events" in game:
			game.combat_events.event.emit("boss_phase", {"title":"ANTRIEB OFFEN", "subtitle":"MUTTERMASCHINE / DOPPELSALVE", "portrait":"siege", "final_boss":true})
		sound_phase()
	super._physics_process(delta)

func sound_phase() -> void:
	if is_instance_valid(game):
		game.sound("alarm")
		game.impact(global_position-Vector2(0,body_height),"arc",Vector2.UP,1.3)

func _draw_body() -> void:
	super._draw_body()
	# Riveted crown, twin antennae and live drive: separate from the source bitmap.
	body_part.draw_rect(Rect2(-22,-32,43,10),Color("151e21"))
	body_part.draw_rect(Rect2(-20,-30,39,5),Color("9b8966"))
	for x in [-17,-4,9]:
		body_part.draw_rect(Rect2(x,-29,5,3),Color("ebbc69"))
	for x in [-23,23]:
		body_part.draw_line(Vector2(x,-22),Vector2(x*1.2,-46),Color("29332f"),4)
		body_part.draw_rect(Rect2(x*1.2-2,-47,4,3),Color("f77454"))
	var drive := Vector2(9,-6)
	body_part.draw_rect(Rect2(drive-Vector2(9,9),Vector2(18,18)),Color("151d20"))
	for blade in 6:
		var angle := age*(4.6 if overdrive else 1.8)+blade*TAU/6
		body_part.draw_line(drive+Vector2.from_angle(angle)*3,drive+Vector2.from_angle(angle)*7,Color("ef8455") if overdrive else Color("968468"),2)
	body_part.draw_rect(Rect2(drive-Vector2(2,2),Vector2(4,4)),Color("ffe8ad") if overdrive else Color("be7350"))
