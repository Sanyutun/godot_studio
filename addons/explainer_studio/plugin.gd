@tool
extends EditorPlugin
## Explainer Studio editor entry point.
##
## M4 still only registers the plugin: the Studio dock, shot inspector and
## preview scrubber arrive in M5. Keeping this file tiny means headless builds
## and runtime exports never pay for editor-only code.

const PLUGIN_NAME := "Explainer Studio"
const PLUGIN_VERSION := "0.4.0"


func _enter_tree() -> void:
	print("[%s] v%s ready" % [PLUGIN_NAME, PLUGIN_VERSION])


func _exit_tree() -> void:
	pass
