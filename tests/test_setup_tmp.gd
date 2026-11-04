extends SceneTree
func _init() -> void:
  var sequence = Sequence.new()
  var shot1 = Shot.new()
  shot1.kind = Shot.Kind.HOLD
  shot1.duration = 0.5
  var cues = []
  var cue1 = Cue.new()
  cue1.time = 0.1
  cue1.action = &"gut_pulse"
  cues.append(cue1)
  shot1.cues = cues
  sequence.add_shot(shot1)
  print("ok")
  quit()

