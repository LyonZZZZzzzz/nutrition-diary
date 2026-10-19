import Foundation
import NutritionKit

struct AppVersion: Equatable, Sendable {
    let version: String
    let build: String

    static var current: AppVersion {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return AppVersion(
            version: version.isEmpty ? "未知" : version,
            build: build.isEmpty ? "未知" : build
        )
    }

    var displayText: String { displayText(for: .simplifiedChinese) }

    func displayText(for language: AppLanguage) -> String {
        let unknown = language.isChinese ? "未知" : "Unknown"
        if version == "未知" && build == "未知" { return unknown }
        if build == "未知" { return version }
        if version == "未知" { return language.isChinese ? "构建 \(build)" : "Build \(build)" }
        return "\(version) (\(build))"
    }
}
