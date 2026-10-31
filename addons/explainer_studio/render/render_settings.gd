@tool
class_name RenderSettings
extends Resource
## Settings for one deterministic render pass (M4).
##
## Rendering is frame driven: the [FrameRenderer] captures one image per frame
## and [FfmpegEncoder] turns those PNGs into an MP4. Run the game with
## `--fixed-fps <fps>` (matching [member fps]) so Tweens advance by exactly
## `1.0 / fps` per processed frame; that is what makes the result repeatable.
##
## Everything serializes to `.tres`, so a render profile can be checked in next
## to a sequence and reused by the dock (M5) or CI.

## Prefix and extension used for captured frames. The encoder and cleanup code
## both derive the ffmpeg pattern from these.
const FRAME_PREFIX := "frame_"
const FRAME_DIGITS := 6
const FRAME_EXTENSION := ".png"

## Output movie. `user://` and `res://` paths are globalized before ffmpeg runs.
@export var output_path: String = "user://explainer_render/take.mp4"

## Directory for captured PNGs. Empty derives `<output_basename>_frames` next to
## the output file, which keeps sequential renders from sharing stale frames.
@export var frames_dir: String = ""

## Frame rate of the render. Must match the engine's `--fixed-fps` value.
@export_range(1, 240, 1, "suffix:fps")
var fps: int = 60

## Optional output size in pixels. `(0, 0)` keeps the project viewport size.
@export var resolution: Vector2i = Vector2i.ZERO

## ffmpeg executable. Resolved through `PATH` when not absolute.
@export var ffmpeg_path: String = "ffmpeg"

## H.264/H.265 quality. Lower is better quality and a larger file.
@export_range(0, 51, 1)
var crf: int = 18

## x264/x265 speed preset.
@export_enum("ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow")
var preset: String = "medium"

## Video codec passed to ffmpeg.
@export var video_codec: String = "libx264"

## Pixel format passed to ffmpeg. `yuv420p` is the compatible default.
@export var pixel_format: String = "yuv420p"

## Optional audio file to mux into the movie. Leave empty for a silent render.
## Narration is authored in real time, so M4 accepts a pre-mixed track here;
## deterministic audio mixing lands with the polish pass.
@export var audio_path: String = ""

## Audio codec used when [member audio_path] is set.
@export var audio_codec: String = "aac"

## Audio bitrate used when [member audio_path] is set.
@export var audio_bitrate: String = "192k"

## Keep PNG frames after a successful encode. Frames are always kept on failure.
@export var keep_frames: bool = false

## Replace an existing output file. When false and the file exists, the render
## is refused before any frame is captured.
@export var overwrite: bool = true

## Extra ffmpeg arguments appended after the defaults and before the output
## path, so callers can override codec/muxer choices.
@export var extra_args: PackedStringArray = PackedStringArray()


## Number of frames needed to cover [param duration] at [member fps]. Rounds up
## with a tiny epsilon so e.g. `10.8s * 60` yields exactly 648, not 649.
func get_frame_count(duration: float) -> int:
	if duration <= 0.0 or fps <= 0:
		return 0
	return maxi(1, ceili(duration * float(fps) - 0.000001))


## Presentation time of [param index] in seconds.
func get_frame_time(index: int) -> float:
	if fps <= 0:
		return 0.0
	return float(index) / float(fps)


## Directory for captured frames, deriving one from [member output_path] when
## [member frames_dir] is empty.
func get_frames_dir() -> String:
	if not frames_dir.is_empty():
		return frames_dir
	var output := output_path
	if output.is_empty():
		output = "take.mp4"
	return output.get_basename() + "_frames"


## Absolute directory for captured frames, suitable for `DirAccess` and ffmpeg.
func get_resolved_frames_dir() -> String:
	return _resolve_path(get_frames_dir())


## Zero-padded file name for [param index].
func get_frame_filename(index: int) -> String:
	var digits := str(maxi(index, 0))
	while digits.length() < FRAME_DIGITS:
		digits = "0" + digits
	return FRAME_PREFIX + digits + FRAME_EXTENSION


