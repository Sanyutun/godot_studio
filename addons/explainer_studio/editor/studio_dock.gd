@tool
extends MarginContainer
## Explainer Studio editor dock: sequence loader, shot/cue inspector and preview
## scrubber.
##
## The dock is deliberately thin. [SequenceEditorModel] owns authoring logic and
## [PreviewTimeline] owns timeline maths, so this file mostly builds controls,
## mirrors model state into them and wraps edits in [EditorUndoRedoManager]
## actions. Nothing here animates a camera directly.

const PreviewScrubber := preload("res://addons/explainer_studio/editor/preview_scrubber.gd")
const VERSION := "0.5.0"

const KIND_NAMES: Array[String] = [
	"move", "punch_in", "punch_out", "pan", "fit_rect", "drift", "hold",
]
const EASE_NAMES: Array[String] = ["in", "out", "in_out", "out_in"]
const TRANS_NAMES: Array[String] = [
	"linear", "sine", "quint", "quart", "quad", "expo", "elastic", "cubic",
	"circ", "bounce", "back", "spring",
]
const ACTION_NAMES: Array[String] = ["caption", "callout", "lower_third", "voice_over"]

var _model := SequenceEditorModel.new()
var _timeline := PreviewTimeline.new()
var _sequence_path := ""
var _dirty := false
var _loading := false
var _refreshing := false
var _playing := false
var _loop := false
var _playback_shot := -1

var _column: VBoxContainer
var _status_label: Label
var _dirty_label: Label
var _sequence_picker: EditorResourcePicker
var _name_edit: LineEdit
var _shot_list: ItemList
var _shot_panel: PanelContainer
var _shot_kind: OptionButton
var _shot_duration: SpinBox
var _shot_zoom: SpinBox
var _shot_target: LineEdit
var _shot_rect_x: SpinBox
var _shot_rect_y: SpinBox
var _shot_rect_w: SpinBox
var _shot_rect_h: SpinBox
var _shot_ease: OptionButton
var _shot_trans: OptionButton
var _cue_list: ItemList
var _cue_panel: PanelContainer
var _cue_action: OptionButton
var _cue_time: SpinBox
var _cue_marker: OptionButton
var _cue_target: LineEdit
var _cue_data: TextEdit
var _cue_data_error: Label
var _cue_time_label: Label
var _marker_list: ItemList
var _marker_name: LineEdit
var _marker_time: SpinBox
var _validation_label: Label
var _play_button: Button
var _time_label: Label
var _shot_time_label: Label
var _loop_check: CheckBox
var _scrubber: Control
var _load_dialog: EditorFileDialog
var _save_dialog: EditorFileDialog


func _ready() -> void:
	add_theme_constant_override("margin_left", 8)
	add_theme_constant_override("margin_right", 8)
	add_theme_constant_override("margin_top", 6)
	add_theme_constant_override("margin_bottom", 6)
	custom_minimum_size = Vector2(280.0, 0.0)
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 6)
	add_child(_column)

	_build_header()
	_build_scroll_body()
	_build_preview()
	_build_dialogs()

	_model.changed.connect(_on_model_changed)
	_model.selection_changed.connect(_on_selection_changed)
	_load_sequence(_new_sequence(), "", false)
	set_process(true)


func _process(delta: float) -> void:
	if not _playing:
		return
	var duration := _timeline.get_duration()
	if duration <= 0.0:
		_stop_playback(false)
		return
	var next_time := float(_scrubber.get_time()) + delta
	if next_time >= duration:
		if _loop:
			next_time = fmod(next_time, duration)
		else:
			_set_preview_time(duration)
			_stop_playback(false)
			return
	_set_preview_time(next_time)
	var state := _timeline.get_shot_local_time(next_time)
	var shot_index := int(state.get("index", -1))
	if shot_index >= 0 and shot_index != _playback_shot:
		_playback_shot = shot_index
		_model.select_shot(shot_index)


