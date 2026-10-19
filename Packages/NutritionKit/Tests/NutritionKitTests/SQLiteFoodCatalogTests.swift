import Foundation
import Testing
@testable import NutritionKit

struct SQLiteFoodCatalogTests {
    @Test
    func bundledCatalogSearchesSimplifiedChinese() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let empty = await catalog.searchResults(query: "", limit: 5)
        #expect(!empty.isEmpty)
        let egg = await catalog.food(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        #expect(egg?.name == "鸡蛋")
        let chicken = await catalog.searchResults(query: "鸡", limit: 10)
        #expect(!chicken.isEmpty)
        #expect(chicken.contains { $0.food.name == "鸡蛋" })
        let latte = await catalog.searchResults(query: "拿铁", limit: 10)
        #expect(latte.contains { $0.food.name == "拿铁咖啡" })
        let matcher = PhotoFoodMatcher(catalog: catalog)
        let dish = AnalyzedDish(name: "流心芝士拿铁（冰，无焦糖）", visibleIngredients: ["牛奶", "咖啡"], portionMinGrams: 250, portionMaxGrams: 350, confidence: 0.8)
        let matches = await matcher.candidates(for: dish)
        #expect(matches.first?.food.name == "拿铁咖啡")
    }

    @Test
    func bundledManifestHasRequiredSources() throws {
        let manifest = try #require(CatalogManifest.bundled())
        #expect(manifest.recordCount > 10_000)
        #expect(manifest.database.bytes > 1_000_000)
        #expect(manifest.sources.contains { $0.name == "usda_foundation" })
    }
}

struct CatalogPerformanceTests {
    @Test
    func broadChineseSearchIsBoundedAndCompletesQuickly() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let clock = ContinuousClock()
        let start = clock.now
        let results = await catalog.searchResults(query: "鸡", limit: 500)
        let elapsed = start.duration(to: clock.now)
        #expect(results.count <= SQLiteFoodCatalog.maximumCandidateCount)
        #expect(elapsed < .seconds(2))
        let wideResults = await catalog.searchResults(query: "营养", limit: 500)
        #expect(wideResults.count <= SQLiteFoodCatalog.maximumCandidateCount)
    }
}
