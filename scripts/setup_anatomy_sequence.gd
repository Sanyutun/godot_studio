@tool
extends SceneTree

func _init() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("sequences")
	
	var sequence = Sequence.new()
	sequence.display_name = "Anatomy Lab: Brain, Heart, Lungs"
	
	# Shot 1: 0.0 - 3.0s PUNCH_IN to Brain
	var shot1 = Shot.new()
	shot1.kind = Shot.Kind.PUNCH_IN
	shot1.duration = 3.0
	shot1.zoom = 2.0
	var cues1 = []
	var c1a = Cue.new()
	c1a.time = 0.5
	c1a.action = &"trigger_pulse"
	c1a.data = {"duration": 0.3}
	cues1.append(c1a)
	var c1b = Cue.new()
	c1b.time = 1.5
	c1b.action = &"trigger_pulse"
	c1b.data = {"duration": 0.3, "repeats": 1}
	cues1.append(c1b)
	var c1c = Cue.new()
	c1c.time = 2.0
	c1c.action = &"trigger_pulse"
	c1c.data = {"duration": 0.3}
	cues1.append(c1c)
	shot1.cues = cues1
	sequence.add_shot(shot1)
	
	# Shot 2: 3.0 - 6.0s PAN to Heart
	var shot2 = Shot.new()
	shot2.kind = Shot.Kind.PAN
	shot2.duration = 3.0
	var cues2 = []
	var c2a = Cue.new()
	c2a.time = 0.2
	c2a.action = &"play_organ"
	c2a.data = {"animation_name": "pump_cycle", "loop": true}
	cues2.append(c2a)
	var c2b = Cue.new()
	c2b.time = 0.5
	c2b.action = &"trigger_pulse"
	c2b.data = {"duration": 0.4, "repeats": 3}
	cues2.append(c2b)
	shot2.cues = cues2
	sequence.add_shot(shot2)
	
	# Shot 3: 6.0 - 8.0s PAN to Lungs
	var shot3 = Shot.new()
	shot3.kind = Shot.Kind.PAN
	shot3.duration = 2.0
	var cues3 = []
	var c3 = Cue.new()
	c3.time = 0.2
	c3.action = &"play_organ"
	c3.data = {"animation_name": "breathe_cycle", "loop": true}
	cues3.append(c3)
	shot3.cues = cues3
	sequence.add_shot(shot3)
	
	# Shot 4: 8.0 - 10.0s PAN to Face
	var shot4 = Shot.new()
	shot4.kind = Shot.Kind.PAN
	shot4.duration = 2.0
	var cues4 = []
	var c4a = Cue.new()
	c4a.time = 0.2
	c4a.action = &"set_expression"
	c4a.data = {"emotion": "happy"}
	cues4.append(c4a)
	var c4b = Cue.new()
	c4b.time = 1.0
	c4b.action = &"set_expression"
	c4b.data = {"emotion": "dizzy"}
	cues4.append(c4b)
	shot4.cues = cues4
	sequence.add_shot(shot4)
	
	# Shot 5: 10.0 - 12.0s PAN to Limb
	var shot5 = Shot.new()
	shot5.kind = Shot.Kind.PAN
	shot5.duration = 2.0
	var cues5 = []
	var c5 = Cue.new()
	c5.time = 0.2
	c5.action = &"pose_limb"
	c5.data = {"duration": 1.5}
	cues5.append(c5)
	shot5.cues = cues5
	sequence.add_shot(shot5)
	
	var path = "res://sequences/anatomy_pixel_lab.tres"
	var err = ResourceSaver.save(sequence, path)
	print("Saved: ", err)
	quit()