func _build_header() -> void:
	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "Explainer Studio"
	title.add_theme_font_size_override("font_size", 16)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_dirty_label = Label.new()
	_dirty_label.add_theme_font_size_override("font_size", 11)
	_dirty_label.text = "v%s" % VERSION
	title_row.add_child(_dirty_label)
	_column.add_child(title_row)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.text = "Select or create a Sequence resource."
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(_status_label)

	_section_label("Sequence")
	var picker_row := HBoxContainer.new()
	_sequence_picker = EditorResourcePicker.new()
	_sequence_picker.base_type = "Sequence"
	_sequence_picker.editable = true
	_sequence_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sequence_picker.resource_changed.connect(_on_sequence_picked)
	picker_row.add_child(_sequence_picker)

	var new_button := _button("New", "Create a new in-memory sequence.")
	new_button.pressed.connect(_on_new_pressed)
	picker_row.add_child(new_button)
	var save_button := _button("Save", "Save the current sequence resource.")
	save_button.pressed.connect(_on_save_pressed)
	picker_row.add_child(save_button)
	_column.add_child(picker_row)

	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "Name"
	name_label.custom_minimum_size.x = 48.0
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Sequence display name"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(_commit_sequence_name)
	_name_edit.focus_exited.connect(_commit_sequence_name)
	name_row.add_child(_name_edit)
	var save_as := _button("Save As…", "Save the sequence to a new .tres file.")
	save_as.pressed.connect(_on_save_as_pressed)
	name_row.add_child(save_as)
	_column.add_child(name_row)


func _build_scroll_body() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)

	# Shots ---------------------------------------------------------------
	_section_label("Shots", body)
	_shot_list = ItemList.new()
	_shot_list.custom_minimum_size.y = 118.0
	_shot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shot_list.item_selected.connect(_on_shot_selected)
	body.add_child(_shot_list)
	var shot_buttons := HBoxContainer.new()
	shot_buttons.add_child(_button("Add", "Add a hold shot.", _add_shot))
	shot_buttons.add_child(_button("Dup", "Duplicate the selected shot.", _duplicate_shot))
	shot_buttons.add_child(_button("↑", "Move the shot earlier.", _move_shot_up))
	shot_buttons.add_child(_button("↓", "Move the shot later.", _move_shot_down))
	shot_buttons.add_child(_button("−", "Remove the selected shot.", _remove_shot))
	body.add_child(shot_buttons)

	_shot_panel = _panel(body)
	var shot_box := _panel_box(_shot_panel, "Shot inspector")
	var shot_grid := _grid(shot_box)
	_shot_kind = _option(shot_grid, "Kind", KIND_NAMES)
	_shot_kind.item_selected.connect(_on_shot_kind_selected)
	_shot_duration = _spin(shot_grid, "Duration", 0.0, 600.0, 0.01, " s")
	_shot_duration.value_changed.connect(_on_shot_duration_changed)
	_shot_zoom = _spin(shot_grid, "Zoom", 0.05, 20.0, 0.05)
	_shot_zoom.value_changed.connect(_on_shot_zoom_changed)
	_shot_target = _line(shot_grid, "Target", "../World/Card")
	_shot_target.text_submitted.connect(_commit_shot_target)
	_shot_target.focus_exited.connect(_commit_shot_target)
	_shot_ease = _option(shot_grid, "Ease", EASE_NAMES)
	_shot_ease.item_selected.connect(_on_shot_ease_selected)
	_shot_trans = _option(shot_grid, "Trans", TRANS_NAMES)
	_shot_trans.item_selected.connect(_on_shot_trans_selected)

	var rect_label := Label.new()
	rect_label.text = "Rect"
	shot_grid.add_child(rect_label)
	var rect_row := HBoxContainer.new()
	_shot_rect_x = _compact_spin(rect_row, -100000.0, 100000.0, 1.0)
	_shot_rect_y = _compact_spin(rect_row, -100000.0, 100000.0, 1.0)
	_shot_rect_w = _compact_spin(rect_row, 0.0, 100000.0, 1.0)
	_shot_rect_h = _compact_spin(rect_row, 0.0, 100000.0, 1.0)
	shot_grid.add_child(rect_row)
	for spin: SpinBox in [_shot_rect_x, _shot_rect_y, _shot_rect_w, _shot_rect_h]:
		spin.value_changed.connect(_on_shot_rect_changed)

	# Cues ----------------------------------------------------------------
	_section_label("Cues", body)
	_cue_list = ItemList.new()
	_cue_list.custom_minimum_size.y = 96.0
	_cue_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_list.item_selected.connect(_on_cue_selected)
	body.add_child(_cue_list)
	var cue_buttons := HBoxContainer.new()
	cue_buttons.add_child(_button("Add", "Add a caption cue.", _on_add_cue))
	cue_buttons.add_child(_button("Dup", "Duplicate the selected cue.", _duplicate_cue))
	cue_buttons.add_child(_button("−", "Remove the selected cue.", _remove_cue))
	body.add_child(cue_buttons)

	_cue_panel = _panel(body)
	var cue_box := _panel_box(_cue_panel, "Cue inspector")
	var cue_grid := _grid(cue_box)
	_cue_action = _option(cue_grid, "Action", ACTION_NAMES)
	_cue_action.item_selected.connect(_on_cue_action_selected)
	_cue_time = _spin(cue_grid, "Time", 0.0, 600.0, 0.01, " s")
	_cue_time.value_changed.connect(_on_cue_time_changed)
	_cue_marker = _option(cue_grid, "Marker", ["(none)"])
	_cue_marker.item_selected.connect(_on_cue_marker_selected)
	_cue_target = _line(cue_grid, "Target", "../HUD/Caption")
	_cue_target.text_submitted.connect(_commit_cue_target)
	_cue_target.focus_exited.connect(_commit_cue_target)
	_cue_time_label = Label.new()
	_cue_time_label.add_theme_font_size_override("font_size", 11)
	cue_box.add_child(_cue_time_label)

	var data_label := Label.new()
	data_label.text = "Data (JSON)"
	data_label.add_theme_font_size_override("font_size", 11)
	cue_box.add_child(data_label)
	_cue_data = TextEdit.new()
	_cue_data.custom_minimum_size.y = 76.0
	_cue_data.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_cue_data.add_theme_font_size_override("font_size", 11)
	cue_box.add_child(_cue_data)
	var data_row := HBoxContainer.new()
	_cue_data_error = Label.new()
	_cue_data_error.add_theme_font_size_override("font_size", 11)
	_cue_data_error.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cue_data_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	data_row.add_child(_cue_data_error)
	data_row.add_child(_button("Apply data", "Parse the JSON payload.", _on_apply_cue_data))
	cue_box.add_child(data_row)

	# Markers -------------------------------------------------------------
	_section_label("Markers", body)
	_marker_list = ItemList.new()
	_marker_list.custom_minimum_size.y = 72.0
	_marker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_marker_list.item_selected.connect(_on_marker_selected)
	body.add_child(_marker_list)
	var marker_row := HBoxContainer.new()
	_marker_name = LineEdit.new()
	_marker_name.placeholder_text = "marker name"
	_marker_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	marker_row.add_child(_marker_name)
	_marker_time = _compact_spin(marker_row, 0.0, 600.0, 0.01)
	_marker_time.tooltip_text = "Marker time in seconds."
	marker_row.add_child(_marker_time)
	body.add_child(marker_row)
	var marker_buttons := HBoxContainer.new()
	marker_buttons.add_child(_button("Set", "Add or retime the named marker.", _on_set_marker))
	marker_buttons.add_child(
		_button("At playhead", "Use the scrubber time.", _on_marker_from_playhead)
	)
	marker_buttons.add_child(_button("−", "Remove the selected marker.", _on_remove_marker))
	body.add_child(marker_buttons)

	_validation_label = Label.new()
	_validation_label.add_theme_font_size_override("font_size", 11)
	_validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_validation_label)


