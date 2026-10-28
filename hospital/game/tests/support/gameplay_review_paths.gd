extends RefCounted

# Storage adapter only. Gameplay assertions and the original Mac CI policy stay
# in their existing owners. Windows evidence belongs solely to this task.
const FormalPaths=preload("res://tests/support/formal_test_paths.gd")
const WINDOWS_ROOT:String="E:/CODEX/2026-10-28/医院逻辑与游戏性复审"

static func reserve(requested_output:String,tag:String)->Dictionary:
	if OS.get_name()!="Windows":return FormalPaths.reserve(requested_output,tag)
	var report:String=FormalPaths._canonical(requested_output)
	if report=="" or not FormalPaths._descendant(report,WINDOWS_ROOT) or report.get_extension()!="json":return {"ok":false,"code":"report_path_rejected"}
	var folder:String=report.get_base_dir()
	if not FormalPaths._descendant(folder,WINDOWS_ROOT) or FileAccess.file_exists(report) or DirAccess.dir_exists_absolute(report) or FileAccess.file_exists(folder) or DirAccess.dir_exists_absolute(folder):return {"ok":false,"code":"report_directory_not_fresh"}
	if not FormalPaths._no_links(folder):return {"ok":false,"code":"report_link_rejected"}
	if not FormalPaths._fresh_directory(folder):return {"ok":false,"code":"report_directory_create_failed"}
	if not FormalPaths._no_links(folder):return {"ok":false,"code":"report_link_rejected"}
	var paths=FormalPaths.new()
	paths.output_path=report;paths.run_root=folder;paths.allowed_root=WINDOWS_ROOT
	return {"ok":true,"paths":paths,"output":paths.output_path,"run_root":paths.run_root,"tag":tag}
