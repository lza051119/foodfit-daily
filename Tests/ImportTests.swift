import Foundation
import XCTest
@testable import FoodFitCore

final class ImportTests: XCTestCase {
    func testFitnessRingAnatomyAndThousandsSeparators() {
        XCTAssertEqual(FitnessScreenshotParser.parse(["活动", "４３２／５００ 千卡", "总共 ２，０１３ 千卡", "锻炼", "26/30 分钟"]),
                       FitnessScreenshotReading(active: 432, total: 2_013, isWorkoutDetail: false))
        XCTAssertEqual(FitnessScreenshotParser.parse(["Move", "684/550 CAL", "TOTAL 2,284 CAL", "Exercise 21/30 MIN"]),
                       FitnessScreenshotReading(active: 684, total: 2_284, isWorkoutDetail: false))
        XCTAssertEqual(FitnessScreenshotParser.parse(["活 动", "540 / 500 干 卡", "总 共 2 ， 1 1 0 干 卡"]),
                       FitnessScreenshotReading(active: 540, total: 2_110, isWorkoutDetail: false))
        XCTAssertEqual(FitnessScreenshotParser.parse(["活动", "540 / 500 于 卡", "忠 共 2,110 于 卡"]),
                       FitnessScreenshotReading(active: 540, total: 2_110, isWorkoutDetail: false))
    }

    func testUncertainScreenshotValuesRemainBlank() {
        XCTAssertEqual(FitnessScreenshotParser.parse(["Workout Details", "Move 84 CAL", "Total 102 CAL", "Avg. Heart Rate"]),
                       FitnessScreenshotReading(active: nil, total: nil, isWorkoutDetail: true))
        XCTAssertEqual(FitnessScreenshotParser.parse(["MOVE", "255/500 CAL", "TOTAL 2,201 CAL", "TOTAL 2,450 CAL"]),
                       FitnessScreenshotReading(active: 255, total: nil, isWorkoutDetail: false))
        XCTAssertEqual(FitnessScreenshotParser.parse(["400/500 CAL", "一行文字"]),
                       FitnessScreenshotReading(active: nil, total: nil, isWorkoutDetail: false))
        XCTAssertEqual(FitnessScreenshotParser.parse(["活动", "355.2/500 CAL", "TOTAL -100 CAL"]),
                       FitnessScreenshotReading(active: nil, total: nil, isWorkoutDetail: false))
    }

    func testDeepSeekRequestIncludesPromptDescriptionAndImage() throws {
        let image = Data([0xFF, 0xD8, 0xFF, 0xD9])
        let request = try DeepSeekRequest.make(key: "example-token", notes: "米饭半碗", photo: image)
        XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer example-token")
        let raw = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("example-token"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "deepseek-flash")
        XCTAssertEqual(body["response_format"] as? [String: String], ["type": "json_object"])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertTrue((messages[0]["content"] as? String)?.contains("kcal") == true)
        let content = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(content[0]["text"] as? String, "米饭半碗")
        XCTAssertEqual(content[1]["image_url"] as? [String: String],
                       ["url": "data:image/jpeg;base64,\(image.base64EncodedString())"])
    }

    func testDeepSeekCanEstimateWithTextAloneAndMapsErrors() throws {
        let request = try DeepSeekRequest.make(key: "example-token", notes: "牛奶一杯", photo: nil)
        let raw = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(decoding: raw, as: UTF8.self).contains("image_url"))
        XCTAssertThrowsError(try DeepSeekRequest.make(key: " ", notes: "牛奶", photo: nil)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .noKey)
        }
        XCTAssertThrowsError(try DeepSeekRequest.make(key: "example-token", notes: " ", photo: nil)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .noInput)
        }
        XCTAssertThrowsError(try DeepSeekRequest.decode(Data(), status: 429)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .rateLimited)
        }
    }

    func testDeepSeekSendsPrimaryAndReferencePhotosInOrder() throws {
        let primary = Data([1])
        let references = [Data([2]), Data([3])]
        let request = try DeepSeekRequest.make(key: "example-token", notes: "鸡腿饭", photo: primary,
                                              referencePhotos: references)
        let raw = try XCTUnwrap(request.httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(content.compactMap { $0["type"] as? String },
                       ["text", "image_url", "text", "image_url", "image_url"])
        XCTAssertEqual(content.compactMap { $0["text"] as? String },
                       ["鸡腿饭", "前一张是主图，以下是同一餐的辅助图。"])
        XCTAssertEqual(content.compactMap { ($0["image_url"] as? [String: String])?["url"] },
                       ([primary] + references).map { "data:image/jpeg;base64,\($0.base64EncodedString())" })

        let referenceOnly = try DeepSeekRequest.make(key: "example-token", notes: "", photo: nil,
                                                    referencePhotos: references)
        XCTAssertTrue(String(decoding: try XCTUnwrap(referenceOnly.httpBody), as: UTF8.self)
            .contains("这次只有同一餐的辅助图。"))
        XCTAssertThrowsError(try DeepSeekRequest.make(key: "example-token", notes: "", photo: primary,
                                                     referencePhotos: Array(repeating: references[0], count: 600))) {
            XCTAssertEqual($0 as? DeepSeekIssue, .imageLimit)
        }
    }

    func testDeepSeekAcceptsOnlyCoherentEstimates() throws {
        let content = #"{"status":"ok","name":"鸡腿饭","kcal":620,"low":500,"high":760,"assumptions":"米饭一碗，酱料未称重。"}"#
        let estimate = try DeepSeekRequest.decode(response(content), status: 200)
        XCTAssertEqual(estimate, CalorieEstimate(name: "鸡腿饭", kcal: 620, low: 500, high: 760,
                                                 assumptions: "米饭一碗，酱料未称重。"))
        XCTAssertThrowsError(try DeepSeekRequest.decode(response(content.replacingOccurrences(of: "500", with: "700")), status: 200)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .invalidResponse)
        }
        XCTAssertThrowsError(try DeepSeekRequest.decode(response("   "), status: 200)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .invalidResponse)
        }
        XCTAssertThrowsError(try DeepSeekRequest.decode(response(content, finish: "length"), status: 200)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .truncatedResponse)
        }
        XCTAssertThrowsError(try DeepSeekRequest.decode(response(#"{"status":"uncertain"}"#), status: 200)) {
            XCTAssertEqual($0 as? DeepSeekIssue, .insufficientInformation)
        }
    }

    func testDeepSeekSeparatesProviderErrors() throws {
        for (status, expected) in [(400, DeepSeekIssue.rejectedRequest), (401, .rejectedKey),
                                   (402, .quota), (504, .timedOut), (503, .unavailable)] {
            XCTAssertThrowsError(try DeepSeekRequest.decode(Data(), status: status)) {
                XCTAssertEqual($0 as? DeepSeekIssue, expected)
            }
        }
        XCTAssertTrue(DeepSeekRequest.estimatePrompt.contains("自助烤肉"))
        XCTAssertEqual(try DeepSeekRequest.decodeRecap(response(#"{"recap":"已记录晚餐和力量组次。"}"#), status: 200),
                       "已记录晚餐和力量组次。")
    }

    private func response(_ content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }
}
