#!/usr/bin/env bash
# Runs the headless test suite, one Godot process per test file, in parallel. Prints failures,
# script errors and a summary; -v prints every passing test too.
#   scripts/test.sh                 every test (about 2 minutes)
#   scripts/test.sh --quick         skips the tests each file lists in SLOW (about 30 seconds)
#   scripts/test.sh determinism     only tests whose "file::method" contains the filter
# JOBS=N caps how many Godot processes run at once (default: the CPU count).
# MYAIPLANET_LIVE_AI=1 scripts/test.sh live_ai   calls real AI providers (costs money).
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT_PATH:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
QUICK=""
VERBOSE=0
FILTER=""
for arg in "$@"; do
	case "$arg" in
		--quick) QUICK=--quick ;;
		-v) VERBOSE=1 ;;
		*) FILTER="$arg" ;;
	esac
done
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
STARTED=$SECONDS

# Importing builds the class_name cache that a fresh checkout doesn't have yet. Only redo it when a
# file under src/ changed since the last time.
STAMP=src/.godot/test_import.stamp
if [[ ! -f "$STAMP" || -n "$(find src -path src/.godot -prune -o -type f -newer "$STAMP" -print -quit)" ]]; then
	"$GODOT" --headless --path src --import >/dev/null 2>&1 || true
	touch "$STAMP"
fi

# Files that declare SLOW go first, so the longest processes start early.
FILES=()
for path in $(grep -l '^const SLOW' src/tests/test_*.gd) $(grep -L '^const SLOW' src/tests/test_*.gd); do
	name="$(basename "$path")"
	[[ "$name" == test_case.gd ]] && continue
	if [[ -z "$FILTER" ]] || grep -o '^func test_[A-Za-z0-9_]*' "$path" | sed "s/^func /${name%.gd}::/" | grep -qF -- "$FILTER"; then
		FILES+=("$name")
	fi
done
if [[ ${#FILES[@]} -eq 0 ]]; then
	echo "no tests match \"$FILTER\""
	exit 1
fi

LOGS="$(mktemp -d)"
trap 'rm -rf "$LOGS"' EXIT
printf '%s\n' "${FILES[@]}" | xargs -P "$JOBS" -I{} sh -c \
	'"$0" --headless --path src -s res://tests/run_tests.gd -- '"$QUICK"' --files={} "$1" > "$2/{}.log" 2>&1; echo $? > "$2/{}.rc"' \
	"$GODOT" "$FILTER" "$LOGS"

passed=0
failed=0
skipped=0
status=0
for name in "${FILES[@]}"; do
	log="$LOGS/$name.log"
	summary="$(grep -E '^[0-9]+ passed, [0-9]+ failed' "$log")"
	if [[ "$summary" =~ ^([0-9]+)\ passed,\ ([0-9]+)\ failed(,\ ([0-9]+)\ slow)? ]]; then
		passed=$((passed + BASH_REMATCH[1]))
		failed=$((failed + BASH_REMATCH[2]))
		skipped=$((skipped + ${BASH_REMATCH[4]:-0}))
	fi
	if [[ "$(cat "$LOGS/$name.rc")" != 0 || -z "$summary" ]]; then
		status=1
	fi
	if [[ -z "$summary" ]]; then
		echo "== $name crashed or never finished; last lines:"
		tail -40 "$log"
	elif [[ $VERBOSE -eq 1 ]]; then
		grep -vE '^[0-9]+ passed|^Godot Engine|^$' "$log"
	else
		# A failing test and its messages, plus script errors (they can hide behind a passing test).
		awk '/^  FAIL /{show=1; print; next} /^  ok /{show=0; next} /SCRIPT ERROR|Parse Error/{print; next} show && /^        /{print}' "$log"
	fi
done
echo
echo "$passed passed, $failed failed$([[ $skipped -gt 0 ]] && echo ", $skipped slow skipped") in $((SECONDS - STARTED))s"
exit $status
