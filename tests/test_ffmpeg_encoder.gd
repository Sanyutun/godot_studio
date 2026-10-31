extends "res://tests/support/test_case.gd"
## M4 test 2 — ffmpeg command execution, exit codes and result metadata, using
## an injected process runner so the suite never needs a real ffmpeg binary.

func _run_tests() -> void:
	var settings := RenderSettings.new()
	settings.output_path = "user://m4_encoder/take.mp4"
	settings.frames_dir = "user://m4_encoder/frames"
	settings.fps = 24
	settings.crf = 20
	settings.preset = "veryfast"

	var encoder := FfmpegEncoder.new("fake-ffmpeg")
	check(encoder.ffmpeg_path == "fake-ffmpeg", "encoder keeps the configured executable")

	var captured_executable: Array[String] = []
	var captured_args: Array[PackedStringArray] = []
	encoder.process_runner = func(
		executable: String, args: PackedStringArray, output: Array
	) -> int:
		captured_executable.append(executable)
		captured_args.append(args.duplicate())
		output.append("frame= 42")
		return 0

	var result := encoder.encode(settings)
	check(bool(result.get("ok", false)), "successful process reports ok")
	check(int(result.get("exit_code", -1)) == 0, "successful process reports exit code 0")
	check(captured_executable.size() == 1, "runner invoked once")
	check(
		captured_executable[0] == settings.ffmpeg_path,
		"runner sees the profile executable"
	)
	check(
		captured_args[0] == settings.build_ffmpeg_args(),
		"runner receives the built argument list"
	)
	check(
		result.get("command", PackedStringArray()) == settings.build_ffmpeg_args(),
		"result carries the exact command"
	)
	check(String(result.get("output", "")) == "frame= 42", "result carries process output")

	captured_executable.clear()
	captured_args.clear()
	settings.ffmpeg_path = "other-ffmpeg"
	var override_result := encoder.encode(settings)
	check(captured_executable.size() == 1, "override executable invoked")
	check(captured_executable[0] == "other-ffmpeg", "profile executable overrides encoder default")
	check(bool(override_result.get("ok", false)), "override executable succeeds")

	encoder.process_runner = func(
		_executable: String, _args: PackedStringArray, output: Array
	) -> int:
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

	var null_result := encoder.encode(null)
	check(not bool(null_result.get("ok", true)), "null settings fail cleanly")
	check(int(null_result.get("exit_code", 0)) == -1, "null settings report exit code -1")

	finish()
