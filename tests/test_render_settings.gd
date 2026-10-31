extends "res://tests/support/test_case.gd"
## M4 test 1 — render profile math, frame naming, ffmpeg argument building and
## validation.

const AUDIO_PATH := "user://m4_settings_audio.wav"


func _run_tests() -> void:
	_frame_count_math()
	_frame_paths_and_patterns()
	_ffmpeg_arguments()
	_validation()

	if FileAccess.file_exists(AUDIO_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(AUDIO_PATH))
	finish()


func _frame_count_math() -> void:
	var settings := RenderSettings.new()
	check(settings.fps == 60, "default render is 60 fps")
	check(settings.get_frame_count(10.8) == 648, "10.8s at 60 fps is 648 frames")
	check(settings.get_frame_count(0.1) == 6, "0.1s at 60 fps is 6 frames")
	check(settings.get_frame_count(0.0) == 0, "zero duration needs no frames")
	check(settings.get_frame_count(-1.0) == 0, "negative duration needs no frames")

	settings.fps = 30
	check(settings.get_frame_count(1.0) == 30, "1s at 30 fps is 30 frames")
	check(settings.get_frame_count(0.11) == 4, "partial frames round up")
	check_approx(settings.get_frame_time(0), 0.0, 0.000001, "frame 0 is time 0")
	check_approx(settings.get_frame_time(15), 0.5, 0.000001, "frame 15 at 30 fps is 0.5s")
	check_approx(settings.get_frame_time(29), 29.0 / 30.0, 0.000001, "last frame time")

	settings.fps = 0
	check(settings.get_frame_count(10.0) == 0, "fps 0 cannot produce frames")
	check_approx(settings.get_frame_time(5), 0.0, 0.000001, "fps 0 frame time is 0")


func _frame_paths_and_patterns() -> void:
	var settings := RenderSettings.new()
	settings.output_path = "user://renders/take.mp4"
	settings.frames_dir = ""
	check(
		settings.get_frames_dir() == "user://renders/take_frames",
		"frames dir derives from output basename"
	)
	check(
		settings.get_frame_filename(0) == "frame_000000.png", "frame names are zero padded"
	)
	check(
		settings.get_frame_filename(123) == "frame_000123.png", "frame index is preserved"
	)
	check(
		settings.get_frame_path(7) == "user://renders/take_frames/frame_000007.png",
		"frame path joins directory and filename"
	)
	check(
		settings.get_frame_pattern().ends_with("/take_frames/frame_%06d.png"),
		"ffmpeg pattern uses the six digit placeholder"
	)
	check(
		settings.get_resolved_frames_dir().is_absolute_path(),
		"resolved frames dir is an absolute path"
	)
	check(
		settings.get_resolved_output_path().ends_with("take.mp4"),
		"resolved output keeps the file name"
	)

	settings.frames_dir = "res://frames/m4"
	check(settings.get_frames_dir() == "res://frames/m4", "explicit frames dir wins")
	settings.frames_dir = ""


func _ffmpeg_arguments() -> void:
	var settings := RenderSettings.new()
	settings.output_path = "user://renders/take.mp4"
	settings.fps = 30
	settings.crf = 21
	settings.preset = "fast"
	var args := settings.build_ffmpeg_args()
	var joined := " ".join(args)
	check(args.has("-y"), "overwrite adds -y")
	check(joined.contains("-framerate 30"), "input framerate matches settings")
	check(joined.contains("-start_number 0"), "frame numbering starts at zero")
	check(joined.contains("-c:v libx264"), "default video codec is libx264")
	check(joined.contains("-preset fast"), "preset is forwarded")
	check(joined.contains("-crf 21"), "crf is forwarded")
	check(joined.contains("-pix_fmt yuv420p"), "pixel format is forwarded")
	check(
		joined.contains(settings.get_resolved_frame_pattern()),
		"ffmpeg reads the resolved frame pattern"
	)
	check(
		args[args.size() - 1] == settings.get_resolved_output_path(),
		"output path is the final argument"
	)
	check(not joined.contains("-c:a"), "silent renders do not add an audio codec")

	settings.overwrite = false
	check(settings.build_ffmpeg_args().has("-n"), "overwrite false adds -n")

	settings.overwrite = true
	settings.video_codec = "libx265"
	settings.extra_args = PackedStringArray(["-tag:v", "hvc1"])
	var custom_args := settings.build_ffmpeg_args()
	var custom_joined := " ".join(custom_args)
	check(custom_joined.contains("-c:v libx265"), "custom codec is forwarded")
	check(custom_joined.contains("-tag:v hvc1"), "extra args are forwarded")
	check(
		custom_args[custom_args.size() - 1] == settings.get_resolved_output_path(),
		"extra args stay before the output path"
	)

	var wave := FileAccess.open(AUDIO_PATH, FileAccess.WRITE)
	if wave == null:
		check(false, "could not create temporary audio file")
		return
	wave.store_string("RIFF")
	wave.close()
	settings.audio_path = AUDIO_PATH
	var audio_args := settings.build_ffmpeg_args()
	var audio_joined := " ".join(audio_args)
	check(audio_joined.contains("-c:a aac"), "audio codec is added for muxed audio")
	check(audio_joined.contains("-b:a 192k"), "audio bitrate is forwarded")
	check(audio_joined.contains("-shortest"), "audio muxing stops at the shorter input")
	check(audio_joined.contains("-af apad"), "short narration is padded to the picture")
	check(
		audio_joined.contains(settings.get_resolved_audio_path()),
		"audio input uses the resolved path"
	)

	settings.output_path = "user://renders/take.mkv"
	var matroska := " ".join(settings.build_ffmpeg_args())
	check(not matroska.contains("-movflags"), "non-MP4 containers skip faststart")
	settings.output_path = "user://renders/take.mp4"


func _validation() -> void:
	var settings := RenderSettings.new()
	settings.output_path = "user://renders/take.mp4"
	settings.frames_dir = "user://renders/take_frames"
	check(settings.validate(10.0).is_empty(), "default profile validates cleanly")

	settings.fps = 0
	settings.output_path = ""
	settings.ffmpeg_path = ""
	settings.video_codec = ""
	settings.pixel_format = ""
	settings.crf = 99
	settings.resolution = Vector2i(-1, 0)
	settings.audio_path = "user://missing_m4_audio.wav"
	var issues := settings.validate(0.0)
	check(_has_issue(issues, "fps"), "fps below 1 is reported")
	check(_has_issue(issues, "Output path"), "empty output path is reported")
	check(_has_issue(issues, "ffmpeg"), "empty ffmpeg path is reported")
	check(_has_issue(issues, "codec"), "empty video codec is reported")
	check(_has_issue(issues, "Pixel format"), "empty pixel format is reported")
	check(_has_issue(issues, "CRF"), "out-of-range crf is reported")
	check(_has_issue(issues, "Resolution"), "negative resolution is reported")
	check(_has_issue(issues, "Audio file"), "missing audio file is reported")


func _has_issue(issues: PackedStringArray, needle: String) -> bool:
	for issue in issues:
		if issue.contains(needle):
			return true
	return false