func _build_preview() -> void:
	_column.add_child(HSeparator.new())
	var toolbar := HBoxContainer.new()
	_play_button = _button("Play", "Play or pause the timeline preview.", _on_toggle_play)
	_play_button.custom_minimum_size.x = 52.0
	toolbar.add_child(_play_button)
	toolbar.add_child(_button("Stop", "Stop and rewind the preview.", _on_stop_pressed))
	_time_label = Label.new()
	_time_label.text = "0.00 / 0.00 s"
	_time_label.add_theme_font_size_override("font_size", 11)
	_time_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_time_label)
	_loop_check = CheckBox.new()
	_loop_check.text = "Loop"
	_loop_check.add_theme_font_size_override("font_size", 11)
	_loop_check.toggled.connect(func(enabled: bool) -> void: _loop = enabled)
	toolbar.add_child(_loop_check)
	_column.add_child(toolbar)

	_shot_time_label = Label.new()
	_shot_time_label.add_theme_font_size_override("font_size", 11)
	_shot_time_label.text = "No sequence"
	_column.add_child(_shot_time_label)

	_scrubber = PreviewScrubber.new()
	_scrubber.seek_requested.connect(_on_scrubber_seek)
	_scrubber.shot_clicked.connect(_on_scrubber_shot_clicked)
	_scrubber.toggle_play_requested.connect(_on_toggle_play)
	_column.add_child(_scrubber)


func _build_dialogs() -> void:
	_load_dialog = EditorFileDialog.new()
	_load_dialog.title = "Load Explainer Sequence"
	_load_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_load_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_load_dialog.add_filter("*.tres,*.res", "Explainer Sequence")
	_load_dialog.file_selected.connect(_on_load_file_selected)
	add_child(_load_dialog)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.title = "Save Explainer Sequence"
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.add_filter("*.tres", "Explainer Sequence")
	_save_dialog.current_file = "sequence.tres"
	_save_dialog.file_selected.connect(_on_save_file_selected)
	add_child(_save_dialog)


