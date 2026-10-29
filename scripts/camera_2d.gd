@tool
extends "res://addons/explainer_studio/camera/explainer_camera.gd"
## Backwards-compatible alias for the legacy `scripts/camera_2d.gd` path.
##
## The canonical implementation lives in
## `addons/explainer_studio/camera/explainer_camera.gd`. Existing scenes that
## still point at `scripts/camera_2d.gd` keep working, but new code should use
## [ExplainerCamera] (or let a [Director] drive it) so aborts and cues stay on the
## same clock. No behaviour is duplicated here on purpose.
