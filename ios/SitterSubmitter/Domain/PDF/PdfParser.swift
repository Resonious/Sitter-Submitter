import Foundation
import os

struct ParsedReceipt: Equatable, Sendable {
    let year: Int
    let month: Int
    let details: [ParsedReceiptDetail]
}

struct ParsedReceiptDetail: Equatable, Sendable {
    let year: Int
    let month: Int
    let day: Int
    let startTime: String
    let endTime: String
    let sitterName: String
    let childName: String
    let amount: Int
}

/// Reads the sessions out of a babysitter receipt PDF. Poppins is the only provider so far.
protocol PdfParsing: Sendable {
    func parse(_ pdfData: Data) async throws -> ParsedReceipt
}

/// Port of the Android `PdfParser`: sends the PDF to the OpenAI Responses API and reads back the table rows.
struct PdfParser: PdfParsing {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let model = "gpt-6.1-sol"
    static let apiURL = URL(string: "https://api.openai.com/v1/responses")!

    // Keep in sync with the Android PdfParser (PdfParserTests checks this).
    static let prompt = """
        Analyze this Japanese babysitter receipt PDF table. Each row represents one babysitting session.

        The table columns are: ご利用日 | 開始時刻 | 終了時刻 | シッター名 | お子さま | 保育料... | お支払い額

        For each data row, extract:
        - date: from ご利用日 column (YYYY/MM/DD format)
        - startTime: from 開始時刻 column (HH:MM format)
        - endTime: from 終了時刻 column (HH:MM format)
        - sitterName: from シッター名 column (full name)
        - childName: from お子さま column - this contains the child's name followed by 様 and age in parentheses. Extract ONLY the single character or short name before 様. For example if the cell shows "杏 様 (0歳6ヶ月)" extract just "杏". Do NOT include 様, age, or any text from adjacent columns.
        - amount: the childcare fee covered by the subsidy, as an integer with no commas. If the table has a 助成対象金額 column, use that. Otherwise use 保育料（非課税） + 保育料（税込10%） - 割引額. Never include 交通費, オプション料, 特別費用 or キャンセル料, so do NOT use the お支払い額 column.

        Return JSON: {"entries":[{"date":"YYYY/MM/DD","startTime":"HH:MM","endTime":"HH:MM","sitterName":"Name","childName":"Child","amount":1234}]}
        """

    private let apiKey: String
    private let transport: Transport

    init(apiKey: String, transport: @escaping Transport = { try await URLSession.shared.data(for: $0) }) {
        self.apiKey = apiKey
        self.transport = transport
    }

    /// Uses `OPENAI_API_KEY` from Config/Secrets.xcconfig, which the build puts in Info.plist
    /// (the Android app reads it from local.properties).
    static func configured(bundle: Bundle = .main) -> PdfParser {
        PdfParser(apiKey: bundle.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? "")
    }

    func parse(_ pdfData: Data) async throws -> ParsedReceipt {
        guard !apiKey.isEmpty else { throw PdfParserError.missingAPIKey }
        let request = try makeRequest(pdfData: pdfData)
        logger.debug("Sending request to OpenAI API...")
        let (data, response) = try await transport(request)
        return try parseResponse(data: data, response: response)
    }

