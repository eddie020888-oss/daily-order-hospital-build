class_name SaveStore
extends RefCounted

# Optional I/O dependency has exists/read/mkdir/write/rename. Each operation
# returns real OS status; no game state or recovery policy is delegated to it.
static func save(snapshot: Dictionary, root_dir: String, file_io: Variant = null) -> Dictionary:
	var io: Variant = SaveFileIO.new() if file_io == null else file_io
	var content := ContentCatalog.load_checked("res://content")
	if not content.ok: return _failure(content.error)
	var checked := ClinicState.from_data(snapshot,content.catalog)
	if not checked.ok: return _failure("invalid_snapshot:"+checked.error)
	if root_dir == "": return _failure("empty_root")
	if io.mkdir(root_dir) != OK: return _failure("mkdir_failed")
	var main := root_dir.path_join("main.json")
	var previous := root_dir.path_join("previous.json")
	var candidate := root_dir.path_join("candidate.json")
	var swap := root_dir.path_join("main.swap.json")
	var next := root_dir.path_join("previous.next.json")
	var existing: bool = io.exists(main) or io.exists(previous) or io.exists(swap)
	if existing:
		var recovery := SaveStore.load(root_dir,content.catalog,io)
		if not recovery.ok: return _failure("committed_files_invalid:"+recovery.error)
		# Deliberate successful save may archive a bad main, but a read-only
		# fallback never changes its bytes. Preserve the selected committed state.
		if not _read(main,content.catalog,io).ok:
			if io.exists(main) and _archive(main,io) == "": return _failure("archive_bad_main_failed")
			if io.write(main,JSON.stringify(recovery.state.to_data())) != OK: return _failure("restore_main_failed")
	# Never overwrite diagnostic candidates, old backup staging or completed swaps.
	for path in [candidate,next,swap]:
		if io.exists(path) and _archive(path,io) == "": return _failure("archive_staging_failed")
	if io.write(candidate,JSON.stringify(snapshot)) != OK: return _failure("candidate_write_failed")
	var candidate_check := _read(candidate,content.catalog,io)
	if not candidate_check.ok or candidate_check.state.to_data() != snapshot: return _failure("candidate_validation_failed")
	if not io.exists(main):
		if io.rename(candidate,main) != OK: return _failure("first_promotion_failed")
		return _success()
	var old_main: String = io.read(main)
	var had_previous: bool = io.exists(previous)
	var old_previous: String = io.read(previous) if had_previous else ""
	if io.write(next,old_main) != OK or io.read(next) != old_main or not _read(next,content.catalog,io).ok: return _failure("backup_copy_failed")
	var archived_previous := ""
	if had_previous:
		archived_previous = _archive(previous,io)
		if archived_previous == "": return _failure("backup_archive_failed")
	var error := ""
	if io.rename(next,previous) != OK: error = "backup_rotation_failed"
	elif io.rename(main,swap) != OK: error = "main_swap_failed"
	elif io.rename(candidate,main) != OK: error = "candidate_promotion_failed"
	if error != "":
		# Best effort rollback. If the medium remains unavailable, startup uses
		# main or swap, both fully validated previously committed snapshots.
		var restored_main := _restore(main,old_main,io)
		var restored_previous := true
		if had_previous:
			restored_previous = _restore(previous,old_previous,io)
		elif io.exists(previous):
			restored_previous = _archive(previous,io) != ""
		return _failure(error + ("" if restored_main and restored_previous else ":rollback_pending"))
	# Promotion is the commit point. A retained swap after a cleanup failure is
	# harmless: valid main wins; no cleanup failure rolls back a committed save.
	var cleanup_error := ""
	if _archive(swap,io) == "": cleanup_error = "committed_swap_retained"
	return _success(cleanup_error)

# Only an explicit player recovery calls this. A durable marker prevents an
# interrupted archive/promotion from silently becoming an automatic new game.
static func recover_new_game(snapshot: Dictionary, root_dir: String, file_io: Variant = null) -> Dictionary:
	var io: Variant=SaveFileIO.new() if file_io==null else file_io
	var marker:=root_dir.path_join("recovery.pending")
	if io.mkdir(root_dir)!=OK: return _failure("recovery_mkdir_failed")
	if not io.exists(marker) and io.write(marker,"Explicit new-game recovery in progress; retained originals must be preserved.")!=OK: return _failure("recovery_marker_failed")
	for name in ["main.json","previous.json","main.swap.json","candidate.json","previous.next.json"]:
		var path:=root_dir.path_join(name)
		if io.exists(path) and _archive(path,io)=="": return _failure("recovery_preservation_failed")
	var result:=save(snapshot,root_dir,io)
	if not result.ok: return result
	if _archive(marker,io)=="": return _failure("recovery_commit_pending")
	return _success()