func _new_sequence() -> Sequence:
	var sequence := Sequence.new()
	sequence.display_name = "Untitled Sequence"
	return sequence


func _load_sequence(sequence: Sequence, path: String, mark_loaded: bool = true) -> void:
	_loading = true
	_playing = false
	_playback_shot = -1
	_model.set_sequence(sequence)
	_loading = false
	_sequence_path = path
	_dirty = false
	_timeline.set_sequence(sequence)
	_scrubber.set_sequence(sequence)
	_scrubber.set_time(0.0)
	_scrubber.set_selection(_model.shot_index, _model.cue_index)
	_refresh_all()
	if mark_loaded:
		var label := path if not path.is_empty() else "new sequence"
		_set_status("Loaded %s." % label)


func _on_new_pressed() -> void:
	_load_sequence(_new_sequence(), "", false)
	_set_status("New in-memory sequence. Save it when ready.")


func _on_save_pressed() -> void:
	if _model.sequence == null:
		return
	if _sequence_path.is_empty():
		_on_save_as_pressed()
		return
	_save_to_path(_sequence_path)


func _on_save_as_pressed() -> void:
	if _model.sequence == null:
		return
	_save_dialog.current_path = _sequence_path if not _sequence_path.is_empty() else "res://"
	_save_dialog.popup_centered_ratio(0.45)


func _on_load_file_selected(path: String) -> void:
	var resource := ResourceLoader.load(path)
	if resource is Sequence:
		_load_sequence(resource as Sequence, path)
	else:
		_set_status("Not a Sequence resource: %s" % path)


func _on_save_file_selected(path: String) -> void:
	_save_to_path(path)


func _save_to_path(path: String) -> void:
	var final_path := path
	if final_path.get_extension().is_empty():
		final_path += ".tres"
	var error := ResourceSaver.save(_model.sequence, final_path)
	if error != OK:
		_set_status("Save failed (%s): %s" % [error_string(error), final_path])
		return
	_model.sequence.take_over_path(final_path)
	_sequence_path = final_path
	_dirty = false
	_refresh_sequence_header()
	_set_status("Saved %s." % final_path)
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null:
		filesystem.scan()


func _on_sequence_picked(resource: Resource) -> void:
	if _refreshing or _loading:
		return
	if resource is Sequence:
		var path := resource.resource_path
		_load_sequence(resource as Sequence, path)
	elif resource == null:
		_refresh_sequence_header()


func _commit_sequence_name(_text: String = "") -> void:
	if _refreshing or _model.sequence == null:
		return
	_push_property_edit(
		_model.sequence, "display_name", _name_edit.text, "Rename Sequence"
	)


func _on_shot_selected(index: int) -> void:
	if _refreshing:
		return
	_model.select_shot(index)


func _on_cue_selected(index: int) -> void:
	if _refreshing:
		return
	_model.select_cue(index)


func _on_marker_selected(index: int) -> void:
	if _refreshing or _marker_list.get_item_metadata(index) == null:
		return
	_marker_name.text = String(_marker_list.get_item_metadata(index))
	if _model.sequence != null:
		_marker_time.value = _model.sequence.get_marker_time(_marker_name.text)


func _add_shot() -> void:
	if _model.sequence == null:
		return
	var shot := Shot.new()
	shot.kind = Shot.Kind.HOLD
	shot.duration = 1.0
	var index := _model.shot_index + 1 if _model.shot_index >= 0 else _model.sequence.shots.size()
	_register_edit(
		"Add Shot",
		Callable(_model, "insert_shot").bind(index, shot),
		Callable(_model, "remove_shot").bind(index)
	)


func _duplicate_shot() -> void:
	var source := _model.get_selected_shot()
	if source == null:
		return
	var copy := source.duplicate(true) as Shot
	if copy == null:
		return
	var index := _model.shot_index + 1
	_register_edit(
		"Duplicate Shot",
		Callable(_model, "insert_shot").bind(index, copy),
		Callable(_model, "remove_shot").bind(index)
	)


func _remove_shot() -> void:
	var shot := _model.get_selected_shot()
	if shot == null:
		return
	var index := _model.shot_index
	_register_edit(
		"Remove Shot",
		Callable(_model, "remove_shot").bind(index),
		Callable(_model, "insert_shot").bind(index, shot)
	)


func _move_shot_up() -> void:
	_move_shot(-1)


func _move_shot_down() -> void:
	_move_shot(1)