    func makeRequest(pdfData: Data) throws -> URLRequest {
        // Responses API request; it accepts PDFs natively.
        let body = ResponsesRequest(
            model: Self.model,
            input: [
                .init(role: "user", content: [
                    .init(type: "input_text", text: Self.prompt),
                    .init(
                        type: "input_file",
                        filename: "receipt.pdf",
                        fileData: "data:application/pdf;base64,\(pdfData.base64EncodedString())"
                    ),
                ]),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes

        var request = URLRequest(url: Self.apiURL, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return request
    }

    func parseResponse(data: Data, response: URLResponse) throws -> ParsedReceipt {
        let responseBody = String(decoding: data, as: UTF8.self)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        logger.debug("Response code: \(statusCode)")

        guard (200..<300).contains(statusCode) else {
            logger.error("API Error: \(responseBody, privacy: .private)")
            throw PdfParserError.apiError(statusCode: statusCode, body: responseBody)
        }
        guard !data.isEmpty else { throw PdfParserError.emptyResponse }
        logger.debug("Response body: \(responseBody, privacy: .private)")

        // Navigate: output[] -> find message type -> content[] -> find output_text -> text
        // (reasoning models put "reasoning" items before the message).
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let output = json?["output"] as? [[String: Any]] ?? []
        let content = output
            .filter { $0["type"] as? String == "message" }
            .flatMap { $0["content"] as? [[String: Any]] ?? [] }
            .first { $0["type"] as? String == "output_text" && $0["text"] is String }?["text"] as? String
        guard let content else { throw PdfParserError.noContent(body: responseBody) }

        // Extract JSON from response
        let jsonText = try Self.extractJson(content)
        logger.debug("Cleaned content: \(jsonText, privacy: .private)")

        let extracted: ExtractedReceiptData
        do {
            extracted = try JSONDecoder().decode(ExtractedReceiptData.self, from: Data(jsonText.utf8))
        } catch {
            throw PdfParserError.unreadableEntries(json: jsonText)
        }
        guard !extracted.entries.isEmpty else { throw PdfParserError.noEntries }

        let details = try extracted.entries.map { entry in
            let dateParts = entry.date.split(whereSeparator: { $0 == "/" || $0 == "-" })
                .map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard dateParts.count == 3, let year = dateParts[0], let month = dateParts[1], let day = dateParts[2] else {
                throw PdfParserError.invalidDate(entry.date)
            }
            return ParsedReceiptDetail(
                year: year,
                month: month,
                day: day,
                startTime: entry.startTime,
                endTime: entry.endTime,
                sitterName: entry.sitterName,
                childName: entry.childName,
                amount: entry.amount
            )
        }

        let first = details[0]
        return ParsedReceipt(year: first.year, month: first.month, details: details)
    }

    /// The outermost `{…}` in the model's reply, which may wrap the JSON in prose or code fences.
    static func extractJson(_ content: String) throws -> String {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start < end
        else { throw PdfParserError.noJsonObject(content: content) }
        return String(content[start...end])
    }
}

enum PdfParserError: LocalizedError, Equatable {
    case missingAPIKey
    case emptyResponse
    case apiError(statusCode: Int, body: String)
    case noContent(body: String)
    case noJsonObject(content: String)
    case unreadableEntries(json: String)
    case noEntries
    case invalidDate(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "No OpenAI API key is configured. Set OPENAI_API_KEY in ios/Config/Secrets.xcconfig and rebuild."
        case .emptyResponse:
            "Empty response from OpenAI API"
        case let .apiError(statusCode, body):
            "OpenAI API error: \(statusCode) - \(body)"
        case .noContent(let body):
            "No content in OpenAI response: \(body)"
        case .noJsonObject(let content):
            "No valid JSON object found in response: \(content)"
        case .unreadableEntries(let json):
            "Could not read receipt entries from response: \(json)"
        case .noEntries:
            "No valid receipt entries found in PDF."
        case .invalidDate(let date):
            "Invalid date in receipt entry: \(date)"
        }
    }
}

private let logger = Logger(subsystem: "dev.baillie.sittersubmitter", category: "PdfParser")

// MARK: - Request and response models

private struct ResponsesRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: [ContentPart]
    }

    struct ContentPart: Encodable {
        let type: String
        var text: String?
        var filename: String?
        var fileData: String?

        enum CodingKeys: String, CodingKey {
            case type, text, filename
            case fileData = "file_data"
        }
    }

    let model: String
    let input: [Message]
}

private struct ExtractedReceiptData: Decodable {
    let entries: [ExtractedEntry]
}

private struct ExtractedEntry: Decodable {
    let date: String
    let startTime: String
    let endTime: String
    let sitterName: String
    let childName: String
    let amount: Int

    private enum CodingKeys: String, CodingKey {
        case date, startTime, endTime, sitterName, childName, amount
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        startTime = try container.decode(String.self, forKey: .startTime)
        endTime = try container.decode(String.self, forKey: .endTime)
        sitterName = try container.decode(String.self, forKey: .sitterName)
        childName = try container.decode(String.self, forKey: .childName)
        // Be as forgiving as Gson on Android: 14300.0 is fine, and so is "14,300".
        if let integer = try? container.decode(Int.self, forKey: .amount) {
            amount = integer
        } else if let double = try? container.decode(Double.self, forKey: .amount), let integer = Int(exactly: double) {
            amount = integer
        } else if let text = try? container.decode(String.self, forKey: .amount),
                  let integer = Int(text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) {
            amount = integer
        } else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: container, debugDescription: "amount is not an integer")
        }
    }
}
