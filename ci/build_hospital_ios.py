#!/usr/bin/env python3
"""Public-source hospital build. Real Godot -> Xcode, existing signing assets only.

Subcommands export/unsigned/signed separate the no-secret engine phase from P12.
Never calls Apple management APIs, match, automatic provisioning or upload.
"""
import base64
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import re
import secrets
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import zipfile

ROOT = Path(os.environ.get("GITHUB_WORKSPACE", ".")).resolve()
OUT = ROOT / "out" / "hospital-ios"
SCRATCH = Path(os.environ.get("RUNNER_TEMP", ".")).resolve() / "hospital-ios-build"
GAME = ROOT / "hospital" / "game"
COPY = SCRATCH / "game"
XCODE = SCRATCH / "xcode"
NAME = "HospitalBeta"


def need(name, pattern=None):
    value = os.environ.get(name, "").strip()
    if not value or (pattern and not re.fullmatch(pattern, value)):
        raise RuntimeError("Missing/invalid required configuration: " + name)
    return value


def run(args, name, secret=False, env=None, cwd=None, timeout=None):
    OUT.mkdir(parents=True, exist_ok=True)
    stage = name if isinstance(name, str) and re.fullmatch(r"[a-z][a-z0-9-]{0,63}", name) else "command"
    print("HOSPITAL_STAGE_START: " + stage, flush=True)
    try:
        result = subprocess.run([str(x) for x in args], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, cwd=cwd, timeout=timeout)
    except subprocess.TimeoutExpired:
        print("HOSPITAL_STAGE_END: " + stage + " deadline-exceeded", flush=True)
        raise RuntimeError(stage + " exceeded its bounded runtime; raw partial output withheld") from None
    except OSError:
        print("HOSPITAL_STAGE_END: " + stage + " launch-failed", flush=True)
        raise RuntimeError(stage + " could not start; command arguments and raw errors withheld") from None
    if not secret:
        (OUT / (stage + ".log")).write_bytes(result.stdout)
    print("HOSPITAL_STAGE_END: " + stage + (" success" if result.returncode == 0 else " failed (%d)" % result.returncode), flush=True)
    if result.returncode:
        if not secret:
            # These are controlled stage errors only, never whole commands/logs.
            # Retain no public artifact. Redact both the parent and child env values.
            sensitive_keys = ("ASC_ISSUER_ID", "ASC_KEY_ID", "ASC_KEY_P8", "HOSPITAL_DISTRIBUTION_P12_B64",
                              "HOSPITAL_P12_PASSWORD", "HOSPITAL_PROFILE_B64")
            sensitive_values = set()
            for source_env in (os.environ, env or {}):
                for key in sensitive_keys:
                    value = source_env.get(key, "")
                    if isinstance(value, str) and value:
                        sensitive_values.add(value)
                        sensitive_values.add(value.replace("\n", "\\n"))
                        sensitive_values.update(part for part in value.splitlines() if part)
            sensitive_values = sorted(sensitive_values, key=len, reverse=True)
            errors = re.compile(r"(?:SCRIPT\s+ERROR\s*:|Parse\s+Error\s*:|FAIL\s*:|\berror\s*:|\bfatal\s+(?:error\s*)?:)", re.IGNORECASE)
            jwt = re.compile(r"[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,}")
            pem_begin = re.compile(r"-----BEGIN [A-Z0-9 ]+-----")
            pem_end = re.compile(r"-----END [A-Z0-9 ]+-----")
            inside_pem = False
            printed = 0
            prefix = "HOSPITAL_DIAGNOSTIC: "
            for raw_line in result.stdout.decode(errors="replace").splitlines():
                if pem_begin.search(raw_line):
                    inside_pem = not bool(pem_end.search(raw_line))
                    continue
                if inside_pem:
                    if pem_end.search(raw_line):
                        inside_pem = False
                    continue
                if pem_end.search(raw_line) or jwt.search(raw_line) or not errors.search(raw_line):
                    continue
                line = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", raw_line)
                line = "".join(char for char in line if char == "\t" or ord(char) >= 32)
                for value in sensitive_values:
                    line = line.replace(value, "[REDACTED]")
                limit = 300 - len(prefix)
                if len(line) > limit:
                    line = line[:limit - 3] + "..."
                print(prefix + line, flush=True)
                printed += 1
                if printed == 12:
                    break
        raise RuntimeError(f"{stage} failed ({result.returncode}); only bounded sanitized diagnostics may be public")
    return result.stdout


