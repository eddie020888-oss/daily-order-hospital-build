#!/usr/bin/env python3
"""Emit allowlisted public facts only. Never print raw files, logs or environment."""
import json
import os
from pathlib import Path
import re

ROOT = Path(os.environ.get("GITHUB_WORKSPACE", ".")).resolve()
OUT = ROOT / "out" / "hospital-ios"
OUTCOMES = {"success", "failure", "cancelled", "skipped"}


def small_document(name):
    path = OUT / name
    if not path.is_file() or path.stat().st_size > 16384:
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def outcome(phase):
    value = os.environ.get("HOSPITAL_" + phase.upper() + "_OUTCOME", "")
    return value if value in OUTCOMES else "not-reported"


def checked(value, expression):
    return value if isinstance(value, str) and len(value) <= 200 and re.fullmatch(expression, value) else None


def main():
    identity = small_document("build-identity.json")
    receipt = small_document("upload-receipt.json")
    phases = {name: outcome(name) for name in ["install", "export", "signing", "upload"]}
    counters = None
    tests = OUT / "godot-tests.log"
    if tests.is_file() and tests.stat().st_size <= 1024 * 1024:
        try:
            matches = re.findall(r"(?m)^TEST RESULT: failed=(\d+) passed=(\d+)\s*$", tests.read_text(encoding="utf-8", errors="replace"))
            if matches:
                counters = {"failed": int(matches[-1][0]), "passed": int(matches[-1][1])}
        except OSError:
            pass
    public_identity = {key: checked(identity.get(key), pattern) for key, pattern in {
        "bundleId": r"[A-Za-z0-9][A-Za-z0-9.-]+", "teamId": r"[A-Z0-9]{10}",
        "version": r"\d+\.\d+(?:\.\d+)?", "build": r"\d+(?:\.\d+){0,2}",
        "sourceCommit": r"[a-f0-9]{40}", "ipaSha256": r"[a-f0-9]{64}",
        "gamePackSha256": r"[a-f0-9]{64}", "privacyManifestSha256": r"[a-f0-9]{64}"
    }.items()}
    public_identity = {key: value for key, value in public_identity.items() if value is not None}
    identity_matches = all(identity.get(key) == os.environ.get(variable) for key, variable in {
        "bundleId": "HOSPITAL_BUNDLE_ID", "teamId": "HOSPITAL_TEAM_ID",
        "version": "HOSPITAL_VERSION", "build": "HOSPITAL_BUILD_NUMBER", "sourceCommit": "GITHUB_SHA"
    }.items())
    verified = phases["signing"] == "success" and identity_matches and all(identity.get(key) is True for key in ["signatureVerified", "entitlementsVerified", "actualIpaIdentityVerified"])
    uploaded = (phases["upload"] == "success" and verified and
                receipt.get("ipaSha256") == identity.get("ipaSha256") and
                receipt.get("sourceCommit") == identity.get("sourceCommit") and
                receipt.get("bundleId") == identity.get("bundleId") and receipt.get("build") == identity.get("build"))
    report = {
        "schema": 1, "pipeline": "public-standard-macos", "phases": phases,
        "runId": checked(os.environ.get("GITHUB_RUN_ID"), r"\d+"),
        "workflowSourceCommit": checked(os.environ.get("GITHUB_SHA"), r"[a-f0-9]{40}"),
        "regression": counters, "signedIpaVerified": verified,
        "uploadAcceptedByTool": uploaded, "appleProcessingVerified": False,
        "publicArtifactsPublished": False, "identity": public_identity,
        "note": "No IPA/PCK/source manifest/raw logs are retained publicly. Signed checks are not TestFlight uploads; Apple processing and tester visibility need separate confirmation."
    }
    print("HOSPITAL_PUBLIC_STATUS: " + json.dumps(report, separators=(",", ":")))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        print("HOSPITAL_PUBLIC_STATUS: unavailable; raw status inputs suppressed")
        raise SystemExit(1)
