# Explainer Studio

Godot **4.3+** editor add-on + runtime toolkit that turns scripted shot lists into
polished 2D explainer videos: camera moves, UI reveals, captions, VO sync, and
frame-accurate MP4 export.

GDScript only. No C#, no shaders, no GDExtensions.

> **Status: M4 complete.** Core runtime (Shot / Cue / Sequence / Director /
> ExplainerCamera), UI sequencing (CaptionRevealer / Callout / LowerThird), VO
> sync (VoiceOver / VoiceTrack, marker snapping), deterministic frame rendering
> (RenderSettings / FrameRenderer / FfmpegEncoder), demo scene and headless
> tests. The editor dock (M5) and polish (M6) are next.

## Requirements

- Godot 4.3 or newer (verified on 4.7.2 stable)
- ffmpeg on `PATH` (only needed from M4)
- On Windows, use the `_console.exe` build for CLI/test output.

## Quickstart

```powershell
# Windowed demo (10.8 s, five shots, loops)
godot scenes/demo/m1_shots.tscn

# Headless demo: fixed 60 fps, 800 frames (~13.3 s), grep for errors
godot --headless --fixed-fps 60 --quit-after 800 scenes/demo/m1_shots.tscn

# Deterministic MP4 (needs ffmpeg on PATH; use xvfb-run on headless Linux)
godot --fixed-fps 60 scenes/demo/m1_shots.tscn -- --render --out user://m1_demo.mp4

# Headless tests
godot --headless -s tests/test_director_sequence.gd
godot --headless -s tests/test_cue_clamping.gd
godot --headless -s tests/test_camera_kill_reset.gd
godot --headless -s tests/test_caption_revealer.gd
godot --headless -s tests/test_callout.gd
godot --headless -s tests/test_lower_third.gd
godot --headless -s tests/test_voice_over.gd
godot --headless -s tests/test_marker_snapping.gd
godot --headless -s tests/test_render_settings.gd
godot --headless -s tests/test_ffmpeg_encoder.gd
godot --headless -s tests/test_frame_renderer.gd

# Parse check (exit code 0 = clean)
godot --headless --check-only --script addons/explainer_studio/core/shot.gd
```

## Runtime in 20 lines

```gdscript
var sequence := Sequence.new()
sequence.display_name = "intro"

var punch := Shot.new()
punch.kind = Shot.Kind.PUNCH_IN
punch.target = NodePath("../Hero")   # resolved relative to the camera
punch.zoom = 2.2
punch.duration = 1.8
punch.ease = Tween.EASE_OUT
punch.trans = Tween.TRANS_CUBIC

var cue := Cue.new()
cue.time = 1.6                       # clamped to [0, duration] by the Director
cue.action = Cue.ACTION_CAPTION
cue.data = {"text": "Deterministic by design"}
punch.cues = [cue]

sequence.add_shot(punch)

director.camera = camera
await director.play(sequence)        # waits for the whole take
```

## UI sequencing (M2)

UI receivers implement `on_cue(event: CueEvent)` and are targeted with `cue.target`.
The Director hands each receiver the shot's remaining time, so reveals settle when
the camera move does instead of running past the cut:

| Receiver           | `action`      | `data` keys                                              |
|--------------------|---------------|----------------------------------------------------------|
| `CaptionRevealer`  | `caption`     | `text`, `mode`, `duration`, `hide`                       |
| `Callout`          | `callout`     | `text`, `anchor`, `hold`, `reveal`, `duration`, `hide`   |
| `LowerThird`       | `lower_third` | `title`, `subtitle`, `kicker`, `hold`, `reveal`, `duration`, `hide` |

Omit `hold` to keep a card up until the shot ends; set `hold: 0` to leave it up
until a later `hide` cue or a new cue on the same receiver.

## Voice-over sync (M3)

`VoiceOver` is an `AudioStreamPlayer` receiver. Cues use `action: voice_over` and
target the player; `data` may carry a serialized `VoiceTrack` plus per-cue
overrides:

| Receiver     | `action`     | `data` keys                                                        |
|--------------|--------------|--------------------------------------------------------------------|
| `VoiceOver`  | `voice_over` | `stream`, `track`, `stream_path`/`path`, `volume_db`, `bus`, `fade_in`, `from`, `hide`/`stop`, `duration` |

`VoiceTrack` (`.tres`-serializable) holds `stream`, `volume_db`, `bus`, `fade_in`,
`fade_out` and `start_offset`. Precedence is per-cue `data` → track → player
defaults. Narration deliberately outlives the shot that starts it, so a line can
bridge a cut; send a `hide`/`stop` cue (with optional `duration`) to fade it out.

Cues can snap to named sequence beats instead of using raw `time`:

```gdscript
sequence.add_marker("vo_hook", 1.8)        # absolute seconds in the sequence

var cue := Cue.new()
cue.action = Cue.ACTION_VOICE_OVER
cue.marker = &"vo_hook"                    # Director resolves + clamps to the shot
cue.target = NodePath("../VoiceOver")
cue.data = {"track": my_voice_track}
```

