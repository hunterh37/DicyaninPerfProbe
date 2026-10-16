import XCTest
@testable import DicyaninPerfProbe

final class StatsTests: XCTestCase {
    func testSteady90() {
        let s = FrameStats.compute(dts: Array(repeating: 11.1, count: 90), ts: (0..<90).map { Double($0) / 90 }, target: 11.1)
        XCTAssertEqual(s.fps, 90.1, accuracy: 0.2); XCTAssertEqual(s.hitches, 0); XCTAssertEqual(s.p95, 11.1)
    }
    func testHitch() {
        var d = Array(repeating: 11.1, count: 99); d.insert(80, at: 50)
        let s = FrameStats.compute(dts: d, ts: (0..<100).map(Double.init), target: 11.1)
        XCTAssertEqual(s.hitches, 1); XCTAssertEqual(s.max, 80); XCTAssertEqual(s.worstAt, 50)
    }
    func testEmpty() { XCTAssertEqual(FrameStats.compute(dts: [], ts: [], target: 11.1).frames, 0) }
}
