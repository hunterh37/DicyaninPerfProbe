import Foundation

/// Pure frame statistics. Unit tested headless.
public struct FrameStats: Codable, Equatable, Sendable {
    public var frames: Int
    public var fps: Double
    public var p50: Double
    public var p95: Double
    public var p99: Double
    public var max: Double
    public var hitches: Int
    public var worstAt: Double

    /// dts in ms, ts in seconds since window start, target in ms (11.1 at 90 Hz).
    public static func compute(dts: [Double], ts: [Double], target: Double) -> FrameStats {
        guard !dts.isEmpty else { return FrameStats(frames: 0, fps: 0, p50: 0, p95: 0, p99: 0, max: 0, hitches: 0, worstAt: 0) }
        let s = dts.sorted()
        func q(_ p: Double) -> Double { s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))] }
        let total = dts.reduce(0, +)
        let wi = dts.indices.max { dts[$0] < dts[$1] }!
        return FrameStats(frames: dts.count, fps: r(Double(dts.count) / (total / 1000)),
                          p50: r(q(0.5)), p95: r(q(0.95)), p99: r(q(0.99)), max: r(s.last!),
                          hitches: dts.filter { $0 > target * 1.5 }.count,
                          worstAt: r(ts.indices.contains(wi) ? ts[wi] : 0))
    }
    static func r(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}

public struct ScopeStat: Codable, Equatable, Sendable {
    public var n: Int = 0
    public var total: Double = 0
    public var max: Double = 0
    mutating func add(_ ms: Double) { n += 1; total += ms; max = Swift.max(max, ms) }
}

public struct PerfReport: Codable, Sendable {
    public var take: String
    public var label: String
    public var secs: Double
    public var frame: FrameStats
    public var scopes: [String: ScopeStat]
    public var counters: [String: Int]
    public var memMB: [Double]
}