`Sequence` also exposes `get_marker_names()`, `get_nearest_marker()`,
`get_nearest_marker_time()`, `snap_to_marker()` and `remove_marker()` for the
preview scrubber and the M5 dock. Unknown markers warn and fall back to `time`.

## Deterministic rendering (M4)

`RenderSettings` is the serializable render profile. `FrameRenderer` starts the
sequence, captures one viewport image per frame, and `FfmpegEncoder` muxes the
PNG sequence into an MP4:

```gdscript
var settings := RenderSettings.new()
settings.output_path = "user://renders/intro.mp4"
settings.fps = 60
settings.resolution = Vector2i(1920, 1080)   # (0, 0) keeps the viewport size
settings.crf = 18
settings.audio_path = "user://renders/narration.wav"  # optional pre-mixed track

var renderer := FrameRenderer.new()
add_child(renderer)
renderer.director = director
var ok := await renderer.render(sequence, settings)
```

Capture is only deterministic when the engine advances by a fixed timestep, so
run with `--fixed-fps` matching `settings.fps`:

```powershell
godot --fixed-fps 60 scenes/demo/m1_shots.tscn -- --render --out user://m1_demo.mp4
# Optional: --size 1920x1080 --fps 60 --keep-frames --audio narration.wav
```

`--render` replaces the normal demo loop, exits 0 on success, and prints the
resolved output path. On headless Linux wrap the command in `xvfb-run`; the
dummy `--headless` renderer cannot read viewport textures.

Frames live in `frames_dir` (derived as `<output>_frames` when empty), are
cleared before a render, kept when ffmpeg fails, and removed after a successful
encode unless `keep_frames` is set. `get_frame_count()`, `get_frame_time()`,
frame naming, validation and ffmpeg argument building are plain functions, which
keeps the headless tests fast and ffmpeg-free.

Audio: M4 muxes an already-mixed file through `audio_path` and pads short tracks
with silence so the picture keeps its full length (`-af apad -shortest`). The
[VoiceOver] player is real-time; offline VO capture/mixing is polished in M6.

## Layout

```
addons/explainer_studio/
├── plugin.cfg / plugin.gd        EditorPlugin entry point (dock lands in M5)
├── core/
│   ├── shot.gd                   Shot resource (.tres-serializable)
│   ├── cue.gd                    Cue resource: time/action/target + payload
│   ├── sequence.gd               Ordered shots, markers, validation
│   └── director.gd               Plays a Sequence, fires cues, clamps times
├── camera/
│   └── explainer_camera.gd       ExplainerCamera (Camera2D)
├── ui/
│   ├── caption_revealer.gd       Typewriter / fade / slide captions
│   ├── callout.gd                World-anchored annotation bubble
│   └── lower_third.gd            Sliding title card
├── audio/
│   ├── voice_over.gd             Cue-driven narration player
│   └── voice_track.gd            Serialized clip + mix settings
├── render/
│   ├── render_settings.gd        Render profile, frame math, ffmpeg args
│   ├── frame_renderer.gd         Fixed-step capture loop and cleanup
│   └── ffmpeg_encoder.gd         Process runner + result metadata
├── editor/                       M5 home
scenes/demo/m1_shots.tscn         Five-shot demo over placeholder art
scenes/demo/m1_demo.gd            Builds the demo sequence, prints cues
scripts/camera_2d.gd              Deprecated alias → ExplainerCamera
scripts/shot_director_example.gd  Copy-paste API example
tests/                            Plain SceneTree tests (no GUT dependency)
```

## Shot semantics

`zoom` is always an **absolute** target (`1.0` = unzoomed viewport).

| Kind        | Position           | Zoom                  |
|-------------|--------------------|-----------------------|
| `MOVE`      | target / keep      | target `zoom`         |
| `PAN`       | target / keep      | untouched             |
| `PUNCH_IN`  | target (optional)  | target `zoom`         |
| `PUNCH_OUT` | target (optional)  | target `zoom`         |
| `FIT_RECT`  | rect center        | derived from `rect`   |
| `DRIFT`     | target / keep      | target `zoom`         |
| `HOLD`      | untouched          | untouched             |

Every camera move returns its `Tween` from `ExplainerCamera.play_shot()` and can be
awaited through `await_shot()` / `Director.play()`.

## Kill-safe camera state

A killed tween never emits `finished`, which used to leave `_shot_active` stuck and
made a following punch-out drift. `ExplainerCamera` now:

1. resets state and kills the previous tween before starting a new shot,
2. reaps externally killed tweens with a signal-based watchdog
   (`KILL_WATCHDOG_GRACE`),
3. self-heals on `is_shot_active()` and emits `shot_aborted` / `shot_settled` once.

`tests/test_camera_kill_reset.gd` covers all three paths, plus a Director that
must keep playing after its camera tween is killed.

## Design rules

- Smoothing uses `1 - exp(-speed * delta)`; timing uses Tweens/timers.
- Renders assume `--fixed-fps`; capture never uses wall-clock waits.
- No `process()` polling, no autoload singletons.
- Typed GDScript, `@export_range` with units in doc comments.
- UI/render/editor talk to `Director` and `Cue` only — never to the camera.

## License

MIT-style: keep the copyright notice, no warranty.