def engine_environment():
    # Only engine children receive isolated HOME; runner and signing HOME stay intact.
    runtime = SCRATCH / "runtime"
    home, temp = runtime / "home", runtime / "tmp"
    home.mkdir(parents=True, exist_ok=True)
    temp.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(HOME=str(home), TEMP=str(temp), TMP=str(temp), TMPDIR=str(temp),
               HOSPITAL_CI_RUNTIME_ROOT=str(runtime))
    return env


def validate():
    if sys.platform != "darwin":
        raise RuntimeError("Requires a Mac runner")
    if os.environ.get("HOSPITAL_REPOSITORY_VISIBILITY") != "public":
        raise RuntimeError("Requires the approved PUBLIC hospital build configuration")
    expected = need("HOSPITAL_EXPECTED_REPOSITORY")
    if expected != "eddie020888-oss/daily-order-hospital-build" or os.environ.get("GITHUB_REPOSITORY") != expected:
        raise RuntimeError("Repository does not match the approved public hospital source")
    event = json.loads(Path(need("GITHUB_EVENT_PATH")).read_text(encoding="utf-8"))
    repository = event.get("repository", {})
    if (repository.get("private") is not False or repository.get("full_name") != expected or
            repository.get("owner", {}).get("login") != "eddie020888-oss" or
            os.environ.get("GITHUB_EVENT_NAME") != "workflow_dispatch" or
            os.environ.get("GITHUB_REF") != "refs/heads/main" or
            os.environ.get("GITHUB_ACTOR") != "eddie020888-oss" or
            event.get("inputs", {}).get("mode") not in {"signed-no-upload", "testflight"}):
        raise RuntimeError("Only owner-dispatched main builds of the approved public hospital source are allowed")
    bundle = need("HOSPITAL_BUNDLE_ID", r"[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+")
    if bundle in {"com.facai.chengqiang", "app.repjournal.training", "org.codexprototype.originalhospital"}:
        raise RuntimeError("Refuse another app or Android prototype identifier")
    team = need("HOSPITAL_TEAM_ID", r"[A-Z0-9]{10}")
    version = need("HOSPITAL_VERSION", r"\d+\.\d+(?:\.\d+)?")
    build = need("HOSPITAL_BUILD_NUMBER", r"\d+(?:\.\d+){0,2}")
    xcode = run(["xcodebuild", "-version"], "xcode-version").decode()
    sdk = run(["xcrun", "--sdk", "iphoneos", "--show-sdk-version"], "ios-sdk-version").decode().strip()
    if int(re.search(r"Xcode (\d+)", xcode)[1]) < 26 or int(sdk.split(".")[0]) < 26:
        raise RuntimeError("Xcode 26+ and iOS 26+ SDK required")
    return bundle, team, version, build


