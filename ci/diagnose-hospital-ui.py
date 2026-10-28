#!/usr/bin/env python3
"""Manual no-signing diagnostic; raw game output stays on the ephemeral runner."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys

REPOSITORY = "eddie020888-oss/daily-order-hospital-build"
MARKER = re.compile(r"(?m)^FORMAL HUD RESULT: passed=([0-9]+) failed=([0-9]+)[ \t]*\r?$")
# Identical formal cleanliness rule to build_hospital_ios.py, not a relaxed gate.
STRICT = re.compile(r"(SCRIPT\s+ERROR|Parse\s+Error|^\s*(?:ERROR|FATAL)\b|ObjectDB instances were leaked|resources? still in use at exit)", re.I | re.M)
IMPORT_ERRORS = re.compile(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)")
KNOWN_TYPES = {"RefCounted", "GDScript", "GDScriptNativeClass", "Resource", "Node", "Node2D", "Node3D", "Control", "SceneTree", "Timer", "Tween", "FontFile", "FontVariation", "Texture2D", "ImageTexture", "StandardMaterial3D", "ShaderMaterial", "AudioStreamWAV", "AudioStreamOggVorbis", "CallableCustom", "PackedScene"}
GUARD_CODES = {"context_rejected", "event_rejected", "source_identity_rejected", "source_root_rejected", "builder_source_rejected", "isolated_source_mapping_rejected", "scratch_not_fresh", "full_game_source_rejected", "runtime_mapping_rejected", "engine_path_rejected", "report_not_fresh"}


def emit(value):
    # Only explicitly constructed fields ever reach public stdout.
    print("HOSPITAL_UI_DIAGNOSTIC: " + json.dumps(value, sort_keys=True, separators=(",", ":")), flush=True)


def bounded_count(value):
    return value if type(value) is int and 0 <= value <= 1_000_000 else None


def diagnostic_locations(log, public_scripts):
    paths, locations = {}, {}
    backtrace = False
    for line in log.splitlines():
        header = bool(re.search(r"^\s*(?:GDScript\s+)?backtrace\b", line, re.I))
        frame = bool(re.search(r"^\s*\[[0-9]+\]\s", line))
        direct = bool(re.search(r"Leaked instance:|resources? still in use|\bSCRIPT\s+ERROR\s*:|\bParse\s+Error\s*:|^\s*(?:ERROR|FATAL)\s*:|^\s*at:", line, re.I))
        relevant = direct or header or (backtrace and frame)
        if header:
            backtrace = True
        elif line.strip() and not frame:
            backtrace = False
        if not relevant:
            continue
        for match in re.finditer(r"(res://[A-Za-z0-9_./-]+\.gd)\b(?::([0-9]+))?", line):
            path, number = match.groups()
            if path not in public_scripts:
                continue
            paths[path] = True
            if number and len(number) <= 7 and 1 <= int(number) <= 1_000_000:
                locations[(path, int(number))] = True
    return {"public_script_paths": list(paths)[:20], "public_script_paths_truncated": len(paths) > 20,
            "public_script_locations": [{"path": path, "line": line} for path, line in list(locations)[:20]],
            "public_script_locations_truncated": len(locations) > 20}


def summarize(log, returncode, report, public_scripts, timed_out=False, truncated=False):
    rows = MARKER.findall(log)
    passed = bounded_count(int(rows[0][0])) if len(rows) == 1 else None
    failed = bounded_count(int(rows[0][1])) if len(rows) == 1 else None
    json_passed = bounded_count(report.get("passed")) if isinstance(report, dict) else None
    json_failed = bounded_count(report.get("failed")) if isinstance(report, dict) else None
    flags = {
        "script_error": bool(re.search(r"SCRIPT\s+ERROR", log, re.I)),
        "parse_error": bool(re.search(r"Parse\s+Error", log, re.I)),
        "error_or_fatal": bool(re.search(r"^\s*(?:ERROR|FATAL)\b", log, re.I | re.M)),
        "object_leak": bool(re.search(r"ObjectDB instances were leaked", log, re.I)),
        "resource_in_use": bool(re.search(r"resources? still in use at exit", log, re.I)),
    }
    types = {}
    for match in re.finditer(r"\bLeaked instance:\s*([A-Za-z][A-Za-z0-9_]{0,63})(?=[:#\s])", log):
        name = match[1] if match[1] in KNOWN_TYPES else "other"
        types[name] = min(types.get(name, 0) + 1, 1_000_000)
    # Ignore ordinary verbose loader noise; report only public diagnostic frames.
    sources = diagnostic_locations(log, public_scripts)
    clean = (returncode == 0 and not timed_out and not truncated and len(rows) == 1 and
             passed is not None and passed > 0 and failed == 0 and not STRICT.search(log) and
             json_passed == passed and json_failed == 0)
    return {"clean": clean, "returncode": bounded_count(returncode) if returncode >= 0 else -1,
            "timed_out": timed_out, "log_truncated": truncated, "marker_count": min(len(rows), 1_000_000),
            "marker_passed": passed, "marker_failed": failed,
            "json_passed": json_passed, "json_failed": json_failed,
            "error_categories": flags, "leaked_object_types": types, **sources}


def validate_context():
    if (sys.platform != "darwin" or os.environ.get("GITHUB_ACTIONS") != "true" or
            os.environ.get("HOSPITAL_REPOSITORY_VISIBILITY") != "public" or
            os.environ.get("HOSPITAL_EXPECTED_REPOSITORY") != REPOSITORY or
            os.environ.get("GITHUB_REPOSITORY") != REPOSITORY or
            os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or
            os.environ.get("GITHUB_REF") != "refs/heads/main" or
            os.environ.get("GITHUB_ACTOR") != "eddie020888-oss"):
        raise RuntimeError("context_rejected")
    event_path = Path(os.environ["GITHUB_EVENT_PATH"])
    event = json.loads(event_path.read_text(encoding="utf-8"))
    repository = event.get("repository", {})
    if (repository.get("private") is not False or repository.get("full_name") != REPOSITORY or
            repository.get("owner", {}).get("login") != "eddie020888-oss"):
        raise RuntimeError("event_rejected")
    commit = os.environ.get("GITHUB_SHA", "")
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise RuntimeError("source_identity_rejected")
    workspace = Path(os.environ["GITHUB_WORKSPACE"])
    runner = Path(os.environ["RUNNER_TEMP"])
    if (not workspace.is_absolute() or not runner.is_absolute() or
            workspace.is_symlink() or runner.is_symlink()):
        raise RuntimeError("source_root_rejected")
    workspace = workspace.resolve(strict=True)
    runner = runner.resolve(strict=True)
    return workspace, runner, commit


def execute(args, log_path, env, timeout):
    timed_out = False
    with log_path.open("xb") as output:
        try:
            result = subprocess.run([str(x) for x in args], stdout=output, stderr=subprocess.STDOUT,
                                    env=env, timeout=timeout, cwd=log_path.parent)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = -1
            timed_out = True
        except OSError:
            code = -1
    with log_path.open("rb") as source:
        raw = source.read(16 * 1024 * 1024 + 1)
    truncated = len(raw) > 16 * 1024 * 1024
    return raw[:16 * 1024 * 1024].decode(errors="replace"), code, timed_out, truncated


def load_report(path):
    if not path.is_file() or path.is_symlink() or path.stat().st_size > 4 * 1024 * 1024:
        return None
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def main():
    workspace, runner, commit = validate_context()
    builder_path = workspace / "ci" / "build_hospital_ios.py"
    if builder_path.is_symlink() or not builder_path.is_file():
        raise RuntimeError("builder_source_rejected")
    spec = importlib.util.spec_from_file_location("hospital_public_builder", builder_path)
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)  # Does not invoke the builder's __main__.
    if (builder.ROOT != workspace or builder.GAME != workspace / "hospital" / "game" or
            builder.SCRATCH != runner / "hospital-ios-build" or builder.COPY != builder.SCRATCH / "game"):
        raise RuntimeError("isolated_source_mapping_rejected")
    if builder.SCRATCH.exists():
        raise RuntimeError("scratch_not_fresh")
    baseline = builder.source_manifest()  # Existing exact public GAME identity check.
    required = {"main.gd", "project.godot", "tests/test_formal_hud_integration.gd", "tests/support/formal_test_paths.gd"}
    source_paths = {row["path"] for row in baseline}
    if not required <= source_paths or 'run/main_scene="res://main.tscn"' not in (builder.GAME / "project.godot").read_text(encoding="utf-8-sig"):
        raise RuntimeError("full_game_source_rejected")
    public_scripts = {"res://" + path for path in source_paths if path.endswith(".gd")}
    emit({"schema": 1, "stage": "source", "repository": REPOSITORY, "source_commit": commit,
          "game_file_count": len(baseline), "game_manifest_sha256": hashlib.sha256(json.dumps(baseline, sort_keys=True).encode()).hexdigest(),
          "full_game_copy": True, "signing": False, "upload": False, "artifacts": False})
    shutil.copytree(builder.GAME, builder.COPY, ignore=shutil.ignore_patterns(".godot", "export_credentials.cfg"))
    engine_env = builder.engine_environment()  # Same HOME/runtime and original Mac FormalPaths scope.
    for key in list(engine_env):
        if key.startswith(("ASC_", "ACTIONS_")) or key.endswith(("_TOKEN", "_PASSWORD")) or key in {"HOSPITAL_DISTRIBUTION_P12_B64", "HOSPITAL_PROFILE_B64", "ASC_KEY_P8"}:
            engine_env.pop(key, None)
    if Path(engine_env["HOSPITAL_CI_RUNTIME_ROOT"]) != builder.SCRATCH / "runtime":
        raise RuntimeError("runtime_mapping_rejected")
    godot = Path(os.environ["GODOT_BIN"])
    if not godot.is_absolute() or not godot.is_file():
        raise RuntimeError("engine_path_rejected")
    logs = builder.SCRATCH / "ui-diagnostic-logs"
    logs.mkdir(exist_ok=False)
    imported, code, timeout, truncated = execute([godot, "--headless", "--path", builder.COPY, "--editor", "--import"], logs / "import.log", engine_env, 600)
    import_clean = code == 0 and not timeout and not truncated and not IMPORT_ERRORS.search(imported)
    import_summary = summarize(imported, code, None, public_scripts, timeout, truncated)
    import_summary["clean"] = import_clean
    emit({"schema": 1, "stage": "import", **import_summary})
    if not import_clean:
        return 1
    formal_root = Path(engine_env["HOSPITAL_CI_RUNTIME_ROOT"]) / "formal-gameplay-checks"
    normal_clean = False
    for verbose in (False, True):
        if verbose and normal_clean:
            break
        label = "formal-hud-verbose" if verbose else "formal-hud"
        report = formal_root / (label + "-" + secrets.token_hex(8)) / "result.json"
        # Original FormalPaths reserves the final directory. Never precreate it.
        if report.parent.exists():
            raise RuntimeError("report_not_fresh")
        args = [godot, "--headless", "--path", builder.COPY]
        if verbose:
            args.append("--verbose")
        args += ["--script", "res://tests/test_formal_hud_integration.gd", "--", "--output=" + str(report)]
        raw, code, timeout, truncated = execute(args, logs / (label + ".log"), engine_env, 180)
        summary = summarize(raw, code, load_report(report), public_scripts, timeout, truncated)
        emit({"schema": 1, "stage": label, **summary})
        if not verbose:
            normal_clean = summary["clean"]
    unchanged = builder.source_manifest() == baseline
    emit({"schema": 1, "stage": "complete", "normal_clean": normal_clean, "approved_source_unchanged": unchanged,
          "raw_logs_ephemeral_only": True, "release_gate_changed": False})
    return 0 if normal_clean and unchanged else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        # No raw exception, argv, environment, report or log text is printed.
        category = str(error) if isinstance(error, RuntimeError) and str(error) in GUARD_CODES else "unexpected_runtime_error"
        emit({"schema": 1, "stage": "guard-or-runtime-failure", "category": category, "diagnostic_completed": False})
        sys.exit(2)
