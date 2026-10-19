import CoreGraphics
import Foundation
import ImageIO
import NutritionKit
import UniformTypeIdentifiers

actor DeepSeekPhotoAnalyzer: DeepSeekPhotoAnalyzing {
    private let client: DeepSeekVisionClient

    init(client: DeepSeekVisionClient = DeepSeekVisionClient()) {
        self.client = client
    }

    func testAPIKey(_ apiKey: String) async throws {
        try await client.testAPIKey(apiKey)
    }

    func analyze(images: [Data], mode: PhotoRecognitionMode, apiKey: String, language: AppLanguage) async throws -> FoodPhotoAnalysisResult {
        guard !images.isEmpty else { throw PhotoAnalysisError.invalidImage }
        for image in images.prefix(3) {
            if let issue = try Self.detectQualityIssue(in: image) {
                throw PhotoAnalysisError.imageQuality(issue)
            }
        }
        let prepared = try images.prefix(3).map { try Self.prepareJPEG($0) }
        guard !prepared.isEmpty else { throw PhotoAnalysisError.invalidImage }
        do {
            return try await client.analyze(images: prepared, mode: mode, apiKey: apiKey, language: language)
        } catch DeepSeekVisionError.invalidJSON where mode == .meal {
            let compacted = try images.prefix(3).map {
                try Self.prepareJPEG($0, maxPixelSize: 1200, compressionQuality: 0.68)
            }
            return try await client.analyze(images: compacted, mode: mode, apiKey: apiKey, language: language)
        }
    }

    func analyzeSecondPass(
        images: [Data],
        regions: [NormalizedImageRegion],
        request: PhotoSecondPassRequest,
        apiKey: String,
        language: AppLanguage
    ) async throws -> AnalyzedMeal {
        guard let first = images.first, !regions.isEmpty else { throw PhotoAnalysisError.invalidImage }
        let source = try Self.imageSource(first)
        guard let fullImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoAnalysisError.invalidImage
        }
        var croppedImages: [Data] = []
        for region in regions.prefix(3) where region.isValid {
            let rect = CGRect(
                x: region.x * Double(fullImage.width),
                y: region.y * Double(fullImage.height),
                width: region.width * Double(fullImage.width),
                height: region.height * Double(fullImage.height)
            ).integral
            guard let cropped = fullImage.cropping(to: rect) else { continue }
            croppedImages.append(try Self.encodeJPEG(cropped, compressionQuality: 0.82))
        }
        if croppedImages.isEmpty {
            croppedImages = try [first].map { try Self.prepareJPEG($0) }
        }
        let result = try await client.analyze(
            images: croppedImages,
            mode: .meal,
            apiKey: apiKey,
            language: language,
            secondPass: request
        )
        guard case .meal(let meal) = result else { throw DeepSeekVisionError.invalidResponse }
        return meal
    }

    private static func prepareJPEG(_ data: Data, maxPixelSize: Int = 1600, compressionQuality: Double = 0.82) throws -> Data {
        let source = try imageSource(data)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoAnalysisError.invalidImage
        }
        return try encodeJPEG(image, compressionQuality: compressionQuality)
    }

    private static func imageSource(_ data: Data) throws -> CGImageSource {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PhotoAnalysisError.invalidImage
        }
        return source
    }

    private static func encodeJPEG(_ image: CGImage, compressionQuality: Double) throws -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PhotoAnalysisError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: compressionQuality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoAnalysisError.invalidImage
        }
        return output as Data
    }

    private static func detectQualityIssue(in data: Data) throws -> PhotoImageQualityIssue? {
        let source = try imageSource(data)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 160
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw PhotoAnalysisError.invalidImage
        }
        let width = image.width
        let height = image.height
        guard width > 1, height > 1 else { return .subjectTooSmall }
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { throw PhotoAnalysisError.invalidImage }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let mean = pixels.reduce(0.0) { $0 + Double($1) } / Double(pixels.count) / 255
        var variance = 0.0
        var edgeEnergy = 0.0
        var edgeCount = 0.0
        for y in 0..<height {
            for x in 0..<width {
                let value = Double(pixels[y * width + x]) / 255
                variance += (value - mean) * (value - mean)
                if x + 1 < width {
                    edgeEnergy += abs(value - Double(pixels[y * width + x + 1]) / 255)
                    edgeCount += 1
                }
                if y + 1 < height {
                    edgeEnergy += abs(value - Double(pixels[(y + 1) * width + x]) / 255)
                    edgeCount += 1
                }
            }
        }
        variance /= Double(pixels.count)
        let averageEdge = edgeCount > 0 ? edgeEnergy / edgeCount : 0
        if mean < 0.12 { return .tooDark }
        if mean > 0.90 { return .tooBright }
        if variance < 0.002 { return .lowContrast }
        if averageEdge < 0.018 { return .likelyBlurry }
        if variance < 0.006 && averageEdge < 0.035 { return .subjectTooSmall }
        return nil
    }
}
