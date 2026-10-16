# DicyaninPerfProbe

DEBUG frame and scope probe for visionOS apps, driven headless by DicyaninStageDirector routes.
Agent output is one line per scenario.

## Install (XcodeGen)

```yaml
packages:
  DicyaninPerfProbe:
    url: https://github.com/hunterh37/DicyaninPerfProbe.git
    from: 0.1.0
```

## App wiring

```swift
#if DEBUG
import DicyaninPerfProbe
#endif

// App.init or root .onAppear
#if DEBUG
PerfProbe.shared.start()
#endif

// hot paths (one branch when inactive)
PerfProbe.shared.measure("AISystem") { updateAI() }
PerfProbe.shared.count("entities", root.children.count)

// RealityKit games: feed real sim dt instead of the display link
PerfProbe.shared.frame(dt: event.deltaTime)
```

Inactive unless launched with `-Perf YES`. Window is the director take (`ready` to `done`), or `-PerfSecs N`.

## Scenarios: notes/perf/scenarios.json

```json
{ "bundleId": "org.dicyaninlabs.app", "scheme": "App", "hz": 90,
  "scenarios": [
    { "id": "idle", "secs": 10 },
    { "id": "walk", "route": "game/walk-loop", "seed": 7 },
    { "id": "kill10", "route": "game/kill", "params": { "count": 10 } } ] }
```

Routes own the scripted motion (`take.ready()` after warmup, `take.done()` after the fixed duration).

## Run

```
scripts/perf.sh notes/perf/scenarios.json before SAVE=1   # baseline
scripts/perf.sh notes/perf/scenarios.json after           # compare, exit 1 on p95 > +10%
```

```
walk  fps  71.2 p95  18.4 p99  31.0 max  88.2 hitch   41 memΔ  12.0 | p95 +38% fps -9.1 hitch +22 REGRESS | AISystem=4.1ms/f
```

Files: `notes/perf/runs/<label>/<id>.<n>.json`, `summary.json`, `notes/perf/baseline.json`.
Simulator numbers rank work. Device numbers decide FPS claims.
