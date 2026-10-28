#!/usr/bin/env bash
# DRAFT, NOT EXECUTED. Official standard (non-mono) release, exact pinned hashes.
set -euo pipefail
test "$(uname -s)" = Darwin || { echo 'macOS is required'; exit 1; }
task_dir="${RUNNER_TEMP:?}/hospital-godot-4.7.2"
mkdir -p "$task_dir"
base='https://github.com/godotengine/godot-builds/releases/download/4.7.2-stable'
mac='Godot_v4.7.2-stable_macos.universal.zip'
templates='Godot_v4.7.2-stable_export_templates.tpz'
curl --fail --location --retry 3 --silent --show-error "$base/$mac" -o "$task_dir/$mac"
curl --fail --location --retry 3 --silent --show-error "$base/$templates" -o "$task_dir/$templates"
printf '%s  %s\n' \
 '38aa16e5bba2083941fc5b3e54be0089bd4cc35e32415f5b9fd9a8a6a7b9818255d44532ea8ef94b5aef56c4b407c2d634fa4f657e4ebe681ebbf59b7bac69ca' "$task_dir/$mac" \
 'ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079' "$task_dir/$templates" \
 | shasum -a 512 -c -
ditto -x -k "$task_dir/$mac" "$task_dir/editor"
template_dir="$HOME/Library/Application Support/Godot/export_templates/4.7.2.stable"
mkdir -p "$template_dir"
unzip -j "$task_dir/$templates" 'templates/ios.zip' 'templates/version.txt' -d "$template_dir"
test -s "$template_dir/ios.zip"
test "$(tr -d '\r\n' < "$template_dir/version.txt")" = '4.7.2.stable'
godot_bin="$task_dir/editor/Godot.app/Contents/MacOS/Godot"
test -x "$godot_bin"
test "$("$godot_bin" --version | tr -d '\r\n')" = '4.7.2.stable.official.ed1daf0bf'
printf 'GODOT_BIN=%s\n' "$godot_bin" >> "${GITHUB_ENV:?}"
printf 'HOSPITAL_IOS_TEMPLATE=%s\n' "$template_dir/ios.zip" >> "${GITHUB_ENV:?}"
