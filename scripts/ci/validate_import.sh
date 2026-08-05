#!/usr/bin/env bash
# Headless import/parse gate for CI and local runs.
# Requires Godot 4.7.x on PATH or via GODOT=/path/to/Godot_v4.7-stable_linux.x86_64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
FAIL=0
HEADLESS_SMOKE_SCENE="res://scenes/debug/verify_match_reset.tscn"

fail() {
	echo "VALIDATION FAIL: $1" >&2
	FAIL=1
}

require_godot() {
	if ! command -v "$GODOT" >/dev/null 2>&1 && [[ ! -x "$GODOT" ]]; then
		echo "VALIDATION FAIL: Godot not found (set GODOT to the 4.7 binary)" >&2
		exit 127
	fi
}

check_autoload_paths() {
	local project_file="$ROOT/project.godot"
	local missing=0
	local in_autoload=0
	local line path rel
	while IFS= read -r line; do
		if [[ "$line" == "[autoload]" ]]; then
			in_autoload=1
			continue
		fi
		if [[ "$line" =~ ^\[ ]]; then
			in_autoload=0
		fi
		if [[ "$in_autoload" -eq 1 ]] && [[ "$line" =~ res:// ]]; then
			path="$(grep -oE 'res://[^"]+' <<<"$line" | head -n1)"
			rel="${path#res://}"
			if [[ ! -f "$ROOT/$rel" ]]; then
				echo "Missing autoload script: $path" >&2
				missing=1
			fi
		fi
	done < "$project_file"
	if [[ "$missing" -ne 0 ]]; then
		fail "One or more autoload paths from project.godot are missing"
	fi
}

check_main_scene() {
	local main_scene
	main_scene="$(grep -E '^run/main_scene=' "$ROOT/project.godot" | head -n1 | cut -d= -f2- | tr -d '"')"
	if [[ -z "$main_scene" ]]; then
		fail "run/main_scene is not set in project.godot"
		return
	fi
	local rel="${main_scene#res://}"
	if [[ ! -f "$ROOT/$rel" ]]; then
		fail "run/main_scene points to missing file: $main_scene"
	fi
}

check_scene_resource_paths() {
	local missing=0
	while IFS= read -r path; do
		local rel="${path#res://}"
		if [[ ! -e "$ROOT/$rel" ]]; then
			echo "Missing scene/resource reference: $path" >&2
			missing=1
		fi
	done < <(grep -rhoE 'path="res://[^"]+"' "$ROOT" --include='*.tscn' 2>/dev/null \
		| sed 's/^path="//;s/"$//' | sort -u || true)
	if [[ "$missing" -ne 0 ]]; then
		fail "One or more scene ext_resource paths are missing"
	fi
}

scan_godot_log() {
	local log="$1"
	local label="$2"
	if grep -Eiq '(SCRIPT ERROR|Parse Error|Failed to load|Cannot open file|Compile Error|ERROR:.*\.gd)' "$log"; then
		cat "$log" >&2
		fail "$label"
	fi
}

check_headless_import() {
	local log
	log="$(mktemp)"
	trap 'rm -f "$log"' RETURN
	if ! "$GODOT" --headless --path "$ROOT" --import >"$log" 2>&1; then
		cat "$log" >&2
		fail "Godot headless import exited non-zero"
		return
	fi
	scan_godot_log "$log" "Godot import/parse reported script or resource errors"
}

check_headless_smoke_scene() {
	local log
	log="$(mktemp)"
	trap 'rm -f "$log"' RETURN
	if ! "$GODOT" --headless --path "$ROOT" --scene "$HEADLESS_SMOKE_SCENE" >"$log" 2>&1; then
		cat "$log" >&2
		fail "Headless smoke scene exited non-zero"
		return
	fi
	scan_godot_log "$log" "Headless smoke scene reported script or resource errors"
}

echo "== Static checks =="
check_autoload_paths
check_main_scene
check_scene_resource_paths

echo "== Godot headless import/parse =="
require_godot
check_headless_import

echo "== Godot headless smoke scene =="
check_headless_smoke_scene

if [[ "$FAIL" -ne 0 ]]; then
	exit 1
fi

echo "VALIDATION PASS: import, references, autoloads, and headless smoke scene"
