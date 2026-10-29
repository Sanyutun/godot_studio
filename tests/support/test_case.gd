extends SceneTree
## Tiny dependency-free test harness for `godot --headless -s tests/...`.
##
## Subclasses override [method _run_tests] and call [method finish] at the end.
## Exit code 0 = pass, 1 = failed checks, 2 = harness misuse.

var _checks: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	# In `-s` script mode the SceneTree root enters the tree after _initialize(),
	# so wait one frame before tests create nodes and play tweens.
	_start()


func _start() -> void:
	await process_frame
	_run_tests()


## Overridden by each test script.
func _run_tests() -> void:
	push_error("test_case.gd: override _run_tests().")
	quit(2)


## Records a boolean assertion.
func check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)
		printerr("  FAIL: %s" % message)


## Records a float assertion with tolerance.
func check_approx(actual: float, expected: float, tolerance: float, message: String) -> void:
	var ok := absf(actual - expected) <= tolerance
	check(ok, "%s (expected %.4f ± %.4f, got %.4f)" % [message, expected, tolerance, actual])


## Awaits [param seconds] of SceneTree time.
func wait(seconds: float) -> void:
	await create_timer(maxf(seconds, 0.0)).timeout


## Creates a scratch node under the test tree.
func make_root(node_name: String = "TestRoot") -> Node:
	var node := Node.new()
	node.name = node_name
	root.add_child(node)
	return node


## Frees a scratch node and flushes one frame.
func dispose(node: Node) -> void:
	if is_instance_valid(node):
		node.queue_free()
	await process_frame


## Prints the summary and exits with the right code.
func finish() -> void:
	if _failures.is_empty():
		print("PASS (%d checks)" % _checks)
		quit(0)
		return
	printerr("FAILED (%d of %d checks)" % [_failures.size(), _checks])
	quit(1)