def source_manifest():
    rows = []
    for path in sorted(GAME.rglob("*")):
        if path.is_symlink():
            raise RuntimeError("Source symlinks need explicit review")
        if path.is_file() and ".godot" not in path.parts:
            if path.suffix.lower() in {".p8", ".p12", ".mobileprovision", ".key"} or path.name == "export_credentials.cfg":
                raise RuntimeError("Credential file found in game source")
            rows.append({"path": path.relative_to(GAME).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return rows


def render_ios_icon(godot, engine_env):
    icon_dir = SCRATCH / "ios-icon"
    icon_dir.mkdir(parents=True, exist_ok=False)
    icon = icon_dir / "hospital-ios-1024.png"
    script = ROOT / "ci" / "render-ios-icon.gd"
    if not script.is_file():
        raise RuntimeError("Missing isolated iOS icon renderer")
    result = run([godot, "--headless", "--path", COPY, "--script", script, "--",
                  COPY / "assets" / "icon.svg", icon], "godot-ios-icon", env=engine_env).decode(errors="replace")
    if "HOSPITAL_IOS_ICON_OK" not in result or re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", result):
        raise RuntimeError("Isolated iOS icon rendering failed")
    # PNG color type 2 is RGB without an alpha channel; type 6 is not accepted.
    data = icon.read_bytes()
    if (data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR" or
            struct.unpack(">II", data[16:24]) != (1024, 1024) or data[24:26] != b"\x08\x02"):
        raise RuntimeError("Expected an 8-bit RGB 1024x1024 iOS icon without alpha")
    offset = 8
    while offset + 12 <= len(data):
        size = struct.unpack(">I", data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        if offset + size + 12 > len(data) or kind == b"tRNS":
            raise RuntimeError("Invalid or transparent iOS icon PNG")
        offset += size + 12
        if kind == b"IEND":
            break
    if offset != len(data) or kind != b"IEND":
        raise RuntimeError("Incomplete iOS icon PNG")
    return icon


def validate_profile(document, config, expected_uuid=None):
    bundle, team, _, _ = config
    entitlements = document.get("Entitlements", {})
    prefixes = document.get("ApplicationIdentifierPrefix", [])
    teams = document.get("TeamIdentifier", [])
    prefix = prefixes[0] if isinstance(prefixes, list) and prefixes else None
    if (not isinstance(prefix, str) or teams != [team] or
            entitlements.get("application-identifier") != prefix + "." + bundle or
            entitlements.get("com.apple.developer.team-identifier") != team):
        raise RuntimeError("Profile is not for the confirmed hospital Team/Bundle ID")
    if ("ProvisionedDevices" in document or document.get("ProvisionsAllDevices") or
            entitlements.get("get-task-allow") or "iOS" not in document.get("Platform", [])):
        raise RuntimeError("Only an iOS App Store Connect distribution profile is allowed")
    expiry = document.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime):
        raise RuntimeError("Hospital profile has no valid expiry")
    if expiry.replace(tzinfo=dt.timezone.utc) <= dt.datetime.now(dt.timezone.utc):
        raise RuntimeError("Hospital profile expired")
    uuid, name = document.get("UUID", ""), document.get("Name", "")
    if not re.fullmatch(r"[A-Fa-f0-9]{8}(?:-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}", uuid) or not isinstance(name, str) or not name:
        raise RuntimeError("Hospital profile identity is invalid")
    if expected_uuid is not None and uuid != expected_uuid:
        raise RuntimeError("Final IPA embeds a different hospital profile")
    certs = document.get("DeveloperCertificates", [])
    if not certs or any(not isinstance(cert, bytes) for cert in certs):
        raise RuntimeError("Hospital profile has no distribution certificates")
    return {"uuid": uuid, "name": name, "prefix": prefix,
            "applicationIdentifier": entitlements["application-identifier"],
            "certificateSha1s": {hashlib.sha1(cert).hexdigest().upper() for cert in certs}}


def certificate_metadata(der, config, scratch):
    # Public certificate only; no private key is ever exported from the keychain.
    fingerprint = hashlib.sha1(der).hexdigest().upper()
    cert_path = scratch / (fingerprint + ".cer")
    cert_path.write_bytes(der)
    cert_path.chmod(0o600)
    try:
        result = run(["openssl", "x509", "-inform", "DER", "-in", cert_path, "-noout",
                      "-subject", "-nameopt", "RFC2253", "-startdate", "-enddate"],
                     "inspect-signing-certificate", secret=True).decode(errors="strict")
        subject_match = re.search(r"(?m)^subject\s*=\s*(.+)$", result)
        subject = subject_match[1] if subject_match else ""
        team = config[1]
        if not re.search(r"(?:^|,)\s*OU=" + re.escape(team) + r"(?:,|$)", subject):
            raise RuntimeError("Signing certificate Team differs from the hospital Team")
        if not re.search(r"(?:^|,)\s*CN=(?:Apple Distribution|iPhone Distribution):", subject):
            raise RuntimeError("Hospital signing certificate is not Apple Distribution")
        dates = {}
        for key in ["notBefore", "notAfter"]:
            found = re.search(r"(?m)^" + key + r"=(.+)$", result)
            if not found:
                raise RuntimeError("Signing certificate validity is missing")
            dates[key] = dt.datetime.strptime(found[1].strip(), "%b %d %H:%M:%S %Y GMT").replace(tzinfo=dt.timezone.utc)
        now = dt.datetime.now(dt.timezone.utc)
        if not dates["notBefore"] <= now < dates["notAfter"]:
            raise RuntimeError("Hospital signing certificate is not currently valid")
        return fingerprint
    finally:
        cert_path.unlink(missing_ok=True)


def select_signing_identity(keychain, document, profile, config, scratch):
    result = run(["security", "find-identity", "-v", "-p", "codesigning", keychain],
                 "find-hospital-signing-identity", secret=True).decode(errors="strict")
    identities = {match[1].upper() for match in re.finditer(r'(?m)^\s*\d+\)\s+([A-Fa-f0-9]{40})\s+"', result)}
    matching = identities & profile["certificateSha1s"]
    if len(matching) != 1:
        raise RuntimeError("Need exactly one valid private-key signing identity matching the hospital profile")
    chosen = matching.pop()
    der = next(cert for cert in document["DeveloperCertificates"] if hashlib.sha1(cert).hexdigest().upper() == chosen)
    if certificate_metadata(der, config, scratch) != chosen:
        raise RuntimeError("Hospital certificate identity mismatch")
    return chosen


def entitlement_plist(raw):
    # codesign writes diagnostics to stderr; run() merges it with the XML stdout.
    start, end = raw.find(b"<?xml"), raw.find(b"</plist>")
    if start < 0 or end < start:
        raise RuntimeError("Could not read actual signed IPA entitlements")
    result = plistlib.loads(raw[start:end + len(b"</plist>")])
    if not isinstance(result, dict):
        raise RuntimeError("Signed IPA entitlements are not a dictionary")
    return result


def verify_final_ipa(ipa, config, signing):
    bundle, team, version, build = config
    verification = SCRATCH / "verify-ipa"
    verification.mkdir(parents=True, exist_ok=False)
    # Inspect before ditto extraction; iOS hospital payload has no symbolic links.
    with zipfile.ZipFile(ipa) as archive_file:
        for item in archive_file.infolist():
            member = PurePosixPath(item.filename)
            if (member.is_absolute() or ".." in member.parts or "\\" in item.filename or
                    stat.S_ISLNK(item.external_attr >> 16)):
                raise RuntimeError("Unexpected path or symbolic link in hospital IPA")
    run(["ditto", "-x", "-k", ipa, verification], "unpack-hospital-ipa", secret=True)
    apps = list((verification / "Payload").glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError("Final IPA must contain exactly one hospital app")
    app = apps[0]
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if (info.get("CFBundleIdentifier") != bundle or info.get("CFBundleShortVersionString") != version or
            info.get("CFBundleVersion") != build):
        raise RuntimeError("Actual IPA Bundle/version/build differs from hospital configuration")
    run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", app], "verify-ipa-signature", secret=True)
    signature = run(["codesign", "--display", "--verbose=4", app], "inspect-ipa-signature", secret=True).decode(errors="strict")
    actual_team = re.search(r"(?m)^TeamIdentifier=([^\r\n]+)$", signature)
    actual_bundle = re.search(r"(?m)^Identifier=([^\r\n]+)$", signature)
    if (not actual_team or actual_team[1] != team or not actual_bundle or actual_bundle[1] != bundle):
        raise RuntimeError("Actual IPA signing Team/identifier differs from the hospital")
    profile_path = app / "embedded.mobileprovision"
    document = plistlib.loads(run(["security", "cms", "-D", "-i", profile_path], "decode-ipa-profile", secret=True))
    profile = validate_profile(document, config, expected_uuid=signing["uuid"])
    if signing["identitySha1"] not in profile["certificateSha1s"]:
        raise RuntimeError("Actual IPA profile does not permit the chosen signing certificate")
    entitlements = entitlement_plist(run(["codesign", "--display", "--entitlements", ":-", app], "inspect-ipa-entitlements", secret=True))
    if (entitlements.get("application-identifier") != profile["applicationIdentifier"] or
            entitlements.get("com.apple.developer.team-identifier") != team or entitlements.get("get-task-allow")):
        raise RuntimeError("Actual signed IPA entitlements do not match the hospital profile")
    cert_prefix = verification / "signature-certificate-"
    try:
        run(["codesign", "--display", "--extract-certificates", cert_prefix, app], "extract-ipa-public-certificate", secret=True)
        leaf_path = Path(str(cert_prefix) + "0")
        actual_identity = certificate_metadata(leaf_path.read_bytes(), config, verification)
        if actual_identity != signing["identitySha1"]:
            raise RuntimeError("Final IPA was signed by a different certificate")
    finally:
        for cert_path in verification.glob("signature-certificate-*"):
            cert_path.unlink(missing_ok=True)
    pck = app / (NAME + ".pck")
    if not pck.is_file() or pck.stat().st_size == 0:
        raise RuntimeError("Final IPA is missing the real hospital game pack")
    privacy = app / "PrivacyInfo.xcprivacy"
    with privacy.open("rb") as handle:
        privacy_document = plistlib.load(handle)
    if not isinstance(privacy_document, dict) or not isinstance(privacy_document.get("NSPrivacyAccessedAPITypes"), list):
        raise RuntimeError("Final IPA has no valid privacy API manifest")
    source_manifest_path = OUT / "source-manifest.json"
    return {"bundleId": info["CFBundleIdentifier"], "teamId": actual_team[1], "version": info["CFBundleShortVersionString"],
            "build": info["CFBundleVersion"], "profileUuid": profile["uuid"], "certificateSha1": actual_identity,
            "sourceCommit": os.environ.get("GITHUB_SHA"), "sourceManifestSha256": hashlib.sha256(source_manifest_path.read_bytes()).hexdigest(),
            "ipa": ipa.name, "ipaSha256": hashlib.sha256(ipa.read_bytes()).hexdigest(),
            "gamePackSha256": hashlib.sha256(pck.read_bytes()).hexdigest(),
            "privacyManifestSha256": hashlib.sha256(privacy.read_bytes()).hexdigest(),
            "signatureVerified": True, "entitlementsVerified": True, "actualIpaIdentityVerified": True}


def export_project(config):
    bundle, team, version, build = config
    project = GAME / "project.godot"
    if not project.is_file() or 'run/main_scene="res://main.tscn"' not in project.read_text(encoding="utf-8-sig"):
        raise RuntimeError("Expected the real Godot hospital project, not an HTML prototype")
    if COPY.exists() or XCODE.exists():
        raise RuntimeError("Use a fresh runner output; no overwrite")
    baseline = source_manifest()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "source-manifest.json").write_text(json.dumps({"commit": os.environ.get("GITHUB_SHA"), "files": baseline}, indent=2), encoding="utf-8")
    shutil.copytree(GAME, COPY, ignore=shutil.ignore_patterns(".godot", "export_credentials.cfg"))
    XCODE.mkdir(parents=True)
    godot = Path(need("GODOT_BIN"))
    engine_env = engine_environment()
    runtime_probe = run([godot, "--headless", "--path", COPY, "--script", ROOT / "ci/mac_runtime_probe.gd"], "godot-runtime-probe", env=engine_env).decode(errors="replace")
    if "MAC_RUNTIME_PROBE_RESULT: failed=0" not in runtime_probe:
        raise RuntimeError("Mac runtime isolation probe failed before project import")
    ios_icon = render_ios_icon(godot, engine_env)
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    preset = '\n'.join([
        '[preset.0]', 'name="Hospital iOS"', 'platform="iOS"', 'runnable=false',
        'export_filter="all_resources"', 'include_filter="*.json,*.txt,*.md"',
        'exclude_filter="tests/*"', 'export_path=""', '', '[preset.0.options]',
        'architectures/arm64=true', 'application/export_project_only=true',
        'custom_template/release=' + quote(need("HOSPITAL_IOS_TEMPLATE")),
        'application/export_method_release=0',
        'application/app_store_team_id=' + quote(team),
        'application/bundle_identifier=' + quote(bundle),
        'application/short_version=' + quote(version), 'application/version=' + quote(build),
        'application/code_sign_identity_release="Apple Distribution"',
        # Offline game: no encryption/network feature is implemented by the app.
        'application/additional_plist_content="<key>ITSAppUsesNonExemptEncryption</key><false/>"',
        'icons/icon_1024x1024=' + quote(str(ios_icon)),
        'icons/app_store_1024x1024=' + quote(str(ios_icon)),
        'application/targeted_device_family=0', '',
    ])
    # Only modifies this isolated cloud copy, never the approved public source.
    (COPY / "export_presets.cfg").write_text(preset, encoding="utf-8")
    imported = run([godot, "--headless", "--path", COPY, "--editor", "--import"], "godot-import", env=engine_env).decode(errors="replace")
    if re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", imported):
        raise RuntimeError("Godot import reported an error")
    bootstrap = run([godot, "--headless", "--path", COPY, "--script", "res://tests/run_all.gd", "--", "suite=Bootstrap"], "godot-bootstrap", env=engine_env).decode(errors="replace")
    if "TEST RESULT: failed=0" not in bootstrap or re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", bootstrap):
        raise RuntimeError("Mac runtime/bootstrap regression checks failed")
    tests = run([godot, "--headless", "--path", COPY, "--script", "res://tests/run_all.gd", "--", "suite=All"], "godot-tests", env=engine_env).decode(errors="replace")
    if "TEST RESULT: failed=0" not in tests or re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", tests):
        raise RuntimeError("Real hospital regression tests failed")
    logs = run([godot, "--headless", "--path", COPY, "--export-release", "Hospital iOS", XCODE / (NAME + ".xcodeproj")], "godot-export", env=engine_env).decode(errors="replace")
    if re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", logs):
        raise RuntimeError("Godot export reported an error")
    if not (XCODE / (NAME + ".xcodeproj")).is_dir():
        raise RuntimeError("Godot did not produce the expected Xcode project")
    packs = [path for path in XCODE.rglob(NAME + ".pck") if path.is_file()]
    if len(packs) != 1:
        raise RuntimeError("Need exactly one actual hospital game pack for startup validation")
    empty = SCRATCH / "packed-smoke-empty"
    empty.mkdir(parents=True, exist_ok=False)
    packed = run([godot, "--headless", "--path", empty, "--main-pack", packs[0], "--script",
                  ROOT / "ci/packed_hospital_probe.gd"], "godot-packed-smoke", env=engine_env,
                 cwd=empty, timeout=180).decode(errors="replace")
    if "HOSPITAL_PACKED_RESULT: failed=0" not in packed or re.search(r"(?m)(SCRIPT ERROR:|Parse Error:|^ERROR:)", packed):
        raise RuntimeError("Actual exported hospital pack failed isolated resource/startup validation")
    if source_manifest() != baseline:
        raise RuntimeError("Approved candidate source changed during copy/export")


def archive(config, signed=None):
    bundle, team, version, build = config
    archive_path = SCRATCH / (NAME + ".xcarchive")
    if archive_path.exists():
        raise RuntimeError("Archive already exists; use fresh runner")
    args = ["xcodebuild", "-project", XCODE / (NAME + ".xcodeproj"), "-scheme", NAME,
            "-configuration", "Release", "-destination", "generic/platform=iOS",
            "-derivedDataPath", SCRATCH / "DerivedData", "-archivePath", archive_path,
            "PRODUCT_BUNDLE_IDENTIFIER=" + bundle, "MARKETING_VERSION=" + version,
            "CURRENT_PROJECT_VERSION=" + build]
    if signed:
        args += ["CODE_SIGN_STYLE=Manual", "DEVELOPMENT_TEAM=" + team,
                 "CODE_SIGN_IDENTITY=" + signed["identitySha1"], "PROVISIONING_PROFILE_SPECIFIER=" + signed["name"],
                 "PROVISIONING_PROFILE=" + signed["uuid"]]
    else:
        args += ["CODE_SIGNING_ALLOWED=NO"]
    # No -allowProvisioningUpdates, no automatic profile/certificate creation.
    run(args + ["archive"], "xcode-archive")
    apps = list((archive_path / "Products" / "Applications").glob("*.app"))
    if len(apps) != 1:
        raise RuntimeError("Expected exactly one hospital app in archive")
    with (apps[0] / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if (info.get("CFBundleIdentifier") != bundle or info.get("CFBundleVersion") != build or
            info.get("CFBundleShortVersionString") != version):
        raise RuntimeError("Archived hospital identity/build differs from expected values")
    if not signed:
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", apps[0], OUT / "hospital-unsigned-app.zip"], "package-unsigned-app")
        return
    options = {"method": "app-store-connect", "destination": "export", "signingStyle": "manual", "teamID": team,
               "provisioningProfiles": {bundle: signed["uuid"]}, "signingCertificate": signed["identitySha1"],
               "manageAppVersionAndBuildNumber": False}
    options_path = SCRATCH / "ExportOptions.plist"
    with options_path.open("wb") as handle:
        plistlib.dump(options, handle)
    run(["xcodebuild", "-exportArchive", "-archivePath", archive_path, "-exportPath", OUT / "ipa", "-exportOptionsPlist", options_path], "xcode-export-ipa")
    ipas = list((OUT / "ipa").glob("*.ipa"))
    if len(ipas) != 1:
        raise RuntimeError("Expected exactly one signed hospital IPA")
    identity = verify_final_ipa(ipas[0], config, signed)
    (OUT / "build-identity.json").write_text(json.dumps(identity, indent=2), encoding="utf-8")


def signed_archive(config):
    bundle, team, _, _ = config
    signing = SCRATCH / "signing"
    signing.mkdir(parents=True, exist_ok=False)
    p12 = signing / "distribution.p12"
    profile = signing / "hospital.mobileprovision"
    p12.write_bytes(base64.b64decode(need("HOSPITAL_DISTRIBUTION_P12_B64"), validate=True))
    profile.write_bytes(base64.b64decode(need("HOSPITAL_PROFILE_B64"), validate=True))
    p12.chmod(0o600)
    profile.chmod(0o600)
    document = plistlib.loads(run(["security", "cms", "-D", "-i", profile], "decode-profile", secret=True))
    signing_profile = validate_profile(document, config)
    uuid = signing_profile["uuid"]
    destination = Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles" / (uuid + ".mobileprovision")
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        raise RuntimeError("Profile destination already exists; preserve it")
    keychain = signing / "hospital.keychain-db"
    password = secrets.token_urlsafe(32)
    original = shlex.split(run(["security", "list-keychains", "-d", "user"], "keychain-list", secret=True).decode())
    try:
        shutil.copyfile(profile, destination)
        run(["security", "create-keychain", "-p", password, keychain], "create-keychain", secret=True)
        run(["security", "set-keychain-settings", "-lut", "21600", keychain], "keychain-settings", secret=True)
        run(["security", "unlock-keychain", "-p", password, keychain], "unlock-keychain", secret=True)
        run(["security", "list-keychains", "-d", "user", "-s", keychain, *original], "add-keychain", secret=True)
        run(["security", "import", p12, "-k", keychain, "-P", need("HOSPITAL_P12_PASSWORD"), "-T", "/usr/bin/codesign"], "import-p12", secret=True)
        run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password, keychain], "key-access", secret=True)
        signing_profile["identitySha1"] = select_signing_identity(keychain, document, signing_profile, config, signing)
        archive(config, signed=signing_profile)
    finally:
        subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["security", "delete-keychain", str(keychain)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for path in [destination, p12, profile]:
            path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        mode = sys.argv[1] if len(sys.argv) == 2 else ""
        config = validate()
        if mode == "export":
            export_project(config)
        elif mode == "unsigned":
            archive(config)
        elif mode == "signed":
            signed_archive(config)
        else:
            raise RuntimeError("Use export, unsigned or signed")
        print("Hospital stage completed:", mode, "(no upload performed)")
    except Exception as error:
        # Never serialize environment, private key data, JWTs or raw signing errors.
        print("HOSPITAL_IOS_STAGE_FAILED:", str(error) if isinstance(error, RuntimeError) else type(error).__name__, file=sys.stderr)
        sys.exit(1)
    finally:
        if len(sys.argv) == 2 and sys.argv[1] == "signed":
            for filename in ["distribution.p12", "hospital.mobileprovision"]:
                (SCRATCH / "signing" / filename).unlink(missing_ok=True)
