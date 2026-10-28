class_name SaveFileIO
extends RefCounted

func exists(path: String) -> bool:
	return FileAccess.file_exists(path)

func read(path: String) -> String:
	return FileAccess.get_file_as_string(path)

func mkdir(path: String) -> Error:
	return DirAccess.make_dir_recursive_absolute(path)

func write(path: String, text: String) -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null: return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	return file.get_error()

func rename(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(from,to)