func _move_shot(direction: int) -> void:
	var from_index := _model.shot_index
	var to_index := from_index + direction
	if _model.sequence == null or from_index < 0:
		return
	if to_index < 0 or to_index >= _model.sequence.shots.size():
		return
	_register_edit(
		"Reorder Shot",
		Callable(_model, "move_shot").bind(from_index, to_index),
		Callable(_model, "move_shot").bind(to_index, from_index)
	)


func _on_shot_kind_selected(index: int) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot != null:
		_push_property_edit(shot, "kind", index, "Set Shot Kind")


func _on_shot_duration_changed(value: float) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot != null:
		_push_property_edit(shot, "duration", value, "Set Shot Duration")


func _on_shot_zoom_changed(value: float) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot != null:
		_push_property_edit(shot, "zoom", value, "Set Shot Zoom")


func _on_shot_ease_selected(index: int) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot != null:
		_push_property_edit(shot, "ease", index, "Set Shot Ease")


func _on_shot_trans_selected(index: int) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot != null:
		_push_property_edit(shot, "trans", index, "Set Shot Transition")


func _commit_shot_target(_text: String = "") -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot == null:
		return
	_push_property_edit(shot, "target", NodePath(_shot_target.text), "Set Shot Target")


func _on_shot_rect_changed(_value: float) -> void:
	if _refreshing:
		return
	var shot := _model.get_selected_shot()
	if shot == null:
		return
	var rect := Rect2(
		_shot_rect_x.value,
		_shot_rect_y.value,
		_shot_rect_w.value,
		_shot_rect_h.value
	)
	_push_property_edit(shot, "rect", rect, "Set Shot Rect")


func _on_add_cue() -> void:
	if _model.sequence == null:
		return
	var shot := _model.get_selected_shot()
	if shot == null:
		return
	var cue := Cue.new()
	cue.action = Cue.ACTION_CAPTION
	cue.time = 0.0
	var index := _model.cue_index + 1 if _model.cue_index >= 0 else shot.cues.size()
	_register_edit(
		"Add Cue",
		Callable(_model, "insert_cue").bind(_model.shot_index, index, cue),
		Callable(_model, "remove_cue").bind(_model.shot_index, index)
	)


func _duplicate_cue() -> void:
	var source := _model.get_selected_cue()
	if source == null:
		return
	var copy := source.duplicate(true) as Cue
	if copy == null:
		return
	var shot_index := _model.shot_index
	var index := _model.cue_index + 1
	_register_edit(
		"Duplicate Cue",
		Callable(_model, "insert_cue").bind(shot_index, index, copy),
		Callable(_model, "remove_cue").bind(shot_index, index)
	)


func _remove_cue() -> void:
	var cue := _model.get_selected_cue()
	if cue == null:
		return
	var shot_index := _model.shot_index
	var index := _model.cue_index
	_register_edit(
		"Remove Cue",
		Callable(_model, "remove_cue").bind(shot_index, index),
		Callable(_model, "insert_cue").bind(shot_index, index, cue)
	)


func _on_cue_action_selected(index: int) -> void:
	if _refreshing:
		return
	var cue := _model.get_selected_cue()
	if cue != null:
		_ensure_option_item(_cue_action, StringName(_cue_action.get_item_text(index)))
		_push_property_edit(
			cue, "action", StringName(_cue_action.get_item_text(index)), "Set Cue Action"
		)


func _on_cue_time_changed(value: float) -> void:
	if _refreshing:
		return
	var cue := _model.get_selected_cue()
	if cue != null:
		_push_property_edit(cue, "time", value, "Set Cue Time")


func _on_cue_marker_selected(index: int) -> void:
	if _refreshing:
		return
	var cue := _model.get_selected_cue()
	if cue == null:
		return
	var marker := StringName(String(_cue_marker.get_item_metadata(index)))
	_push_property_edit(cue, "marker", marker, "Set Cue Marker")


func _commit_cue_target(_text: String = "") -> void:
	if _refreshing:
		return
	var cue := _model.get_selected_cue()
	if cue == null:
		return
	_push_property_edit(cue, "target", NodePath(_cue_target.text), "Set Cue Target")