## Project-relative path for captured frame [param index].
func get_frame_path(index: int) -> String:
	return get_frames_dir().path_join(get_frame_filename(index))


## ffmpeg input pattern for the captured frames.
func get_frame_pattern() -> String:
	return get_frames_dir().path_join(
		FRAME_PREFIX + "%0" + str(FRAME_DIGITS) + "d" + FRAME_EXTENSION
	)


## Absolute ffmpeg input pattern.
func get_resolved_frame_pattern() -> String:
	return _resolve_path(get_frame_pattern())


## Raw output path, as authored.
func get_output_path() -> String:
	return output_path


## Absolute output path, suitable for ffmpeg and existence checks.
func get_resolved_output_path() -> String:
	return _resolve_path(output_path)


## Absolute audio path, or an empty string when no audio is configured.
func get_resolved_audio_path() -> String:
	return _resolve_path(audio_path)


## Whether an audio track will be muxed into the movie.
func has_audio() -> bool:
	return not audio_path.is_empty()


## Builds the complete ffmpeg argument list for this profile.
func build_ffmpeg_args() -> PackedStringArray:
	var args := PackedStringArray()
	args.append("-hide_banner")
	args.append("-loglevel")
	args.append("error")
	args.append("-y" if overwrite else "-n")
	args.append("-framerate")
	args.append(str(maxi(fps, 1)))
	args.append("-start_number")
	args.append("0")
	args.append("-i")
	args.append(get_resolved_frame_pattern())
	if has_audio():
		args.append("-i")
		args.append(get_resolved_audio_path())

	args.append("-c:v")
	args.append(video_codec)
	if video_codec in ["libx264", "libx265"]:
		args.append("-preset")
		args.append(preset)
		args.append("-crf")
		args.append(str(clampi(crf, 0, 51)))
	args.append("-pix_fmt")
	args.append(pixel_format)
	if has_audio():
		args.append("-c:a")
		args.append(audio_codec)
		args.append("-b:a")
		args.append(audio_bitrate)
		# Pad short narration to the video length so -shortest never truncates
		# the picture; a longer track is still cut off at the last frame.
		args.append("-af")
		args.append("apad")
		args.append("-shortest")
	var extension := get_output_path().get_extension().to_lower()
	if extension in ["mp4", "mov", "m4v"]:
		args.append("-movflags")
		args.append("+faststart")
	for extra in extra_args:
		args.append(extra)
	args.append(get_resolved_output_path())
	return args


## Human-readable command line for logs and error messages.
func get_ffmpeg_command() -> String:
	return " ".join(build_ffmpeg_args())


## Authoring checks. [param duration] is optional; when positive it also checks
## that at least one frame would be produced. Empty means the profile is clean.
func validate(duration: float = -1.0) -> PackedStringArray:
	var issues := PackedStringArray()
	if fps < 1:
		issues.append("Render fps must be at least 1.")
	if output_path.strip_edges().is_empty():
		issues.append("Output path is empty.")
	if get_frames_dir().strip_edges().is_empty():
		issues.append("Frames directory is empty.")
	if ffmpeg_path.strip_edges().is_empty():
		issues.append("ffmpeg path is empty.")
	if video_codec.strip_edges().is_empty():
		issues.append("Video codec is empty.")
	if pixel_format.strip_edges().is_empty():
		issues.append("Pixel format is empty.")
	if crf < 0 or crf > 51:
		issues.append("CRF must be in [0, 51].")
	if resolution.x < 0 or resolution.y < 0:
		issues.append("Resolution cannot be negative.")
	if has_audio() and not FileAccess.file_exists(audio_path):
		issues.append("Audio file '%s' does not exist." % audio_path)
	if duration > 0.0 and get_frame_count(duration) <= 0:
		issues.append("Duration produces no frames.")
	return issues


func _resolve_path(path: String) -> String:
	if path.is_empty():
		return ""
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://").path_join(path)
