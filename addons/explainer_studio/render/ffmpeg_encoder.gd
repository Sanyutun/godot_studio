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

## Executable used when a profile leaves [member RenderSettings.ffmpeg_path]
## empty. Both [method is_available] and [method encode] resolve the executable
## through the same helper so they cannot disagree.
var ffmpeg_path: String = DEFAULT_FFMPEG

## Optional replacement for [method OS.execute] with the signature
## `(executable: String, args: PackedStringArray, output: Array) -> int`.
## Tests inject a fake here; production leaves it invalid.
var process_runner: Callable


func _init(executable: String = DEFAULT_FFMPEG) -> void:
	ffmpeg_path = executable


## Whether ffmpeg can be launched (`ffmpeg -version` exits 0). When
## [param settings] is provided its executable wins; otherwise [member ffmpeg_path]
## is used.
func is_available(settings: RenderSettings = null) -> bool:
	var executable := _resolve_executable(settings)
	if executable.strip_edges().is_empty():
		return false
	var output: Array = []
	return _execute(executable, PackedStringArray(["-version"]), output) == 0


## Encodes the frame sequence described by [param settings] into its output
## path. Returns a result dictionary with `ok`, `exit_code`, `command` and
## `output` keys; `command` is the exact argument list passed to ffmpeg. `ok`
## also requires a non-empty output file, so a process that exits 0 without
## writing anything is treated as a failure.
func encode(settings: RenderSettings) -> Dictionary:
	if settings == null:
		return _result(false, -1, PackedStringArray(), "RenderSettings is null.")
	var args := settings.build_ffmpeg_args()
	var output: Array = []
	var executable := _resolve_executable(settings)
	var exit_code := _execute(executable, args, output)
	var text := "\n".join(output)
	var output_ready := _output_ready(settings.get_resolved_output_path())
	var ok := exit_code == 0 and output_ready
	if exit_code == 0 and not output_ready:
		var note := "ffmpeg reported success but did not create a non-empty output file."
		text = note if text.is_empty() else "%s\n%s" % [text, note]
	return _result(ok, exit_code, args, text)


func _resolve_executable(settings: RenderSettings) -> String:
	if settings != null and not settings.ffmpeg_path.strip_edges().is_empty():
		return settings.ffmpeg_path
	return ffmpeg_path


func _output_ready(path: String) -> bool:
	if path.is_empty() or not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var size := file.get_length()
	file.close()
	return size > 0


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