func _on_apply_cue_data() -> void:
	if _refreshing:
		return
	var cue := _model.get_selected_cue()
	if cue == null:
		return
	var parsed: Variant = {}
	var text := _cue_data.text.strip_edges()
	if not text.is_empty():
		var parser := JSON.new()
		var error := parser.parse(text)
		if error != OK:
			_cue_data_error.text = "Line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
			_cue_data_error.add_theme_color_override("font_color", Color(0.95, 0.5, 0.45))
			return
		parsed = parser.data
	if not parsed is Dictionary:
		_cue_data_error.text = "Top-level JSON must be an object."
		_cue_data_error.add_theme_color_override("font_color", Color(0.95, 0.5, 0.45))
		return
	_cue_data_error.text = ""
	_push_property_edit(cue, "data", (parsed as Dictionary).duplicate(true), "Set Cue Data")
	_set_status("Cue payload updated.")


func _on_set_marker() -> void:
	if _model.sequence == null:
		return
	var marker_name := _marker_name.text.strip_edges()
	if marker_name.is_empty():
		_set_status("Marker needs a name.")
		return
	var marker_time := _marker_time.value
	var existed := _model.sequence.has_marker(marker_name)
	var previous := _model.sequence.get_marker_time(marker_name)
	if existed and is_equal_approx(previous, marker_time):
		return
	var do_edit := Callable(_model, "set_marker").bind(marker_name, marker_time)
	var undo_edit := (
		Callable(_model, "set_marker").bind(marker_name, previous)
		if existed
		else Callable(_model, "remove_marker").bind(marker_name)
	)
	_register_edit("Set Marker", do_edit, undo_edit)


func _on_marker_from_playhead() -> void:
	_marker_time.value = _scrubber.get_time()


func _on_remove_marker() -> void:
	var selected := _marker_list.get_selected_items()
	if selected.is_empty() or _model.sequence == null:
		return
	var marker_name := String(_marker_list.get_item_metadata(selected[0]))
	var marker_time := _model.sequence.get_marker_time(marker_name)
	if marker_time < 0.0:
		return
	_register_edit(
		"Remove Marker",
		Callable(_model, "remove_marker").bind(marker_name),
		Callable(_model, "set_marker").bind(marker_name, marker_time)
	)


func _on_toggle_play() -> void:
	if _timeline.get_duration() <= 0.0:
		return
	if _playing:
		_stop_playback(false)
		return
	if _scrubber.get_time() >= _timeline.get_duration() - 0.0001:
		_scrubber.set_time(0.0)
	_playing = true
	_play_button.text = "Pause"
	_playback_shot = -1


func _on_stop_pressed() -> void:
	_stop_playback(true)


func _stop_playback(rewind: bool) -> void:
	_playing = false
	_playback_shot = -1
	_play_button.text = "Play"
	if rewind:
		_scrubber.set_time(0.0)
	_set_preview_time(_scrubber.get_time())


func _on_scrubber_seek(value: float) -> void:
	_set_preview_time(value)


func _on_scrubber_shot_clicked(index: int) -> void:
	if index >= 0:
		_model.select_shot(index)


func _set_preview_time(value: float) -> void:
	_scrubber.set_time(value)
	_update_preview_labels()


func _update_preview_labels() -> void:
	var duration := _timeline.get_duration()
	var current := float(_scrubber.get_time())
	_time_label.text = "%.2f / %.2f s" % [current, duration]
	var state := _timeline.get_shot_local_time(current)
	var index := int(state.get("index", -1))
	if index < 0 or _model.sequence == null:
		_shot_time_label.text = "No sequence"
		return
	var shot := _model.sequence.shots[index]
	var kind_name := "unknown" if shot == null else shot.get_kind_name()
	_shot_time_label.text = (
		"Shot %d/%d · %s · %.2f / %.2fs"
		% [
			index + 1,
			_model.sequence.shots.size(),
			kind_name,
			float(state.get("time", 0.0)),
			float(state.get("duration", 0.0)),
		]
	)


func _on_model_changed() -> void:
	if _loading:
		return
	_dirty = true
	_refresh_all()


func _on_selection_changed(_shot_index: int, _cue_index: int) -> void:
	if _loading:
		return
	_refresh_selection_views()


func _refresh_all() -> void:
	_refreshing = true
	_refresh_sequence_header()
	_refresh_shot_list()
	_refresh_shot_inspector()
	_refresh_cue_list()
	_refresh_cue_inspector()
	_refresh_markers()
	_refresh_validation()
	_refreshing = false

	_timeline.set_sequence(_model.sequence)
	_scrubber.set_sequence(_model.sequence)
	if _scrubber.get_time() > _timeline.get_duration():
		_scrubber.set_time(_timeline.get_duration())
	if _timeline.get_duration() <= 0.0:
		_stop_playback(false)
	_refresh_selection_views()
	_update_preview_labels()
	_update_dirty_label()


