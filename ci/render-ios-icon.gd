extends SceneTree

# CI-only: the source SVG remains unchanged in the real game candidate.
# Its original outer teal is extended to square, then alpha is removed explicitly.
const ICON_SIZE := 1024
const ORIGINAL_TEAL := Color("#184c64")

func _initialize() -> void:
	_render.call_deferred()

func _render() -> void:
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() != 2:
		_fail("expected source SVG and isolated destination PNG")
		return
	var source_path: String = arguments[0]
	var destination: String = arguments[1]
	var runtime_root := OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT").simplify_path()
	var runner_root := OS.get_environment("RUNNER_TEMP").simplify_path()
	var expected_source := runner_root.path_join("hospital-ios-build/game/assets/icon.svg")
	var expected_destination := runner_root.path_join("hospital-ios-build/ios-icon/hospital-ios-1024.png")
	if not source_path.is_absolute_path() or not destination.is_absolute_path() or source_path.simplify_path() != expected_source or runtime_root != runner_root.path_join("hospital-ios-build/runtime") or destination.simplify_path() != expected_destination:
		_fail("icon paths must remain inside the isolated hospital build")
		return
	if FileAccess.file_exists(destination):
		_fail("preserve an existing icon output")
		return
	var svg := FileAccess.get_file_as_string(source_path)
	if svg.is_empty():
		_fail("source SVG could not be read")
		return
	var source := Image.new()
	# The actual source icon has an intrinsic 192x192 viewbox.
	if source.load_svg_from_string(svg, float(ICON_SIZE) / 192.0) != OK:
		_fail("source SVG could not be rendered")
		return
	if source.get_size() != Vector2i(ICON_SIZE, ICON_SIZE):
		source.resize(ICON_SIZE, ICON_SIZE, Image.INTERPOLATE_LANCZOS)
	source.convert(Image.FORMAT_RGBA8)
	var opaque := Image.create_empty(ICON_SIZE, ICON_SIZE, false, Image.FORMAT_RGBA8)
	opaque.fill(ORIGINAL_TEAL)
	opaque.blend_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	opaque.convert(Image.FORMAT_RGB8)
	if opaque.get_format() != Image.FORMAT_RGB8 or opaque.detect_alpha() != Image.ALPHA_NONE or opaque.save_png(destination) != OK:
		_fail("opaque RGB PNG could not be saved")
		return
	var reopened := Image.load_from_file(destination)
	if reopened == null or reopened.get_size() != Vector2i(ICON_SIZE, ICON_SIZE) or reopened.get_format() != Image.FORMAT_RGB8 or reopened.detect_alpha() != Image.ALPHA_NONE:
		_fail("saved icon did not retain opaque RGB format")
		return
	print("HOSPITAL_IOS_ICON_OK: 1024x1024 RGB without alpha; source SVG preserved")
	quit(0)

func _fail(reason: String) -> void:
	printerr("HOSPITAL_IOS_ICON_FAILED: " + reason)
	quit(1)
