import Testing
@testable import NutritionKit

struct FoodSearchTests {
    @Test
    func commonChineseQueriesReturnResults() async {
        let catalog = FoodCatalog()
        let chicken = await catalog.search(query: "鸡")
        #expect(chicken.contains { $0.name == "鸡蛋" })
        #expect(chicken.contains { $0.name == "鸡胸肉" })

        let sweetPotato = await catalog.search(query: "地瓜")
        #expect(sweetPotato.first?.name == "红薯")

        let latte = await catalog.search(query: "拿铁")
        #expect(latte.first?.name == "拿铁咖啡")
    }

    @Test
    func unknownQueryReturnsNoResultsAndEmptyQueryReturnsCatalog() async {
        let catalog = FoodCatalog()
        let unknown = await catalog.search(query: "银河宇宙")
        #expect(unknown.isEmpty)
        let all = await catalog.search(query: "", limit: 200)
        #expect(all.count == 121)
    }

    @Test
    func rapidLatestQueryCanBeRepresentedIndependently() async {
        let catalog = FoodCatalog()
        let first = await catalog.search(query: "鸡")
        let second = await catalog.search(query: "拿铁")
        #expect(first.first?.name != second.first?.name)
        #expect(second.first?.name == "拿铁咖啡")
    }
}
