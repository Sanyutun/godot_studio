@tool
class_name BarChartRevealer
extends Control
## Cue-driven bar chart revealer

signal animation_finished

@export var bars: Array[Dictionary] = []
@export var bar_width: float = 80.0
@export var bar_spacing: float = 40.0
@export var chart_height: float = 300.0

var _bars_container: HBoxContainer
var _bar_nodes: Array[Control] = []
var _badge_label: Label

func _ready() -> void:
	_bars_container = HBoxContainer.new()
	_bars_container.add_theme_constant_override("separation", int(bar_spacing))
	add_child(_bars_container)
	
	_badge_label = Label.new()
	_badge_label.visible = false
	_badge_label.add_theme_font_size_override("font_size", 48)
	_badge_label.add_theme_color_override("font_color", Color.RED)
	add_child(_badge_label)
	
	_setup_bars()

func _setup_bars() -> void:
	for child in _bars_container.get_children():
		child.queue_free()
	_bar_nodes.clear()
	
	for bar_data in bars:
		var bar_container = VBoxContainer.new()
		bar_container.alignment = BoxContainer.ALIGNMENT_END
		
		var bar = ColorRect.new()
		bar.custom_minimum_size = Vector2(bar_width, 10)
		bar.scale.y = 0.0
		bar.color = bar_data.get("color", Color.SLATE_GRAY)
		bar.pivot_offset.y = 10
		bar_container.add_child(bar)
		
		var label = Label.new()
		label.text = bar_data.get("label", "")
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bar_container.add_child(label)
		
		_bars_container.add_child(bar_container)
		_bar_nodes.append(bar)

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"bar_chart":
		_animate_bars(event)
	elif event.cue.action == &"show_bar_chart":
		_animate_bars(event)

func _animate_bars(event: CueEvent) -> void:
	var data = event.cue.data
	var duration = float(data.get("duration", 1.5))
	var show_badge = bool(data.get("show_badge", false))
	
	if bars.is_empty():
		return
	
	# Find max value for normalization
	var max_val = 0.0
	for bar_data in bars:
		max_val = max(max_val, float(bar_data.get("value", 1)))
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.set_ease(Tween.EASE_OUT)
	
	for i in range(_bar_nodes.size()):
		if i < bars.size():
			var bar = _bar_nodes[i]
			var target_height = (float(bars[i].get("value", 1)) / max_val) * chart_height
			bar.custom_minimum_size.y = target_height
			tween.tween_property(bar, "scale:y", 1.0, duration).set_delay(i * 0.1)
	
	if show_badge:
		tween.chain()
		tween.tween_callback(_show_badge.bind(event)).set_delay(duration + 0.2)
	
	tween.finished.connect(func(): animation_finished.emit())

func _show_badge(event: CueEvent) -> void:
	_badge_label.text = event.cue.data.get("badge_text", "×150")
	_badge_label.visible = true
	_badge_label.scale = Vector2(0.5, 0.5)
	
	# Position near the last bar
	if _bar_nodes.size() > 0:
		var last_bar = _bar_nodes[-1]
		_badge_label.global_position = last_bar.global_position + Vector2(last_bar.size.x + 10, -50)
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_badge_label, "scale", Vector2(1.2, 1.2), 0.3)
	tween.tween_property(_badge_label, "scale", Vector2(1.0, 1.0), 0.1)
	
	# Squash and stretch effect
	tween.parallel().tween_property(_badge_label, "scale:y", 0.8, 0.15)
	tween.parallel().tween_property(_badge_label, "scale:x", 1.3, 0.15)
	tween.tween_property(_badge_label, "scale", Vector2(1.0, 1.0), 0.15)
