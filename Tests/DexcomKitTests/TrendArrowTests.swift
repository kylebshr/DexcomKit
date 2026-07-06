import Testing

@testable import DexcomKit

@Suite struct TrendArrowTests {
    @Test func nilRateHasNoArrow() {
        #expect(TrendArrow(rate: nil) == nil)
    }

    @Test(arguments: [
        (rate: -3.5, arrow: TrendArrow.fallingQuickly),
        (rate: -3.0, arrow: .falling),
        (rate: -2.5, arrow: .falling),
        (rate: -2.0, arrow: .fallingSlightly),
        (rate: -1.5, arrow: .fallingSlightly),
        (rate: -1.0, arrow: .steady),
        (rate: 0.0, arrow: .steady),
        (rate: 0.9, arrow: .steady),
        (rate: 1.0, arrow: .risingSlightly),
        (rate: 1.9, arrow: .risingSlightly),
        (rate: 2.0, arrow: .rising),
        (rate: 2.9, arrow: .rising),
        (rate: 3.0, arrow: .risingQuickly),
        (rate: 4.2, arrow: .risingQuickly),
    ])
    func bucketsRates(_ testCase: (rate: Double, arrow: TrendArrow)) {
        #expect(TrendArrow(rate: testCase.rate) == testCase.arrow)
    }
}
