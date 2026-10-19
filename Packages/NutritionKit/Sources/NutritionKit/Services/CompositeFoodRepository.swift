import Foundation

public protocol CompositeFoodRepository: Sendable {
    func saveComposite(_ composite: CompositeFoodDefinition) async throws
    func allComposites() async throws -> [CompositeFoodDefinition]
}

extension DiaryStore: CompositeFoodRepository {}
