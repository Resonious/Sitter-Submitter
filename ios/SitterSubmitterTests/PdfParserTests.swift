import Foundation
import Testing
@testable import SitterSubmitter

struct PdfParserTests {
    /// A Responses API reply from a reasoning model: a reasoning item, then the message.
    private static func reply(_ text: String) -> Data {
        let body: [String: Any] = [
            "id": "resp_123",
            "object": "response",
            "status": "completed",
            "model": PdfParser.model,
            "output": [
                ["id": "rs_1", "type": "reasoning", "summary": [Any]()],
                [
                    "id": "msg_1", "type": "message", "role": "assistant", "status": "completed",
                    "content": [["type": "output_text", "text": text, "annotations": [Any]()]],
                ],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private static func parser(status: Int = 200, body: Data) -> PdfParser {
        PdfParser(apiKey: "sk-test") { request in
            (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }

    private static let entriesJSON = """
        {"entries":[\
        {"date":"2025/11/07","startTime":"09:30","endTime":"15:00","sitterName":"高野 あみい","childName":"杏","amount":14300},\
        {"date":"2025/11/12","startTime":"10:00","endTime":"13:00","sitterName":"早川明日香","childName":"杏","amount":7800}\
        ]}
        """

    @Test func sendsThePdfToTheResponsesAPI() throws {
        let pdf = Data("%PDF-1.4 receipt".utf8)

        let request = try PdfParser(apiKey: "sk-test").makeRequest(pdfData: pdf)

        #expect(request.url == URL(string: "https://api.openai.com/v1/responses"))
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.timeoutInterval == 120)

        let httpBody = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: httpBody) as? [String: Any])
        #expect(Set(body.keys) == ["model", "input"])
        #expect(body["model"] as? String == "gpt-6.1-sol")
        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input.count == 1)
        #expect(input.first?["role"] as? String == "user")
        let content = try #require(input.first?["content"] as? [[String: Any]])
        #expect(content.count == 2)
        #expect(content[0] as? [String: String] == ["type": "input_text", "text": PdfParser.prompt])
        #expect(content[1] as? [String: String] == [
            "type": "input_file",
            "filename": "receipt.pdf",
            "file_data": "data:application/pdf;base64,\(pdf.base64EncodedString())",
        ])
    }

    @Test func usesTheSamePromptAndModelAsTheAndroidApp() throws {
        let kotlin = try String(contentsOf: TestPaths.androidPdfParser, encoding: .utf8)
        let start = try #require(kotlin.range(of: "val prompt = \"\"\""))
        let end = try #require(kotlin.range(of: "\"\"\".trim()", range: start.upperBound..<kotlin.endIndex))

        #expect(kotlin[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines) == PdfParser.prompt)
        #expect(kotlin.contains(#"addProperty("model", "\#(PdfParser.model)")"#))
    }

    @Test func readsTheSessionsFromTheReply() async throws {
        let receipt = try await Self.parser(body: Self.reply(Self.entriesJSON)).parse(Data("%PDF".utf8))

        #expect(receipt == ParsedReceipt(year: 2025, month: 11, details: [
            ParsedReceiptDetail(
                year: 2025, month: 11, day: 7, startTime: "09:30", endTime: "15:00",
                sitterName: "高野 あみい", childName: "杏", amount: 14300
            ),
            ParsedReceiptDetail(
                year: 2025, month: 11, day: 12, startTime: "10:00", endTime: "13:00",
                sitterName: "早川明日香", childName: "杏", amount: 7800
            ),
        ]))
    }

    @Test func takesTheReceiptMonthFromTheFirstSession() async throws {
        let json = """
            {"entries":[{"date":"2025/12/01","startTime":"09:00","endTime":"10:00","sitterName":"A","childName":"杏","amount":1},\
            {"date":"2025/11/30","startTime":"09:00","endTime":"10:00","sitterName":"A","childName":"杏","amount":1}]}
            """

        let receipt = try await Self.parser(body: Self.reply(json)).parse(Data())

        #expect(receipt.year == 2025)
        #expect(receipt.month == 12)
    }

    @Test func findsTheJsonInsideProseOrCodeFences() async throws {
        let receipt = try await Self.parser(body: Self.reply("Here you go:\n```json\n\(Self.entriesJSON)\n```")).parse(Data())

        #expect(receipt.details.count == 2)
    }

    @Test func acceptsAmountsWrittenAsDecimalsOrWithCommas() async throws {
        let json = """
            {"entries":[{"date":"2025/11/07","startTime":"09:30","endTime":"15:00","sitterName":"A","childName":"杏","amount":14300.0},\
            {"date":"2025/11/12","startTime":"10:00","endTime":"13:00","sitterName":"A","childName":"杏","amount":"7,800"}]}
            """

        let receipt = try await Self.parser(body: Self.reply(json)).parse(Data())

        #expect(receipt.details.map(\.amount) == [14300, 7800])
    }

    @Test func reportsAPIErrors() async {
        let body = #"{"error":{"message":"Incorrect API key provided"}}"#

        await #expect(throws: PdfParserError.apiError(statusCode: 401, body: body)) {
            try await Self.parser(status: 401, body: Data(body.utf8)).parse(Data())
        }
        #expect(
            PdfParserError.apiError(statusCode: 401, body: body).localizedDescription
                == "OpenAI API error: 401 - \(body)"
        )
    }

    @Test func reportsRepliesWithoutAMessage() async throws {
        let body = try JSONSerialization.data(withJSONObject: ["output": [["type": "reasoning", "summary": [Any]()]]])

        await #expect(throws: PdfParserError.noContent(body: String(decoding: body, as: UTF8.self))) {
            try await Self.parser(body: body).parse(Data())
        }
    }

    @Test func reportsRepliesWithoutJson() async {
        await #expect(throws: PdfParserError.noJsonObject(content: "Sorry, I can't read this file.")) {
            try await Self.parser(body: Self.reply("Sorry, I can't read this file.")).parse(Data())
        }
    }

    @Test func reportsReceiptsWithoutSessions() async {
        await #expect(throws: PdfParserError.noEntries) {
            try await Self.parser(body: Self.reply(#"{"entries":[]}"#)).parse(Data())
        }
        #expect(PdfParserError.noEntries.localizedDescription == "No valid receipt entries found in PDF.")
    }

    @Test func reportsMalformedEntries() async {
        await #expect(throws: PdfParserError.unreadableEntries(json: #"{"entries":[{"date":"2025/11/07"}]}"#)) {
            try await Self.parser(body: Self.reply(#"{"entries":[{"date":"2025/11/07"}]}"#)).parse(Data())
        }
    }

    @Test func reportsDatesItCannotRead() async {
        let json = #"{"entries":[{"date":"11/07","startTime":"09:30","endTime":"15:00","sitterName":"A","childName":"杏","amount":1}]}"#

        await #expect(throws: PdfParserError.invalidDate("11/07")) {
            try await Self.parser(body: Self.reply(json)).parse(Data())
        }
    }

    @Test func needsAnAPIKey() async {
        let parser = PdfParser(apiKey: "") { _ in
            Issue.record("Should not send a request without an API key")
            throw URLError(.userAuthenticationRequired)
        }

        await #expect(throws: PdfParserError.missingAPIKey) {
            try await parser.parse(Data())
        }
    }
}