static func load(root_dir: String, catalog: ContentCatalog, file_io: Variant = null) -> Dictionary:
	var io: Variant = SaveFileIO.new() if file_io == null else file_io
	var main := root_dir.path_join("main.json")
	var previous := root_dir.path_join("previous.json")
	var swap := root_dir.path_join("main.swap.json")
	var main_result := _read(main,catalog,io)
	if main_result.ok: return main_result
	var swap_result := _read(swap,catalog,io)
	if swap_result.ok:
		# A swap is a committed old main, unlike candidate/previous.next. Copy
		# it back only after preserving any damaged main; retain swap evidence.
		var restored := _restore(main,io.read(swap),io)
		swap_result.used_backup = true
		swap_result.error = "main:"+main_result.error+";recovered_swap"+("" if restored else ":restore_pending")
		return swap_result
	var backup := _read(previous,catalog,io)
	if backup.ok:
		backup.used_backup = true
		backup.error = "main:"+main_result.error+";using_previous"
		return backup
	return _failure("main:"+main_result.error+";swap:"+swap_result.error+";previous:"+backup.error)

static func _read(path: String, catalog: ContentCatalog, io: Variant) -> Dictionary:
	if not io.exists(path): return _failure("missing")
	var raw: String = io.read(path)
	var json := JSON.new()
	if json.parse(raw) != OK: return _failure("invalid_json")
	# Validate decimal tokens before trusting the parser's doubles. A fraction
	# such as 1.00000000000000001 rounds to 1.0 and must still be rejected.
	if not _lossless_numbers(raw): return _failure("invalid_json_integer")
	var normalized := _integers(json.data)
	if not normalized.ok: return _failure("invalid_json_integer")
	if not normalized.value is Dictionary: return _failure("invalid_document")
	return ClinicState.from_data(normalized.value,catalog)

static func _lossless_numbers(raw: String) -> bool:
	var quoted := false
	var escaped := false
	var index := 0
	while index < raw.length():
		var ch := raw[index]
		if quoted:
			if escaped: escaped = false
			elif ch == "\\": escaped = true
			elif ch == '"': quoted = false
			index += 1
			continue
		if ch == '"':
			quoted = true
			index += 1
			continue
		if ch == "-" or ch in "0123456789":
			var start := index
			while index < raw.length() and raw[index] in "0123456789.eE+-": index += 1
			if not _integer_token(raw.substr(start,index-start)): return false
		else: index += 1
	return true

static func _integer_token(token: String) -> bool:
	var parts := token.to_lower().trim_prefix("-").split("e")
	var decimal := parts[0].split(".")
	var digits: String = decimal[0]+(decimal[1] if decimal.size() == 2 else "")
	while digits.begins_with("0"): digits = digits.substr(1)
	if digits == "": return true
	var exponent := 0
	if parts.size() == 2:
		var power: String = parts[1].trim_prefix("+").trim_prefix("-")
		while power.begins_with("0"): power = power.substr(1)
		if power.length() > 6: return false
		exponent = int(parts[1])
	var shift: int = exponent-(decimal[1].length() if decimal.size() == 2 else 0)
	if shift < 0:
		if -shift >= digits.length(): return false
		for i in range(-shift):
			if not digits.ends_with("0"): return false
			digits = digits.substr(0,digits.length()-1)
	elif shift > 0:
		if digits.length()+shift > 16: return false
		digits += "0".repeat(shift)
	return digits.length() <= 16 and int(digits) <= SnapshotValidator.MAX_INTEGER

static func _integers(value: Variant, depth: int = 0) -> Dictionary:
	if depth > 64: return {"ok":false}
	if value is float:
		if not is_finite(value) or value != floor(value) or absf(value) > SnapshotValidator.MAX_INTEGER: return {"ok":false}
		return {"ok":true,"value":int(value)}
	if value is Array or value is Dictionary:
		var result: Variant = [] if value is Array else {}
		for key in range(value.size()) if value is Array else value.keys():
			var child := _integers(value[key],depth+1)
			if not child.ok: return child
			if value is Array: result.append(child.value)
			else: result[key] = child.value
		return {"ok":true,"value":result}
	return {"ok":true,"value":value}

static func _archive(path: String, io: Variant) -> String:
	var stem := path+".retained-%d-%d" % [Time.get_unix_time_from_system(),Time.get_ticks_usec()]
	var target := stem
	var suffix := 0
	while io.exists(target):
		suffix += 1
		target = stem+"-"+str(suffix)
	return target if io.rename(path,target) == OK else ""

static func _restore(path: String, bytes: String, io: Variant) -> bool:
	if io.exists(path):
		if io.read(path) == bytes: return true
		if _archive(path,io) == "": return false
	return io.write(path,bytes) == OK

static func _failure(error: String) -> Dictionary:
	return {"ok":false,"state":null,"error":error,"used_backup":false}

static func _success(error: String = "") -> Dictionary:
	return {"ok":true,"state":null,"error":error,"used_backup":false}
