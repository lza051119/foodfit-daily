import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

enum ImageTools {
    static func prepare(_ original: Data, maxPixels: Int) throws -> Data {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ImageIssue.unreadable
        }

        // Encode the oriented pixels into a new file without copying the photo's metadata.
        let jpeg = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ImageIssue.unreadable
        }
        let quality = [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        CGImageDestinationAddImage(writer, image, quality)
        guard CGImageDestinationFinalize(writer) else { throw ImageIssue.unreadable }
        return jpeg as Data
    }

    static func readFitnessScreenshot(_ image: Data) throws -> FitnessScreenshotReading {
        let preferred = try recognizedFitness(image, correctLabels: true)
        if preferred.isWorkoutDetail || (preferred.active != nil && preferred.total != nil) { return preferred }
        guard let alternate = try? recognizedFitness(image, correctLabels: false) else { return preferred }
        if alternate.isWorkoutDetail { return alternate }
        let active = reconcile(preferred.active, alternate.active)
        let total = reconcile(preferred.total, alternate.total).flatMap { $0 >= (active ?? 0) ? $0 : nil }
        return FitnessScreenshotReading(active: active, total: total, isWorkoutDetail: false)
    }

    private static func recognizedFitness(_ image: Data, correctLabels: Bool) throws -> FitnessScreenshotReading {
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = correctLabels
        if correctLabels {
            request.customWords = ["活动", "活動", "总共", "總共", "总消耗", "千卡", "MOVE", "TOTAL", "KCAL"]
        }
        let available = try request.supportedRecognitionLanguages()
        let languages = ["zh-Hans", "zh-Hant", "en-US"].filter { available.contains($0) }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        try VNImageRequestHandler(data: image).perform([request])
        let items = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var rows: [[VNRecognizedTextObservation]] = []
        for item in items {
            if let last = rows.last?.first,
               abs(last.boundingBox.midY - item.boundingBox.midY) <= max(last.boundingBox.height, item.boundingBox.height) / 2 {
                rows[rows.count - 1].append(item)
            } else {
                rows.append([item])
            }
        }
        let lines = rows.map { row in
            row.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
        }
        return FitnessScreenshotParser.parse(lines)
    }

    private static func reconcile(_ first: Int?, _ second: Int?) -> Int? {
        if let first, let second, first != second { return nil }
        return first ?? second
    }
}

enum ImageIssue: LocalizedError {
    case unreadable

    var errorDescription: String? { "无法读取这张图片，请换一张重试。" }
}
