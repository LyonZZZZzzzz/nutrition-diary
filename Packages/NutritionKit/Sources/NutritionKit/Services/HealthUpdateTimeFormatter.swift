import Foundation

public enum HealthUpdateTimeFormatter {
    public static func text(
        from date: Date,
        now: Date = .now,
        language: AppLanguage = .simplifiedChinese
    ) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let totalMinutes = seconds / 60
        if language == .english {
            if totalMinutes < 60 {
                return "Updated \(totalMinutes) min ago"
            }
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return "Updated \(hours) hr \(minutes) min ago"
        }
        if totalMinutes < 60 {
            return "更新于 \(totalMinutes) 分钟前"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return "更新于 \(hours) 小时 \(minutes) 分钟前"
    }
}
