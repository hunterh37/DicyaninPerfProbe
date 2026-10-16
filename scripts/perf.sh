#!/usr/bin/env bash
# Usage: perf.sh notes/perf/scenarios.json [label]   (RUNS=3 ONLY=<id> SKIP_BUILD=1 SAVE=1)
# Output: one line per scenario, median of RUNS. SAVE=1 writes notes/perf/baseline.json.
# Compares against baseline.json when present. Exit 1 on any p95 regression > 10%.
set -euo pipefail
CFG=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); LABEL=${2:-run}
ROOT=$(cd "$(dirname "$CFG")/../.." && pwd); cd "$ROOT"
OUT="$ROOT/notes/perf/runs/$LABEL"; mkdir -p "$OUT"; RUNS=${RUNS:-3}
j(){ python3 -c "import json;c=json.load(open('$CFG'));print($1)"; }
BID=$(j "c['bundleId']"); SCHEME=$(j "c['scheme']"); SIM=$(j "c.get('simName','Director-AVP')")
HZ=$(j "c.get('hz',90)"); TO=$(j "c.get('timeoutSeconds',60)")
UDID=$(xcrun simctl list devices -j | python3 -c "
import json,sys;d=json.load(sys.stdin)['devices']
print(next((x['udid'] for r,v in d.items() if 'xrOS' in r or 'visionOS' in r for x in v if x['name']=='$SIM' and x['isAvailable']),''))")
[ -n "$UDID" ] || { echo "blocked: sim $SIM missing (run vision-record-demo once)"; exit 2; }
xcrun simctl boot "$UDID" 2>/dev/null || true; xcrun simctl bootstatus "$UDID" -b >/dev/null
if [ "${SKIP_BUILD:-0}" != 1 ]; then
  [ -f project.yml ] && xcodegen -q >/dev/null
  xcodebuild -scheme "$SCHEME" -destination "id=$UDID" -configuration "$(j "c.get('config','Debug')")" \
    -derivedDataPath build/perf-dd -quiet build 2>&1 | grep -E "error:" | head -5 && exit 1 || true
  xcrun simctl install "$UDID" "$(find build/perf-dd/Build/Products -maxdepth 2 -name '*.app' | head -1)"
fi
DATA=$(xcrun simctl get_app_container "$UDID" "$BID" data)
python3 -c "
import json;c=json.load(open('$CFG'))
for s in c['scenarios']:
  a=' '.join(['-Seed',str(s.get('seed',1))]+[f'-P.{k} {v}' for k,v in s.get('params',{}).items()])
  print(s['id'],s.get('route','-'),s.get('secs',0),a,sep='\t')" | while IFS=$'\t' read -r ID ROUTE SECS ARGS; do
  [ -n "${ONLY:-}" ] && [ "$ONLY" != "$ID" ] && continue
  for i in $(seq 1 "$RUNS"); do
    rm -f "$DATA/Library/Caches/perf/$ID.json" "$DATA/Library/Caches/director/$ID".{ready,done,error}
    R=(); [ "$ROUTE" != "-" ] && R=(-Route "$ROUTE"); [ "$SECS" != 0 ] && R+=(-PerfSecs "$SECS")
    # shellcheck disable=SC2086
    xcrun simctl launch --terminate-running-process "$UDID" "$BID" "${R[@]}" -Take "$ID" \
      -Perf YES -PerfLabel "$LABEL" -PerfHz "$HZ" $ARGS >/dev/null
    n=0; until [ -f "$DATA/Library/Caches/perf/$ID.json" ]; do sleep 0.5; n=$((n+1))
      [ -f "$DATA/Library/Caches/director/$ID.error" ] && { echo "FAIL $ID $(cat "$DATA/Library/Caches/director/$ID.error")"; break 2; }
      [ $n -gt $((TO*2)) ] && { echo "FAIL $ID timeout"; break 2; }; done
    cp "$DATA/Library/Caches/perf/$ID.json" "$OUT/$ID.$i.json"
  done
done
xcrun simctl terminate "$UDID" "$BID" 2>/dev/null || true
python3 "$(dirname "$0")/summarize.py" "$OUT" "$ROOT/notes/perf/baseline.json" "${SAVE:-0}"
