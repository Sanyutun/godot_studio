@tool
extends EditorPlugin
## Explainer Studio editor entry point.
##
## Registers the Studio dock (M5): sequence loader, shot/cue inspector, marker
## editor and the preview scrubber. The dock owns no authoring logic of its own;
## it drives [SequenceEditorModel] and [PreviewTimeline], which are also covered
## by headless tests.

const PLUGIN_NAME := "Explainer Studio"
const PLUGIN_VERSION := "0.5.0"
const StudioDock := preload("res://addons/explainer_studio/editor/studio_dock.gd")

var _dock: Control = null


func _enter_tree() -> void:
	_dock = StudioDock.new()
	_dock.name = "Explainer Studio"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	print("[%s] v%s ready · Studio dock loaded" % [PLUGIN_NAME, PLUGIN_VERSION])


func _exit_tree() -> void:
	if _dock == null:
		return
	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
