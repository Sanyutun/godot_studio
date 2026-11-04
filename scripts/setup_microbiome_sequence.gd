@tool
extends SceneTree

func _init() -> void:
	call_deferred("_setup")

func _setup() -> void:
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("sequences")
	
	var sequence = Sequence.new()
	sequence.display_name = "Microbiome: 38 Trillion Microbes"
	
	# Shot 1
	var shot1 = Shot.new()
	shot1.kind = Shot.Kind.HOLD
	shot1.duration = 0.5
	var cue1 = Cue.new()
	cue1.time = 0.1
	cue1.action = &"gut_pulse"
	shot1.cues = [cue1]
	sequence.add_shot(shot1)
	
	# Shot 2
	var shot2 = Shot.new()
	shot2.kind = Shot.Kind.PUNCH_IN
	shot2.duration = 1.3
	shot2.zoom = 2.5
	var cues2 = []
	var cue2a = Cue.new()
	cue2a.time = 0.1
	cue2a.action = &"sticker"
	cue2a.data = {"index": 0}
	cues2.append(cue2a)
	var cue2b = Cue.new()
	cue2b.time = 0.25
	cue2b.action = &"sticker"
	cue2b.data = {"index": 1}
	cues2.append(cue2b)
	var cue2c = Cue.new()
	cue2c.time = 0.4
	cue2c.action = &"sticker"
	cue2c.data = {"index": 2}
	cues2.append(cue2c)
	var cue2d = Cue.new()
	cue2d.time = 0.55
	cue2d.action = &"sticker"
	cue2d.data = {"index": 3}
	cues2.append(cue2d)
	shot2.cues = cues2
	sequence.add_shot(shot2)
	
	# Shot 3
	var shot3 = Shot.new()
	shot3.kind = Shot.Kind.PAN
	shot3.duration = 1.4
	var cues3 = []
	var cue3 = Cue.new()
	cue3.time = 0.1
	cue3.action = &"callout"
	cue3.data = {"text": "拟杆菌 Bacteroides"}
	cues3.append(cue3)
	shot3.cues = cues3
	sequence.add_shot(shot3)
	
	# Shot 4
	var shot4 = Shot.new()
	shot4.kind = Shot.Kind.PAN
	shot4.duration = 1.4
	var cues4 = []
	var cue4a = Cue.new()
	cue4a.time = 0.1
	cue4a.action = &"grid_lightup"
	cues4.append(cue4a)
	var cue4b = Cue.new()
	cue4b.time = 0.2
	cue4b.action = &"counter"
	var data4b = {"from": 0, "to": 1000, "duration": 0.8, "final_text": "1,000+ 种", "format_comma": true}
	cue4b.data = data4b
	cues4.append(cue4b)
	shot4.cues = cues4
	sequence.add_shot(shot4)
	
	# Shot 5
	var shot5 = Shot.new()
	shot5.kind = Shot.Kind.PAN
	shot5.duration = 1.8
	var cues5 = []
	var cue5a = Cue.new()
	cue5a.time = 0.1
	cue5a.action = &"bar_chart"
	var data5a = {"duration": 1.5, "show_badge": false}
	var bars_arr = []
	bars_arr.append({"label": "人体基因", "value": 20000, "color": Color.SLATE_GRAY})
	bars_arr.append({"label": "微生物基因", "value": 3000000, "color": Color.DODGER_BLUE})
	data5a["bars"] = bars_arr
	cue5a.data = data5a
	cues5.append(cue5a)
	var cue5b = Cue.new()
	cue5b.time = 1.4
	cue5b.action = &"bar_chart"
	cue5b.data = {"show_badge": true, "badge_text": "×150"}
	cues5.append(cue5b)
	shot5.cues = cues5
	sequence.add_shot(shot5)
	
	# Shot 6
	var shot6 = Shot.new()
	shot6.kind = Shot.Kind.PUNCH_OUT
	shot6.duration = 1.4
	shot6.zoom = 1.0
	var cues6 = []
	var cue6 = Cue.new()
	cue6.time = 0.1
	cue6.action = &"counter"
	cue6.data = {"from": 0, "to": 38000000000000, "duration": 1.0, "final_text": "38 万亿", "format_comma": true}
	cues6.append(cue6)
	shot6.cues = cues6
	sequence.add_shot(shot6)
	
	# Shot 7
	var shot7 = Shot.new()
	shot7.kind = Shot.Kind.PAN
	shot7.duration = 1.2
	var cues7 = []
	var cue7 = Cue.new()
	cue7.time = 0.1
	cue7.action = &"draw_path"
	cue7.data = {"duration": 1.0}
	cues7.append(cue7)
	shot7.cues = cues7
	sequence.add_shot(shot7)
	
	# Shot 8
	var shot8 = Shot.new()
	shot8.kind = Shot.Kind.FIT_RECT
	shot8.duration = 1.0
	var cues8 = []
	var cue8 = Cue.new()
	cue8.time = 0.1
	cue8.action = &"caption"
	cue8.data = {"text": "38 万亿\n你身体里的第二座城", "mode": "fade_up"}
	cues8.append(cue8)
	shot8.cues = cues8
	sequence.add_shot(shot8)
	
	var path = "res://sequences/microbiome_10s.tres"
	var err = ResourceSaver.save(sequence, path)
	print("Saved: ", err)
	quit()
