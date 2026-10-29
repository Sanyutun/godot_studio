# Explainer Studio

Godot **4.3+** editor add-on + runtime toolkit that turns scripted shot lists into
polished 2D explainer videos: camera moves, UI reveals, captions, VO sync, and
frame-accurate MP4 export.

GDScript only. No C#, no shaders, no GDExtensions.

> **Status: M1 complete.** Core runtime (Shot / Cue / Sequence / Director /
> ExplainerCamera), demo scene and headless tests. UI sequencing (M2), VO (M3),
> deterministic rendering (M4), editor dock (M5) and polish (M6) are next.

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

# Headless tests
godot --headless -s tests/test_director_sequence.gd
godot --headless -s tests/test_cue_clamping.gd
godot --headless -s tests/test_camera_kill_reset.gd

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
├── ui/ audio/ render/ editor/    M2–M5 homes
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
- No `process()` polling, no autoload singletons.
- Typed GDScript, `@export_range` with units in doc comments.
- UI/render/editor talk to `Director` and `Cue` only — never to the camera.

## License

MIT-style: keep the copyright notice, no warranty.
