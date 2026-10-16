import Foundation
import QuartzCore
import os

/// DEBUG-only frame/scope probe. Active only with launch arg `-Perf YES`.
///
///   -Perf YES          enable
///   -PerfLabel before  label stored in the report
///   -PerfHz 90         target refresh (default 90)
///
/// Window: starts when DicyaninStageDirector writes <take>.ready, stops at <take>.done
/// (or `-PerfSecs N` after launch when no director take). Report: <Caches>/perf/<take>.json
@MainActor
public final class PerfProbe {
    public static let shared = PerfProbe()

    public let enabled: Bool
    let label: String, targetMs: Double, fixedSecs: Double?, take: String
    let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "app", category: "perf")
    var dts: [Double] = [], ts: [Double] = []
    var scopes: [String: ScopeStat] = [:]
    public var counters: [String: Int] = [:]
    var mem: [Double] = []
    var link: AnyObject?
    var last: CFTimeInterval = 0, t0: CFTimeInterval = 0
    var recording = false, finished = false

    init(args: [String] = ProcessInfo.processInfo.arguments) {
        func v(_ k: String) -> String? { args.firstIndex(of: k).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        enabled = v("-Perf") == "YES"
        label = v("-PerfLabel") ?? "run"
        targetMs = 1000 / (Double(v("-PerfHz") ?? "") ?? 90)
        fixedSecs = Double(v("-PerfSecs") ?? "")
        take = v("-Take") ?? v("-Route")?.replacingOccurrences(of: "/", with: "-") ?? "launch"
    }

    /// Call once at app start (e.g. in App.init or root .onAppear).
    public func start() {
        guard enabled, link == nil else { return }
        #if !os(macOS)
        let l = CADisplayLink(target: Tick(self), selector: #selector(Tick.fire(_:)))
        l.add(to: .main, forMode: .common); link = l
        #endif
        if let s = fixedSecs { begin(); DispatchQueue.main.asyncAfter(deadline: .now() + s) { self.end() } }
        else { Task { await self.followDirector() } }
    }

    /// Feed a RealityKit SceneEvents.Update deltaTime (seconds) instead of the display link.
    public func frame(dt: Double) { if recording { record(dt * 1000) } }

    /// Time a hot path. Costs one branch when disabled.
    @discardableResult
    public func measure<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        guard recording else { return try body() }
        let st = signposter.beginInterval(name)
        let c = ContinuousClock.now
        defer {
            let d = ContinuousClock.now - c
            scopes["\(name)", default: ScopeStat()].add(Double(d.components.attoseconds) / 1e15 + Double(d.components.seconds) * 1000)
            signposter.endInterval(name, st)
        }
        return try body()
    }

    public func count(_ name: String, _ v: Int) { if recording { counters[name] = max(counters[name] ?? 0, v) } }

    func tick(_ ts: CFTimeInterval) {
        defer { last = ts }
        guard recording, last > 0 else { return }
        record((ts - last) * 1000)
    }

    func record(_ ms: Double) { dts.append(ms); ts.append(CACurrentMediaTime() - t0) }

    func begin() { dts = []; ts = []; scopes = [:]; t0 = CACurrentMediaTime(); last = 0; mem = [Self.footprintMB()]; recording = true }

    func end() {
        guard recording, !finished else { return }
        recording = false; finished = true; mem.append(Self.footprintMB())
        let rep = PerfReport(take: take, label: label, secs: FrameStats.r(CACurrentMediaTime() - t0),
                             frame: .compute(dts: dts, ts: ts, target: targetMs),
                             scopes: scopes, counters: counters, memMB: mem)
        let dir = Self.caches.appendingPathComponent("perf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        try? enc.encode(rep).write(to: dir.appendingPathComponent("\(take).json"))
        print("PERF|\(take)|fps \(rep.frame.fps)|p95 \(rep.frame.p95)|hitch \(rep.frame.hitches)")
    }

    func followDirector() async {
        let d = Self.caches.appendingPathComponent("director")
        func has(_ k: String) -> Bool { FileManager.default.fileExists(atPath: d.appendingPathComponent("\(take).\(k)").path) }
        while !has("ready") && !has("error") { try? await Task.sleep(for: .milliseconds(50)) }
        guard has("ready") else { return }
        begin()
        while !has("done") && !has("error") { try? await Task.sleep(for: .milliseconds(50)) }
        end()
    }

    static var caches: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0] }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var n = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &n) }
        }
        return kr == KERN_SUCCESS ? FrameStats.r(Double(info.phys_footprint) / 1_048_576) : 0
    }
}

/// NSObject trampoline so PerfProbe stays a plain class.
final class Tick: NSObject {
    weak var probe: PerfProbe?
    init(_ p: PerfProbe) { probe = p }
    @MainActor @objc func fire(_ l: CADisplayLink) { probe?.tick(l.timestamp) }
}
