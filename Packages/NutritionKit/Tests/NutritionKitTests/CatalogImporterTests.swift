import Foundation
import Testing
@testable import NutritionKit

struct CatalogImporterTests {
    @Test
    func importsCoreAndExtendedNutrients() throws {
        let csv = """
        name,aliases,category,referenceUnit,energy_kcal,protein_g,fat_g,carbohydrate_g,fiber_g,sugar_g,sodium_mg,calcium_mg
        测试食物,别名1|别名2,测试,g,120,5,3,20,2,4,80,100
        """
        let preview = try CSVFoodCatalogImporter().previewCSV(Data(csv.utf8))
        #expect(preview.canCommit)
        #expect(preview.foods.first?.name == "测试食物")
        #expect(preview.foods.first?.nutrients.first { $0.nutrient == NutrientCatalog.calcium }?.doubleValue == 100)
    }

    @Test
    func reportsUnknownColumnsAndInvalidValues() throws {
        let csv = """
        name,energy_kcal,mystery_column
        bad,-5,1
        """
        let preview = try CSVFoodCatalogImporter().previewCSV(Data(csv.utf8))
        #expect(!preview.canCommit)
        #expect(preview.unknownColumns == ["mystery_column"])
        #expect(!preview.issues.isEmpty)
    }
}
