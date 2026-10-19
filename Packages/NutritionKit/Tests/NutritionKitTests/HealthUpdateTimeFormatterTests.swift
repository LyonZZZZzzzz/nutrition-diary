import Foundation
import Testing
@testable import NutritionKit

struct HealthUpdateTimeFormatterTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func underOneMinuteShowsZeroMinutes() {
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(11)) == "更新于 0 分钟前")
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(59)) == "更新于 0 分钟前")
    }

    @Test
    func underOneHourShowsMinutesOnly() {
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(60)) == "更新于 1 分钟前")
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(3_599)) == "更新于 59 分钟前")
    }

    @Test
    func oneHourOrMoreShowsHoursAndMinutes() {
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(3_600)) == "更新于 1 小时 0 分钟前")
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(3_661)) == "更新于 1 小时 1 分钟前")
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(7_320)) == "更新于 2 小时 2 分钟前")
    }

    @Test
    func futureDateClampsToZeroMinutes() {
        #expect(HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(-30)) == "更新于 0 分钟前")
    }

    @Test
    func outputNeverContainsSeconds() {
        for interval in [0.0, 11.0, 59.0, 60.0, 3_600.0] {
            let text = HealthUpdateTimeFormatter.text(from: base, now: base.addingTimeInterval(interval))
            #expect(!text.contains("秒"))
        }
    }
}