func _refresh_selection_views() -> void:
	if _model.sequence == null:
		return
	_refreshing = true
	if _model.shot_index >= 0:
		_shot_list.select(_model.shot_index)
		_shot_list.ensure_current_is_visible()
	else:
		_shot_list.deselect_all()
	_refresh_shot_inspector()
	_refresh_cue_list()
	_refresh_cue_inspector()
	_refresh_markers()
	_refreshing = false
	_scrubber.set_selection(_model.shot_index, _model.cue_index)
	_update_preview_labels()


func _refresh_sequence_header() -> void:
	var sequence := _model.sequence
	if _sequence_picker.edited_resource != sequence:
		_sequence_picker.edited_resource = sequence
	if not _name_edit.has_focus():
		_name_edit.text = "" if sequence == null else sequence.display_name


func _refresh_shot_list() -> void:
	_shot_list.clear()
	if _model.sequence == null:
		return
	for index in _model.sequence.shots.size():
		var shot := _model.sequence.shots[index]
		var kind_name := "null" if shot == null else shot.get_kind_name()
		var duration := 0.0 if shot == null else shot.get_safe_duration()
		var cue_count := 0 if shot == null else shot.cues.size()
		var text := "%02d  %-10s  %5.2fs  %d cue%s" % [
			index + 1,
			kind_name,
			duration,
			cue_count,
			"" if cue_count == 1 else "s",
		]
		_shot_list.add_item(text)
		_shot_list.set_item_metadata(index, shot)
	if _model.shot_index >= 0:
		_shot_list.select(_model.shot_index)
		_shot_list.ensure_current_is_visible()


func _refresh_shot_inspector() -> void:
	var shot := _model.get_selected_shot()
	_shot_panel.visible = shot != null
	if shot == null:
		return
	_shot_kind.select(shot.kind)
	_shot_duration.value = shot.duration
	_shot_zoom.value = shot.zoom
	_shot_target.text = String(shot.target)
	_shot_ease.select(shot.ease)
	_shot_trans.select(shot.trans)
	_shot_rect_x.value = shot.rect.position.x
	_shot_rect_y.value = shot.rect.position.y
	_shot_rect_w.value = shot.rect.size.x
	_shot_rect_h.value = shot.rect.size.y


func _refresh_cue_list() -> void:
	_cue_list.clear()
	var shot := _model.get_selected_shot()
	if shot == null:
		return
	for index in shot.cues.size():
		var cue := shot.cues[index]
		var action := "null" if cue == null else String(cue.action)
		var timing := ""
		if cue != null:
			if not cue.marker.is_empty():
				timing = "marker:%s" % cue.marker
			else:
				timing = "%.2fs" % cue.time
		var target := "" if cue == null or cue.target.is_empty() else " → %s" % cue.target
		_cue_list.add_item("%02d  %s @ %s%s" % [index + 1, action, timing, target])
		_cue_list.set_item_metadata(index, cue)
	if _model.cue_index >= 0:
		_cue_list.select(_model.cue_index)
		_cue_list.ensure_current_is_visible()


func _refresh_cue_inspector() -> void:
	var cue := _model.get_selected_cue()
	_cue_panel.visible = cue != null
	if cue == null:
		return
	_ensure_option_item(_cue_action, cue.action)
	_cue_action.select(_find_option_index(_cue_action, cue.action))
	_cue_time.value = cue.time
	_refresh_marker_options(cue)
	_cue_target.text = String(cue.target)
	if not _cue_data.has_focus():
		_cue_data.text = JSON.stringify(cue.data, "\t") if not cue.data.is_empty() else ""
	if _cue_data_error.text.begins_with("Line") or _cue_data_error.text.begins_with("Top-level"):
		_cue_data_error.text = ""
	var absolute := _model.get_cue_absolute_time(cue, _model.shot_index)
	_cue_time_label.text = "Fires at %.2fs in the sequence." % absolute


func _refresh_marker_options(cue: Cue) -> void:
	_cue_marker.clear()
	_cue_marker.add_item("(no marker)")
	_cue_marker.set_item_metadata(0, "")
	var selected := 0
	if _model.sequence != null:
		var names := _model.sequence.get_marker_names()
		if not cue.marker.is_empty() and not names.has(String(cue.marker)):
			names.append(String(cue.marker))
		for index in names.size():
			_cue_marker.add_item(names[index])
			_cue_marker.set_item_metadata(index + 1, names[index])
			if String(cue.marker) == names[index]:
				selected = index + 1
	_cue_marker.select(selected)


