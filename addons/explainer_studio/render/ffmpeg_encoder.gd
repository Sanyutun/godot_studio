class_name FfmpegEncoder
extends RefCounted
## Runs ffmpeg for a [RenderSettings] profile (M4).
##
## The encoder is deliberately synchronous: encoding happens after the last
## frame is captured, and the engine is free to block while ffmpeg drains the
## PNG sequence. [member process_runner] is a test seam so headless tests can
## assert the command and return codes without requiring ffmpeg on `PATH`.

## Executable used when a profile does not override it.
const DEFAULT_FFMPEG := "ffmpeg"

## ffmpeg executable. [method encode] still uses [member RenderSettings.ffmpeg_path]
## when a profile provides one.
var ffmpeg_path: String = DEFAULT_FFMPEG

## Optional replacement for [method OS.execute] with the signature
## `(executable: String, args: PackedStringArray, output: Array) -> int`.
## Tests inject a fake here; production leaves it invalid.
var process_runner: Callable


func _init(executable: String = DEFAULT_FFMPEG) -> void:
	ffmpeg_path = executable


## Whether ffmpeg can be launched (`ffmpeg -version` exits 0).
func is_available() -> bool:
	var output: Array = []
	return _execute(ffmpeg_path, PackedStringArray(["-version"]), output) == 0


## Encodes the frame sequence described by [param settings] into its output
## path. Returns a result dictionary with `ok`, `exit_code`, `command` and
## `output` keys; `command` is the exact argument list passed to ffmpeg.
func encode(settings: RenderSettings) -> Dictionary:
	if settings == null:
		return _result(false, -1, PackedStringArray(), "RenderSettings is null.")
	var args := settings.build_ffmpeg_args()
	var output: Array = []
	var executable := settings.ffmpeg_path
	if executable.strip_edges().is_empty():
		executable = ffmpeg_path
	var exit_code := _execute(executable, args, output)
	return _result(exit_code == 0, exit_code, args, "\n".join(output))


func _execute(executable: String, args: PackedStringArray, output: Array) -> int:
	if process_runner.is_valid():
		return int(process_runner.call(executable, args, output))
	return OS.execute(executable, args, output, true)


func _result(
	ok: bool, exit_code: int, command: PackedStringArray, output: String
) -> Dictionary:
	return {
		"ok": ok,
		"exit_code": exit_code,
		"command": command,
		"output": output,
	}
