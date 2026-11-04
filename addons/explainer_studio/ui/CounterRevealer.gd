@tool
class_name CounterRevealer
extends Label
## Cue-driven counter with comma formatting

signal counter_finished

func on_cue(event: CueEvent) -> void:
	if event == null or event.cue == null:
		return
	if event.cue.action == &"counter" or event.cue.action == &"count_up":
		_animate_counter(event)

func _animate_counter(event: CueEvent) -> void:
	var data = event.cue.data
	var from_val = float(data.get("from", 0))
	var to_val = float(data.get("to", 100))
	var duration = float(data.get("duration", 1.0))
	var final_text = data.get("final_text", "")
	var use_comma = bool(data.get("format_comma", true))
	
	var tween = create_tween()
	tween.set_trans(Tween.TRANS_LINEAR)
	
	tween.tween_method(func(val: float): 
		if use_comma:
			text = _format_with_commas(int(val))
		else:
			text = str(int(val))
	, from_val, to_val, duration)
	
	tween.tween_callback(func():
		if not final_text.is_empty():
			pivot_offset = size / 2
			var pop_tween = create_tween()
			pop_tween.set_trans(Tween.TRANS_BACK)
			pop_tween.set_ease(Tween.EASE_OUT)
			text = final_text
			pop_tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.2)
			pop_tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15)
		counter_finished.emit()
	)

func _format_with_commas(num: int) -> String:
	var s = str(num)
	var result = ""
	var count = 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
