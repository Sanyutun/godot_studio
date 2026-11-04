@tool
extends EditorScript

func _run() -> void:
	var dir = DirAccess.open("res://")
	if dir:
		dir.make_dir_recursive("assets/pixel_anatomy")
	
	# Generate heart
	_create_heart()
	# Generate lungs
	_create_lungs()
	# Generate brain
	_create_brain()
	# Generate face
	_create_face()
	# Generate spark
	_create_spark()
	
	print("Generated pixel anatomy assets")
	EditorInterface.get_resource_filesystem().scan()

func _create_heart() -> void:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	# Simple heart shape
	var heart_color = Color(0.8, 0.2, 0.3, 1)
	for y in range(8, 24):
		for x in range(8, 24):
			var dx = x - 16
			var dy = y - 16
			if (dx*dx + dy*dy < 60 and dx*dx + (dy+4)*(dy+4) < 60) or (abs(dx) < 6 and dy > 0 and dy < 8):
				img.set_pixel(x, y, heart_color)
			elif abs(dx) < 4 and abs(dy) < 4:
				img.set_pixel(x, y, heart_color)
	
	var tex = ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://assets/pixel_anatomy/heart.png")
	img.save_png("res://assets/pixel_anatomy/heart.png")

func _create_lungs() -> void:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var lung_color = Color(0.9, 0.7, 0.8, 1)
	# Left lung
	for y in range(6, 26):
		for x in range(4, 14):
			if (x-9)*(x-9) + (y-16)*(y-16) < 70:
				img.set_pixel(x, y, lung_color)
	# Right lung
	for y in range(6, 26):
		for x in range(18, 28):
			if (x-23)*(x-23) + (y-16)*(y-16) < 70:
				img.set_pixel(x, y, lung_color)
	
	var tex = ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://assets/pixel_anatomy/lungs.png")
	img.save_png("res://assets/pixel_anatomy/lungs.png")

func _create_brain() -> void:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var brain_color = Color(0.9, 0.8, 0.7, 1)
	for y in range(8, 24):
		for x in range(6, 26):
			if (x-16)*(x-16) + (y-16)*(y-16) < 100:
				img.set_pixel(x, y, brain_color)
	# Folds
	for i in range(10):
		img.set_pixel(10 + i, 12, Color(0.8, 0.7, 0.6, 1))
		img.set_pixel(12, 14 + i, Color(0.8, 0.7, 0.6, 1))
	
	var tex = ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://assets/pixel_anatomy/brain.png")
	img.save_png("res://assets/pixel_anatomy/brain.png")

func _create_face() -> void:
	var img = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var skin_color = Color(0.95, 0.8, 0.7, 1)
	# Head
	for y in range(6, 26):
		for x in range(6, 26):
			if (x-16)*(x-16) + (y-16)*(y-16) < 120:
				img.set_pixel(x, y, skin_color)
	# Eyes
	img.set_pixel(12, 14, Color.BLACK)
	img.set_pixel(20, 14, Color.BLACK)
	# Mouth
	img.set_pixel(16, 20, Color(0.8, 0.3, 0.3, 1))
	img.set_pixel(15, 20, Color(0.8, 0.3, 0.3, 1))
	img.set_pixel(17, 20, Color(0.8, 0.3, 0.3, 1))
	
	var tex = ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://assets/pixel_anatomy/face.png")
	img.save_png("res://assets/pixel_anatomy/face.png")

func _create_spark() -> void:
	var img = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var spark_color = Color(1, 1, 0, 1)
	img.set_pixel(1, 1, spark_color)
	img.set_pixel(2, 1, spark_color)
	img.set_pixel(1, 2, spark_color)
	img.set_pixel(2, 2, spark_color)
	
	var tex = ImageTexture.create_from_image(img)
	ResourceSaver.save(tex, "res://assets/pixel_anatomy/spark.png")
	img.save_png("res://assets/pixel_anatomy/spark.png")
	
	# 2x2 version
	var img2 = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img2.fill(Color(1, 1, 0, 1))
	var tex2 = ImageTexture.create_from_image(img2)
	ResourceSaver.save(tex2, "res://assets/pixel_anatomy/spark2x2.png")
	img2.save_png("res://assets/pixel_anatomy/spark2x2.png")
