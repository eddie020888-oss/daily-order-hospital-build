class_name FormalTestPaths
extends RefCounted

# Test storage only. No game factory, command, patient or assertion lives here.
const WINDOWS_ROOT:String="E:/CODEX/2026-10-28/医院经营闭环优化"
var output_path:String=""
var run_root:String=""
var allowed_root:String=""
var fixture_serial:int=0

static func _canonical(path:String)->String:
	var normalized:String=path.replace("\\","/").trim_suffix("/")
	if normalized=="" or not normalized.is_absolute_path() or normalized.simplify_path()!=normalized:return ""
	return normalized

static func _descendant(path:String,base:String)->bool:
	return path.begins_with(base+"/") and path!=base

static func _policy_root(platform:String,github_actions:String,runner_temp:String,runtime_root:String)->String:
	if platform=="Windows":return WINDOWS_ROOT
	if platform!="macOS" or github_actions!="true":return ""
	var runner:String=_canonical(runner_temp)
	var runtime:String=_canonical(runtime_root)
	if runner=="" or runtime=="" or runtime!=runner.path_join("hospital-ios-build/runtime"):return ""
	if runner_temp.replace("\\","/")!=runner or runtime_root.replace("\\","/")!=runtime:return ""
	return runtime.path_join("formal-gameplay-checks")

static func _no_links(path:String)->bool:
	var current:String=path
	while current!="":
		var parent:String=current.get_base_dir()
		if parent.ends_with(":"):parent+="/"
		if parent==current or parent=="":break
		if DirAccess.dir_exists_absolute(parent):
			var directory:DirAccess=DirAccess.open(parent)
			if directory==null or directory.is_link(current.get_file()):return false
		current=parent
	return true

static func _fresh_directory(folder:String)->bool:
	var parent:String=folder.get_base_dir()
	if not _no_links(folder):return false
	if not DirAccess.dir_exists_absolute(parent) and DirAccess.make_dir_recursive_absolute(parent)!=OK:return false
	if not _no_links(parent):return false
	return DirAccess.make_dir_absolute(folder)==OK and _no_links(folder)

static func reserve(requested_output:String,tag:String)->Dictionary:
	var base:String=_policy_root(OS.get_name(),OS.get_environment("GITHUB_ACTIONS"),OS.get_environment("RUNNER_TEMP"),OS.get_environment("HOSPITAL_CI_RUNTIME_ROOT"))
	if base=="":return {"ok":false,"code":"platform_or_ci_gate_rejected"}
	var report:String=_canonical(requested_output)
	if report=="" or not _descendant(report,base) or report.get_extension()!="json":return {"ok":false,"code":"report_path_rejected"}
	var folder:String=report.get_base_dir()
	if not _descendant(folder,base) or FileAccess.file_exists(report) or DirAccess.dir_exists_absolute(report) or FileAccess.file_exists(folder) or DirAccess.dir_exists_absolute(folder):return {"ok":false,"code":"report_directory_not_fresh"}
	if not _no_links(folder):return {"ok":false,"code":"report_link_rejected"}
	if not _fresh_directory(folder):return {"ok":false,"code":"report_directory_create_failed"}
	if not _no_links(folder):return {"ok":false,"code":"report_link_rejected"}
	var paths:=FormalTestPaths.new()
	paths.output_path=report;paths.run_root=folder;paths.allowed_root=base
	return {"ok":true,"paths":paths,"output":report,"run_root":folder,"tag":tag}

func fixture(tag:String)->String:
	var slug:String=""
	for character:String in tag:
		if character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":slug+=character
	if slug=="":slug="fixture"
	fixture_serial+=1
	var folder:String=run_root.path_join("fixtures/%d-%d-%04d-%s"%[OS.get_process_id(),Time.get_ticks_usec(),fixture_serial,slug])
	if not _descendant(folder,allowed_root) or not _no_links(folder) or FileAccess.file_exists(folder) or DirAccess.dir_exists_absolute(folder):return ""
	if not _fresh_directory(folder):return ""
	return folder

func write_report(report:Dictionary,indent:String="  ")->Error:
	if not _descendant(output_path,allowed_root) or not _no_links(output_path) or FileAccess.file_exists(output_path) or DirAccess.dir_exists_absolute(output_path):return ERR_ALREADY_EXISTS
	var file:FileAccess=FileAccess.open(output_path,FileAccess.WRITE)
	if file==null:return FileAccess.get_open_error()
	file.store_string(JSON.stringify(report,indent))
	var error:Error=file.get_error()
	file.close()
	return error
