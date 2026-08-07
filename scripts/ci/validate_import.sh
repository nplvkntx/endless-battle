#!/usr/bin/env bash
# Headless import/parse gate for CI and local runs.
# Requires Godot 4.7.x on PATH or via GODOT=/path/to/Godot_v4.7-stable_linux.x86_64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT="${GODOT:-godot}"
FAIL=0
HEADLESS_SMOKE_SCENE="res://scenes/debug/verify_match_reset.tscn"
HEADLESS_FREED_SCENE="res://scenes/debug/verify_freed_instance_regression.tscn"
HEADLESS_COMPOSITION_SCENE="res://scenes/debug/verify_match_composition_root.tscn"

fail() {
	echo "VALIDATION FAIL: $1" >&2
	if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
		echo "::error::$1"
	fi
	FAIL=1
}

summarize_log() {
	local log="$1"
	local summary
	summary="$(grep -Ei '(SCRIPT ERROR|Parse Error|Failed to load|Cannot open file|Compile Error|FAIL:|ERROR:)' "$log" | tail -n 5 | tr '\n' ' ' || true)"
	if [[ -z "$summary" ]]; then
		summary="$(tail -n 20 "$log" | tr '\n' ' ' || true)"
	fi
	echo "$summary" | cut -c1-500
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

check_canonical_scenes() {
	local main_scene menu_const match_const
	main_scene="$(grep -E '^run/main_scene=' "$ROOT/project.godot" | head -n1 | cut -d= -f2- | tr -d '"')"
	menu_const="$(grep -E '^\s*const MAIN_MENU_SCENE' "$ROOT/autoloads/match_session.gd" | head -n1 | grep -oE 'res://[^"]+' || true)"
	match_const="$(grep -E '^\s*const MATCH_SCENE' "$ROOT/autoloads/match_session.gd" | head -n1 | grep -oE 'res://[^"]+' || true)"

	if [[ -z "$menu_const" || -z "$match_const" ]]; then
		fail "Could not read MatchSession.MAIN_MENU_SCENE / MATCH_SCENE constants"
		return
	fi
	if [[ "$main_scene" != "$menu_const" ]]; then
		fail "run/main_scene ($main_scene) must match MatchSession.MAIN_MENU_SCENE ($menu_const)"
	fi
	if [[ "$main_scene" == "$match_const" ]]; then
		fail "run/main_scene must be the menu entry, not MatchSession.MATCH_SCENE ($match_const)"
	fi
	local match_rel="${match_const#res://}"
	if [[ ! -f "$ROOT/$match_rel" ]]; then
		fail "MatchSession.MATCH_SCENE points to missing file: $match_const"
	fi
}

check_no_root_verify_logs() {
	local stale=()
	local f
	shopt -s nullglob
	for f in "$ROOT"/*_verify_run.txt "$ROOT"/*_verify_err.txt "$ROOT"/*_verify_log.txt \
		"$ROOT"/*_verify_result.txt "$ROOT"/*_run_log.txt "$ROOT"/godot_verify_log.txt \
		"$ROOT"/*handles_verify.txt "$ROOT"/*verify_after_handles.txt \
		"$ROOT"/terrain_decoration_verify_result.txt "$ROOT"/balance_overhaul_verify_run*.txt; do
		[[ -f "$f" ]] && stale+=("$(basename "$f")")
	done
	shopt -u nullglob
	if [[ ${#stale[@]} -gt 0 ]]; then
		fail "Stale root verification logs must not ship in the source tree: ${stale[*]}"
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
	if grep -Eiq '(SCRIPT ERROR|Parse Error|Failed to load|Cannot open file|Compile Error|ERROR:.*\.gd|Lambda capture.*was freed|previously freed|Trying to assign invalid previously freed|Invalid type.*freed)' "$log"; then
		cat "$log" >&2
		fail "$label. $(summarize_log "$log")"
	fi
}

check_headless_import() {
	local log
	log="$(mktemp)"
	trap 'rm -f "$log"' RETURN
	if ! "$GODOT" --headless --path "$ROOT" --import >"$log" 2>&1; then
		cat "$log" >&2
		fail "Godot headless import exited non-zero. $(summarize_log "$log")"
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
		fail "Headless smoke scene exited non-zero. $(summarize_log "$log")"
		return
	fi
	scan_godot_log "$log" "Headless smoke scene reported script or resource errors"
}

check_headless_freed_instance_scene() {
	local log
	log="$(mktemp)"
	trap 'rm -f "$log"' RETURN
	if ! "$GODOT" --headless --path "$ROOT" --scene "$HEADLESS_FREED_SCENE" >"$log" 2>&1; then
		cat "$log" >&2
		fail "Freed-instance regression scene exited non-zero. $(summarize_log "$log")"
		return
	fi
	scan_godot_log "$log" "Freed-instance regression scene reported script or resource errors"
	if ! grep -q "PASS freed_instance_regression" "$log"; then
		cat "$log" >&2
		fail "Freed-instance regression scene did not report PASS"
	fi
}

check_headless_composition_root_scene() {
	local log
	log="$(mktemp)"
	trap 'rm -f "$log"' RETURN
	if ! "$GODOT" --headless --path "$ROOT" --scene "$HEADLESS_COMPOSITION_SCENE" >"$log" 2>&1; then
		cat "$log" >&2
		fail "Match composition root scene exited non-zero. $(summarize_log "$log")"
		return
	fi
	scan_godot_log "$log" "Match composition root scene reported script or resource errors"
	if ! grep -q "PASS match_composition_root" "$log"; then
		cat "$log" >&2
		fail "Match composition root scene did not report PASS"
	fi
}

echo "== Static checks =="
check_autoload_paths
check_main_scene
check_canonical_scenes
check_no_root_verify_logs
check_scene_resource_paths

echo "== Godot headless import/parse =="
require_godot
check_headless_import

echo "== Godot headless smoke scene =="
check_headless_smoke_scene

echo "== Godot freed-instance regression =="
check_headless_freed_instance_scene

echo "== Godot match composition root =="
check_headless_composition_root_scene

if [[ "$FAIL" -ne 0 ]]; then
	exit 1
fi

echo "VALIDATION PASS: import, references, autoloads, headless smoke, freed-instance, and composition root"
