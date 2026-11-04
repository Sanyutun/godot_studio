@tool
class_name PixelElectroPulse
extends Path2D
## Nerve/heart conduction pathway with deterministic pulse

@export var pulse_scene: PackedScene
@export var use_glow: bool = true

func _ready() -> void:
	if use_glow:
		var spark = find_child("Spark", true, false)
		if spark and spark is Sprite2D and spark.material == null:
			var shader = load("res://addons/explainer_studio/shaders/pixel_glow.gdshader")
			if shader:
				var mat = ShaderMaterial.new()
				mat.shader = shader
				mat.set_shader_parameter("glow_intensity", 2.0)
				mat.set_shader_parameter("glow_color", Color(1, 1, 0.3, 1))
				mat.set_shader_parameter("pulse_speed", 3.0)
				spark.material = mat

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"trigger_pulse":
		_trigger_pulse(event)
	elif event.cue.action == &"pulse_chain":
		_trigger_chain(event)

func _trigger_pulse(event: CueEvent) -> void:
	var data = event.cue.data
	var duration = float(data.get("duration", 0.5))
	var repeats = int(data.get("repeats", 1))
	var speed_curve = data.get("curve", Tween.TRANS_LINEAR)
	
	var follow = get_node_or_null("PathFollow2D")
	if follow == null:
		follow = find_child("PathFollow2D", true, false)
	
	if follow and follow is PathFollow2D:
		_animate_pulse(follow, duration, repeats, speed_curve)

func _trigger_chain(event: CueEvent) -> void:
	# Chain pulses across multiple paths
	var duration = float(event.cue.data.get("duration", 0.3))
	var delay = 0.0
	for child in get_children():
		if child is Path2D and child != self:
			var follow = child.find_child("PathFollow2D", true, false)
			if follow:
				var tween = create_tween()
				tween.tween_interval(delay)
				delay += 0.15
				tween.tween_callback(func(f = follow): 
					var t2 = create_tween()
					f.progress_ratio = 0.0
					t2.tween_property(f, "progress_ratio", 1.0, duration)
				)

func _animate_pulse(follow: PathFollow2D, duration: float, repeats: int, curve = Tween.TRANS_LINEAR) -> void:
	var tween = create_tween()
	tween.set_loops(repeats)
	tween.set_trans(curve)
	follow.progress_ratio = 0.0
	tween.tween_property(follow, "progress_ratio", 1.0, duration)
	
	# Add glow effect
	var spark = follow.get_child(0) if follow.get_child_count() > 0 else null
	if spark and spark is Sprite2D:
		var glow_tween = create_tween()
		glow_tween.set_loops(repeats * 2)
		glow_tween.set_trans(Tween.TRANS_SINE)
		glow_tween.set_ease(Tween.EASE_IN_OUT)
		glow_tween.tween_property(spark, "scale", Vector2(1.5, 1.5), duration * 0.2)
		glow_tween.tween_property(spark, "scale", Vector2(1.0, 1.0), duration * 0.2)
		glow_tween.tween_property(spark, "modulate", Color(3, 3, 1, 1), duration * 0.15)
		glow_tween.tween_property(spark, "modulate", Color(1, 1, 1.5, 1), duration * 0.15)
