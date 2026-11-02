extends "res://tests/support/test_case.gd"
## M4 test 2 — ffmpeg command execution, exit codes and result metadata, using
## an injected process runner so the suite never needs a real ffmpeg binary.

const OUTPUT_DIR := "user://m4_encoder"
const OUTPUT_PATH := "user://m4_encoder/take.mp4"


func _run_tests() -> void:
	_clean()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

	var settings := RenderSettings.new()
	settings.output_path = OUTPUT_PATH
	settings.frames_dir = "user://m4_encoder/frames"
	settings.fps = 24
	settings.crf = 20
	settings.preset = "veryfast"

	var encoder := FfmpegEncoder.new("fake-ffmpeg")
	check(encoder.ffmpeg_path == "fake-ffmpeg", "encoder keeps the configured executable")
	# A profile's default "ffmpeg" wins over the encoder default. Clear it to
	# exercise the fallback path explicitly.
	settings.ffmpeg_path = ""

	var captured_executable: Array[String] = []
	var captured_args: Array[PackedStringArray] = []
	encoder.process_runner = func(
		executable: String, args: PackedStringArray, output: Array
	) -> int:
		captured_executable.append(executable)
		captured_args.append(args.duplicate())
		if args.has("-version"):
			return 0
		_write_output(args)
		output.append("frame= 42")
		return 0

	var result := encoder.encode(settings)
	check(bool(result.get("ok", false)), "successful process reports ok")
	check(int(result.get("exit_code", -1)) == 0, "successful process reports exit code 0")
	check(captured_executable.size() == 1, "executable invoked once")
	check(captured_executable[0] == "fake-ffmpeg", "profile executable is used")
	check(
		captured_args[0] == settings.build_ffmpeg_args(),
		"result carries the exact command"
	)
	check(String(result.get("output", "")) == "frame= 42", "result carries process output")
	check(
		FileAccess.file_exists(settings.get_resolved_output_path()),
		"successful encode leaves an output file"
	)

	captured_executable.clear()
	captured_args.clear()
	settings.ffmpeg_path = "other-ffmpeg"
	var override_result := encoder.encode(settings)
	check(captured_executable.size() == 1, "override executable invoked")
	check(captured_executable[0] == "other-ffmpeg", "profile executable overrides encoder default")
	check(bool(override_result.get("ok", false)), "override executable succeeds")

	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, output: Array
	) -> int:
		if args.has("-version"):
			return 0
		output.append("Unknown encoder 'libx264'")
		output.append("Conversion failed!")
		return 1
	var failure := encoder.encode(settings)
	check(not bool(failure.get("ok", true)), "non-zero exit reports failure")
	check(int(failure.get("exit_code", 0)) == 1, "failure preserves the exit code")
	check(
		String(failure.get("output", "")).contains("Unknown encoder"),
		"failure preserves ffmpeg output"
	)

	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, output: Array
	) -> int:
		output.append(" ".join(args))
		return 0
	check(encoder.is_available(), "availability check uses the runner")
	var version_args: Array[PackedStringArray] = []
	encoder.process_runner = func(
		_executable: String, args: PackedStringArray, _output: Array
	) -> int:
		version_args.append(args.duplicate())
		return 127
	check(not encoder.is_available(), "missing executable reports unavailable")
	check(version_args.size() == 1, "availability check runs once")
	check(version_args[0] == PackedStringArray(["-version"]), "availability uses -version")

	var availability_paths: Array[String] = []
	settings.ffmpeg_path = "profile-ffmpeg"
	encoder.ffmpeg_path = "encoder-ffmpeg"
	encoder.process_runner = func(
		executable: String, _args: PackedStringArray, _output: Array
	) -> int:
		availability_paths.append(executable)
		return 0
	check(encoder.is_available(settings), "availability accepts a profile")
	check(
		availability_paths[0] == "profile-ffmpeg",
		"availability uses the profile executable"
	)

	DirAccess.remove_absolute(ProjectSettings.globalize_path(OUTPUT_PATH))
	encoder.process_runner = func(
		_executable: String, _args: PackedStringArray, _output: Array
	) -> int:
		return 0
	var missing_output := encoder.encode(settings)
	check(
		not bool(missing_output.get("ok", true)),
		"exit code 0 without an output file reports failure"
	)
	check(
		String(missing_output.get("output", "")).contains("did not create"),
		"missing output failure explains the problem"
	)

	var null_result := encoder.encode(null)
	check(not bool(null_result.get("ok", true)), "null settings fail cleanly")
	check(int(null_result.get("exit_code", 0)) == -1, "null settings report exit code -1")

	_clean()
	finish()


func _write_output(args: PackedStringArray) -> void:
	if args.is_empty():
		return
	var file := FileAccess.open(String(args[args.size() - 1]), FileAccess.WRITE)
	if file != null:
		file.store_string("fake mp4")
		file.close()


func _clean() -> void:
	var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
