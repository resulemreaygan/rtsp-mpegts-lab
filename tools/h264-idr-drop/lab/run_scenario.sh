#!/usr/bin/env bash
# Runs one scenario: upstream MediaMTX + MediaMTX under test + publisher, then
# counts DTS errors in the log of the node under test.
#
# usage: run_scenario.sh NAME MEDIAMTX_BIN DURATION [publish options...]
# example: run_scenario.sh orig-drop3 /tmp/mediamtx-orig 60s -drop-idr-every 3
set -uo pipefail

NAME="$1"
TEST_BIN="$2"
DURATION="$3"
shift 3

DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_BIN="${SOURCE_BIN:-$TEST_BIN}"
TOOL="${TOOL:-$DIR/../h264-idr-drop}"
INPUT="${INPUT:-/tmp/h264-idr-drop-work/sim.h264}"
OUT="${OUT_DIR:-/tmp/h264-idr-drop-runs}/$NAME"

rm -rf "$OUT" /tmp/h264-idr-drop-rec
mkdir -p "$OUT"

cleanup() {
  kill "${PIDS[@]}" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT
PIDS=()

"$SOURCE_BIN" "$DIR/source.yml" >"$OUT/source.log" 2>&1 &
PIDS+=($!)
sleep 1

"$TEST_BIN" "$DIR/test.yml" >"$OUT/test.log" 2>&1 &
PIDS+=($!)
sleep 1

"$TOOL" publish -in "$INPUT" -url rtsp://localhost:8554/upstream -duration "$DURATION" "$@" \
  >"$OUT/publish.log" 2>&1

sleep 2

crashes=$(grep -c "muxer instance crashed" "$OUT/test.log")
recorder=$(grep -cE "\[recorder\].*(too many reordered|DTS)" "$OUT/test.log")
dropped=$(grep -c "dropping IDR" "$OUT/publish.log")
segments=$(find /tmp/h264-idr-drop-rec -type f 2>/dev/null | wc -l)

printf "%-28s droppedIDR=%-4s hlsCrashes=%-4s recorderErrors=%-4s recordSegments=%s\n" \
  "$NAME" "$dropped" "$crashes" "$recorder" "$segments" | tee "$OUT/summary.txt"
grep -oE "(too many reordered frames \([0-9]+\)|DTS is not monotonically increasing|DTS is greater than PTS)" \
  "$OUT/test.log" | sort | uniq -c | sed "s/^/    /" | tee -a "$OUT/summary.txt" || true
