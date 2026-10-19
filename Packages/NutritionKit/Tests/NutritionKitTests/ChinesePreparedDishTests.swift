import Foundation
import Testing
@testable import NutritionKit

struct ChinesePreparedDishTests {
    @Test
    func bundledPreparedDishesAreSearchableByChineseAliasAndPinyin() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())

        let yuXiang = await catalog.searchResults(query: "鱼香肉丝", limit: 10)
        #expect(yuXiang.first?.food.nameZh == "鱼香肉丝")
        #expect(yuXiang.first?.matchReason == .displayName)

        let tomatoEgg = await catalog.searchResults(query: "西红柿炒鸡蛋", limit: 10)
        #expect(tomatoEgg.first?.food.nameZh == "番茄炒蛋")
        #expect(tomatoEgg.first?.matchReason == .alias)

        let kungPaoPinyin = await catalog.searchResults(query: "gongbaojiding", limit: 10)
        #expect(kungPaoPinyin.first?.food.nameZh == "宫保鸡丁")
        #expect(kungPaoPinyin.first?.matchReason == .pinyin)

        let sweetPotato = await catalog.searchResults(query: "地瓜", limit: 10)
        #expect(sweetPotato.first?.food.nameZh == "红薯")
        #expect(sweetPotato.first?.matchReason == .alias)
    }

    @Test
    func preparedDishBenchmarkMeetsTopOneAndTopThreeTargets() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let foods = await catalog.search(query: "", limit: 20_000, language: .simplifiedChinese)
        let prepared = foods.filter { $0.preparationState == .prepared }
        #expect(prepared.count >= 120)

        var queries: [(String, UUID)] = []
        for food in prepared {
            queries.append((food.nameZh ?? food.name, food.id))
            for pinyin in food.pinyin ?? [] { queries.append((pinyin, food.id)) }
        }
        #expect(queries.count >= 200)

        var topOne = 0
        var topThree = 0
        for (query, expectedID) in queries {
            let results = await catalog.searchResults(query: query, limit: 5, language: .simplifiedChinese)
            if results.first?.food.id == expectedID { topOne += 1 }
            if results.prefix(3).contains(where: { $0.food.id == expectedID }) { topThree += 1 }
        }
        let count = Double(max(queries.count, 1))
        #expect(Double(topOne) / count >= 0.85)
        #expect(Double(topThree) / count >= 0.95)
    }

    @Test
    func preparedFoodAlwaysKeepsCoreNutritionStateExplicit() async throws {
        let catalog = try #require(SQLiteFoodCatalog.bundled())
        let results = await catalog.searchResults(query: "宫保鸡丁", limit: 5)
        let food = try #require(results.first?.food)
        let byID = Dictionary(uniqueKeysWithValues: food.nutrients.map { ($0.nutrient, $0) })
        for nutrient in NutrientCatalog.core {
            let measurement = try #require(byID[nutrient])
            if measurement.value == nil {
                #expect(measurement.status == .missing)
            } else {
                #expect(measurement.status == .complete || measurement.status == .estimated)
            }
        }
    }
}
