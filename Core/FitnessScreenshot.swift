import Foundation

struct FitnessScreenshotReading: Equatable, Sendable {
    let active: Int?
    let total: Int?
    let isWorkoutDetail: Bool
}

enum FitnessScreenshotParser {
    private static let number = #"(?<![\d.,，/−-])(\d+(?:[ ,，]\d{3})*)"#
    private static let units = #"(?:千卡|大卡|卡路里|kcal\b|cal(?:ories)?\b)"#
    private static let move = #"(?:活动|活動|移动|移動|\bmove\b)"#
    private static let workout = #"体能训练详情|體能訓練詳情|训练时长|訓練時長|平均心率|\bworkout details\b|\b(avg\.?|average)\s+heart rate\b"#
    private static let totalLabel = #"(?:全天(?:总|總)?消耗|总消耗|總消耗|总共|總共|总计|總計|合计|合計|\btotal(?:\s+energy)?\b)"#
    private static let activeLabel = #"(?:活动能量|活動能量|活动消耗|活動消耗|移动能量|移動能量|活动|活動|移动|移動|\bactive(?:\s+energy)?\b|\bmove\b)"#

    static func parse(_ lines: [String]) -> FitnessScreenshotReading {
        let text = lines.map { $0.folding(options: .widthInsensitive, locale: nil).trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"(?<=\p{Han})[ \t]+(?=\p{Han})"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[ \t]*,[ \t]*"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[ \t]+(?=\d)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)[ \t]*[干于]卡"#, with: " 千卡", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)^([ \t]*)忠共(?=[ \t]*:?[ \t]*\d)"#, with: "$1总共", options: .regularExpression)
        if text.range(of: workout, options: [.caseInsensitive, .regularExpression]) != nil {
            return FitnessScreenshotReading(active: nil, total: nil, isWorkoutDetail: true)
        }

        let markedActive = values(in: text, matching: activeLabel + #"\s*[:：]?\s*"# + number + #"\s*"# + units)
        let hasMove = text.range(of: move, options: [.caseInsensitive, .regularExpression]) != nil
        let ringValues = hasMove
            ? values(in: text, matching: number + #"\s*/\s*\d+(?:[ ,，]\d{3})*\s*"# + units)
            : []
        let active = unique(markedActive.union(ringValues))
        let totalValues = values(in: text, matching: totalLabel + #"\s*[:：]?\s*"# + number + #"\s*"# + units)
        let total = unique(totalValues).flatMap { $0 >= (active ?? 0) ? $0 : nil }
        return FitnessScreenshotReading(active: active, total: total, isWorkoutDetail: false)
    }

    private static func values(in text: String, matching pattern: String) -> Set<Int> {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return Set(matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text),
                  let value = Int(text[range].filter(\.isNumber)),
                  (0...Journal.maxDailyEnergy).contains(value) else { return nil }
            return value
        })
    }

    private static func unique(_ values: Set<Int>) -> Int? {
        values.count == 1 ? values.first : nil
    }
}
