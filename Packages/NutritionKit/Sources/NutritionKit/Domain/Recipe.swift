import Foundation

public struct RecipeIngredient: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let food: FoodItem
    public let quantity: FoodQuantity

    public init(id: UUID = UUID(), food: FoodItem, quantity: FoodQuantity) {
        self.id = id
        self.food = food
        self.quantity = quantity
    }
}

public struct Recipe: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var servings: Decimal
    public var finalYieldGrams: Decimal?
    public var ingredients: [RecipeIngredient]
    public var source: MeasurementSource

    public init(id: UUID = UUID(), name: String, servings: Decimal = 1, finalYieldGrams: Decimal? = nil, ingredients: [RecipeIngredient], source: MeasurementSource = .recipe) {
        self.id = id
        self.name = name
        self.servings = servings
        self.finalYieldGrams = finalYieldGrams
        self.ingredients = ingredients
        self.source = source
    }
}
