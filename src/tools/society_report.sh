#!/usr/bin/env bash
# Runs tools/society_report.gd in parallel, one Godot process per (god, seed), then prints the merged
# summary. Rows land in OUT_DIR/<god>_<seed>.txt; rows already there (from earlier batches) are
# merged too, so a long report can be run a batch at a time.
#   Godot/tools/society_report.sh OUT_DIR [seeds=1,2,5-style list, a-b range or a count; default the 18 balance
#   islands] [years=360] [gods=none,benevolent,wrathful,meddler] [jobs=6]
# Set GODOT_LOCK=/some/dir to take a mkdir lock around the whole batch (shared import cache).
set -uo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT_PATH:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
OUT="${1:?usage: society_report.sh OUT_DIR [seeds=12] [years=360] [gods=a,b] [jobs=6]}"
shift
SEEDS=1,2,3,4,5,6,7,8,9,10,11,12,13,19,21,23,36,37; YEARS=360; GODS=none,benevolent,wrathful,meddler; JOBS=6; AFTER=0
for arg in "$@"; do
	case "$arg" in
		seeds=*) SEEDS="${arg#seeds=}" ;;
		years=*) YEARS="${arg#years=}" ;;
		gods=*) GODS="${arg#gods=}" ;;
		jobs=*) JOBS="${arg#jobs=}" ;;
		after=*) AFTER="${arg#after=}" ;;
	esac
done
if [[ "$SEEDS" == *,* ]]; then LIST="${SEEDS//,/ }"
elif [[ "$SEEDS" == *-* ]]; then LIST="$(seq "${SEEDS%-*}" "${SEEDS#*-}")"
else LIST="$(seq 1 "$SEEDS")"; fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
if [[ -n "${GODOT_LOCK:-}" ]]; then
	until mkdir "$GODOT_LOCK" 2>/dev/null; do sleep 2; done
	trap 'rmdir "$GODOT_LOCK"' EXIT
fi
for god in ${GODS//,/ }; do
	for seed in $LIST; do
		echo "$god $seed"
	done
done | xargs -P "$JOBS" -n 2 sh -c '"$0" --headless --path Godot -s res://tools/society_report.gd -- seeds="$2-$2" years='"$YEARS"' gods="$1" after='"$AFTER"' rows=0 > "'"$OUT"'/$1_$2.txt" 2>&1' "$GODOT"
"$GODOT" --headless --path Godot -s res://tools/society_report.gd -- merge="$OUT" 2>&1 | grep -v "^Godot Engine"