/// Like the Android PdfParserTest, these call the real API with the sample receipts in docs/.
@Suite(.enabled(if: LiveAPI.apiKey != nil, "Set OPENAI_API_KEY in ios/Config/Secrets.xcconfig to run these"))
struct PdfParserLiveTests {
    @Test func parsesTheNovember2025Receipt() async throws {
        let parser = PdfParser(apiKey: try #require(LiveAPI.apiKey))

        let receipt = try await parser.parse(Data(contentsOf: TestPaths.november2025Receipt))

        #expect(receipt.year == 2025)
        #expect(receipt.month == 11)
        #expect(receipt.details.map { "\($0.year)/\($0.month)/\($0.day) \($0.startTime)-\($0.endTime)" } == [
            "2025/11/7 09:30-15:00", "2025/11/12 10:00-13:00", "2025/11/21 09:30-15:00", "2025/11/25 10:00-15:30",
        ])
        #expect(receipt.details.map { $0.sitterName.filter { !$0.isWhitespace } } == ["高野あみい", "早川明日香", "高野あみい", "木村美穂"])
        #expect(receipt.details.allSatisfy { $0.childName == "杏" })
        // 助成対象金額, as on the hand-filled form (docs/exampe-output-data.csv), not お支払い額 with transport.
        #expect(receipt.details.map(\.amount) == [14300, 7800, 14300, 14300])
    }

    @Test func parsesTheDecember2024Receipt() async throws {
        let parser = PdfParser(apiKey: try #require(LiveAPI.apiKey))

        let receipt = try await parser.parse(Data(contentsOf: TestPaths.december2024Receipt))

        #expect(receipt.details.map { "\($0.year)/\($0.month)/\($0.day) \($0.startTime)-\($0.endTime)" } == [
            "2024/12/6 18:45-19:45", "2024/12/16 18:45-19:45",
        ])
        #expect(receipt.details.map { $0.sitterName.filter { !$0.isWhitespace } } == ["蜜本沙希穂", "蜜本沙希穂"])
        #expect(receipt.details.allSatisfy { $0.childName == "杏" })
        // 保育料（非課税）: this older receipt has no 助成対象金額 column, and お支払い額 includes ¥1,310 transport.
        #expect(receipt.details.map(\.amount) == [2310, 3355])
    }
}

enum LiveAPI {
    /// The key the app was built with, if any.
    static var apiKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String, !key.isEmpty else {
            return nil
        }
        return key
    }
}
