import Foundation
import Testing
@testable import NutritionKit

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct DeepSeekVisionClientTests {
    private func makeClient() -> DeepSeekVisionClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return DeepSeekVisionClient(session: URLSession(configuration: configuration))
    }

    private func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func chatResponse(_ content: [String: Any]) throws -> Data {
        let contentData = try JSONSerialization.data(withJSONObject: content)
        let contentString = String(decoding: contentData, as: UTF8.self)
        let outer: [String: Any] = [
            "choices": [
                ["message": ["content": contentString]]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: outer)
    }

    @Test
    func mealRequestAndParsing() async throws {
        let meal: [String: Any] = [
            "kind": "meal",
            "dishes": [[
                "name": "番茄炒蛋",
                "visibleIngredients": ["番茄", "鸡蛋"],
                "cookingMethod": "炒",
                "portionMinGrams": 120,
                "portionMaxGrams": 180,
                "candidateAliases": ["西红柿炒蛋"],
                "normalizedRegion": ["x": 0.1, "y": 0.2, "width": 0.4, "height": 0.3],
                "plateware": "plate20cm",
                "portionConfidence": 0.72,
                "hiddenOilLevel": "中",
                "confidence": 0.84,
                "uncertaintyNotes": ["油量不可见"]
            ]],
            "overallConfidence": 0.84,
            "analysisNote": "测试结果"
        ]
        MockURLProtocol.handler = { request in
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
            let bodyData = try #require(self.requestBody(request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["model"] as? String == "deepseek-flash")
            let thinking = body["thinking"] as? [String: Any]
            #expect(thinking?["type"] as? String == "disabled")
            let format = body["response_format"] as? [String: Any]
            #expect(format?["type"] as? String == "json_object")
            let messages = body["messages"] as? [[String: Any]]
            let content = messages?.last?["content"] as? [[String: Any]]
            #expect(content?.filter { $0["type"] as? String == "image_url" }.count == 1)
            let prompt = content?.first?["text"] as? String
            #expect(prompt?.contains("normalizedRegion") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.chatResponse(meal))
        }

        let result = try await makeClient().analyze(images: [Data([0xFF, 0xD8, 0xFF])], mode: .meal, apiKey: "sk-test")
        guard case .meal(let analyzed) = result else {
            Issue.record("Expected meal result")
            return
        }
        #expect(analyzed.dishes.first?.name == "番茄炒蛋")
        #expect(analyzed.dishes.first?.portionMinGrams == 120)
        #expect(analyzed.dishes.first?.candidateAliases == ["西红柿炒蛋"])
        #expect(analyzed.dishes.first?.normalizedRegion?.width == 0.4)
        #expect(analyzed.dishes.first?.plateware == .plate20cm)
        #expect(analyzed.dishes.first?.portionConfidence == 0.72)
    }

    @Test
    func englishLanguageUsesEnglishPrompt() async throws {
        let meal: [String: Any] = [
            "kind": "meal",
            "dishes": [[
                "name": "Tomato and egg",
                "visibleIngredients": ["Tomato", "Egg"],
                "cookingMethod": "stir-fried",
                "portionMinGrams": 120,
                "portionMaxGrams": 180,
                "hiddenOilLevel": "medium",
                "confidence": 0.84,
                "uncertaintyNotes": ["Oil amount is not visible"]
            ]],
            "overallConfidence": 0.84,
            "analysisNote": "English test"
        ]
        MockURLProtocol.handler = { request in
            let bodyData = try #require(self.requestBody(request))
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            let messages = body["messages"] as? [[String: Any]]
            let system = messages?.first?["content"] as? String
            #expect(system?.contains("strict food vision information extractor") == true)
            let content = messages?.last?["content"] as? [[String: Any]]
            let prompt = content?.first?["text"] as? String
            #expect(prompt?.contains("Dish name in English") == true)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.chatResponse(meal))
        }
        let result = try await makeClient().analyze(
            images: [Data([0xFF, 0xD8, 0xFF])],
            mode: .meal,
            apiKey: "sk-test",
            language: .english
        )
        guard case .meal(let analyzed) = result else {
            Issue.record("Expected meal result")
            return
        }
        #expect(analyzed.dishes.first?.name == "Tomato and egg")
    }

    @Test
    func packagedServingValuesAreNormalizedPer100() async throws {
        let label: [String: Any] = [
            "kind": "packagedLabel",
            "packagedLabel": [
                "brand": "测试品牌",
                "productName": "测试饮料",
                "basis": "perServing",
                "servingAmount": 250,
                "servingUnit": "ml",
                "energyKcal": 100,
                "proteinG": 5,
                "fatG": 2,
                "carbohydrateG": 15,
                "fiberG": 1,
                "sugarG": 12,
                "sodiumMg": 80,
                "confidence": 0.9,
                "notes": ["标签清晰"]
            ],
            "analysisNote": "包装标签"
        ]
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, try self.chatResponse(label))
        }

        let result = try await makeClient().analyze(images: [Data([0xFF, 0xD8, 0xFF])], mode: .packagedLabel, apiKey: "sk-test")
        guard case .packagedLabel(let packaged) = result else {
            Issue.record("Expected packaged label result")
            return
        }
        #expect(packaged.referenceUnit == .milliliter)
        #expect(packaged.productName == "测试饮料")
        let energy = packaged.nutrients.first { $0.nutrient == NutrientCatalog.energy }
        #expect(energy?.doubleValue == 40)
        #expect(energy?.status == .estimated)
    }

    @Test
    func unauthorizedKeyIsMapped() async throws {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }
        do {
            _ = try await makeClient().analyze(images: [Data([0xFF])], mode: .meal, apiKey: "bad-key")
            Issue.record("Expected unauthorized error")
        } catch DeepSeekVisionError.unauthorized {
            // Expected.
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func codeFenceIsRemovedBeforeJSONParsing() async throws {
        let rawContent = """
        ```json
        {"kind":"meal","dishes":[{"name":"米饭","visibleIngredients":[],"cookingMethod":null,"portionMinGrams":100,"portionMaxGrams":150,"hiddenOilLevel":null,"confidence":0.8,"uncertaintyNotes":[]}],"overallConfidence":0.8,"analysisNote":"ok"}
        ```
        """
        let outer: [String: Any] = ["choices": [["message": ["content": rawContent]]]]
        let data = try JSONSerialization.data(withJSONObject: outer)
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        }
        let result = try await makeClient().analyze(images: [Data([0xFF])], mode: .meal, apiKey: "sk-test")
        guard case .meal(let meal) = result else {
            Issue.record("Expected meal")
            return
        }
        #expect(meal.dishes.first?.name == "米饭")
    }
}