func _refresh_markers() -> void:
	_marker_list.clear()
	if _model.sequence == null:
		return
	for marker: Dictionary in _model.sequence.markers:
		var marker_name := String(marker.get("name", ""))
		var marker_time := float(marker.get("time", 0.0))
		_marker_list.add_item("%s  ·  %.2fs" % [marker_name, marker_time])
		var index := _marker_list.get_item_count() - 1
		_marker_list.set_item_metadata(index, marker_name)


func _refresh_validation() -> void:
	if _model.sequence == null:
		_validation_label.text = "No sequence loaded."
		_validation_label.add_theme_color_override("font_color", Color(0.55, 0.6, 0.68))
		return
	var issues := _model.validate()
	if issues.is_empty():
		_validation_label.text = "✓ %.2fs · %d shot%s · no validation issues" % [
			_model.sequence.get_total_duration(),
			_model.sequence.shots.size(),
			"" if _model.sequence.shots.size() == 1 else "s",
		]
		_validation_label.add_theme_color_override("font_color", Color(0.55, 0.78, 0.65))
	else:
		_validation_label.text = "%d issue%s\n%s" % [
			issues.size(),
			"" if issues.size() == 1 else "s",
			"\n".join(issues),
		]
		_validation_label.add_theme_color_override("font_color", Color(0.95, 0.58, 0.52))


func _update_dirty_label() -> void:
	if _model.sequence == null:
		_dirty_label.text = "v%s" % VERSION
	elif _dirty:
		_dirty_label.text = "● modified"
		_dirty_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.33))
	else:
		_dirty_label.text = "● saved"
		_dirty_label.add_theme_color_override("font_color", Color(0.55, 0.78, 0.65))


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _register_edit(
	action_name: String,
	do_edit: Callable,
	undo_edit: Callable,
	merge_mode: int = UndoRedo.MERGE_DISABLE
) -> void:
	var undo_redo := EditorInterface.get_editor_undo_redo()
	if undo_redo == null:
		do_edit.call()
		return
	undo_redo.create_action(action_name, merge_mode, self)
	undo_redo.add_do_method(self, "_invoke_callable", do_edit)
	undo_redo.add_undo_method(self, "_invoke_callable", undo_edit)
	undo_redo.commit_action()


func _invoke_callable(callable: Callable) -> void:
	callable.call()


func _push_property_edit(
	object: Object, property: String, value: Variant, action_name: String
) -> void:
	if object == null:
		return
	var previous: Variant = object.get(property)
	if previous == value:
		return
	var undo_redo := EditorInterface.get_editor_undo_redo()
	if undo_redo == null:
		object.set(property, value)
		_model.touch()
		return
	undo_redo.create_action(action_name, UndoRedo.MERGE_ENDS, self)
	undo_redo.add_do_property(object, property, value)
	undo_redo.add_undo_property(object, property, previous)
	undo_redo.add_do_method(_model, "touch")
	undo_redo.add_undo_method(_model, "touch")
	undo_redo.commit_action()


func _section_label(text: String, parent: Container = null) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.42, 0.72, 0.86))
	if parent == null:
		_column.add_child(label)
	else:
		parent.add_child(label)
	return label


func _panel(parent: Container) -> PanelContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	return panel


func _panel_box(panel: PanelContainer, title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)
	var label := Label.new()
	label.text = title
	label.add_theme_font_size_override("font_size", 12)
	box.add_child(label)
	return box


func _grid(parent: Container) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 4)
	parent.add_child(grid)
	return grid


func _option(parent: Container, label_text: String, values: Array[String]) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value in values:
		option.add_item(value)
	parent.add_child(option)
	return option


func _spin(
	parent: Container,
	label_text: String,
	minimum: float,
	maximum: float,
	step: float,
	suffix: String = ""
) -> SpinBox:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = true
	spin.suffix = suffix
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _compact_spin(
	parent: Container, minimum: float, maximum: float, step: float
) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.allow_greater = true
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spin)
	return spin


func _line(parent: Container, label_text: String, placeholder: String) -> LineEdit:
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)
	var line := LineEdit.new()
	line.placeholder_text = placeholder
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(line)
	return line


func _button(
	text: String,
	tooltip: String,
	pressed: Callable = Callable()
) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.add_theme_font_size_override("font_size", 11)
	if pressed.is_valid():
		button.pressed.connect(pressed)
	return button


func _ensure_option_item(option: OptionButton, value: StringName) -> void:
	if _find_option_index(option, value) < 0:
		option.add_item(String(value))
		option.set_item_metadata(option.get_item_count() - 1, String(value))


func _find_option_index(option: OptionButton, value: StringName) -> int:
	for index in option.get_item_count():
		if StringName(option.get_item_text(index)) == value:
			return index
	return -1
