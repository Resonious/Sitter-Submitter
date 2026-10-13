import Foundation

/// Fills in cells of an existing .xlsx workbook (the bundled submission template) while copying every other
/// part of the package (styles, drawings, merged cells, validations, print settings) through untouched.
///
/// Foundation's `XMLDocument` isn't available on iOS, so the SpreadsheetML is edited textually. That is
/// reliable for workbooks saved by Excel, which write each row and cell as a single `<row>`/`<c>` element,
/// but this isn't a general-purpose XLSX library: it only edits cells that already exist in the first sheet.
struct XlsxTemplate {
    enum CellValue: Equatable {
        case string(String)
        case number(Double)
        case formula(String, cachedResult: FormulaResult?)
        case blank
    }

    enum FormulaResult: Equatable {
        case number(Double)
        case text(String)
        /// An Excel error value such as `#VALUE!`.
        case error(String)
    }

    static let workbookPath = "xl/workbook.xml"
    static let worksheetPath = "xl/worksheets/sheet1.xml"
    static let sharedStringsPath = "xl/sharedStrings.xml"

    private var archive: ZipArchive
    private var workbook: String
    private var worksheet: Worksheet
    private var sharedStrings: SharedStringTable

    init(data: Data) throws {
        archive = try ZipArchive(data: data)
        workbook = try Self.text(of: Self.workbookPath, in: archive)
        worksheet = try Worksheet(xml: Self.text(of: Self.worksheetPath, in: archive))
        sharedStrings = try SharedStringTable(xml: Self.text(of: Self.sharedStringsPath, in: archive))
    }

    // MARK: - Writing

    /// Stores `value` as a shared string, like Excel (and Apache POI on Android) do.
    mutating func setString(_ value: String, at reference: String) throws {
        let index = sharedStrings.index(of: value)
        try worksheet.updateCell(reference) { cell in
            cell.setAttribute("t", to: "s")
            cell.body = "<v>\(index)</v>"
        }
    }

    mutating func setNumber(_ value: Double, at reference: String) throws {
        try worksheet.updateCell(reference) { cell in
            cell.removeAttribute("t")
            cell.body = "<v>\(Self.format(value))</v>"
        }
    }

    /// Replaces the cached result of the formula in `reference`, keeping the formula itself.
    mutating func setFormulaResult(_ result: FormulaResult, at reference: String) throws {
        try worksheet.updateCell(reference) { cell in
            guard let formula = cell.formulaElement else { throw TemplateError.notAFormula(reference) }
            switch result {
            case .number(let value):
                cell.removeAttribute("t")
                cell.body = formula + "<v>\(Self.format(value))</v>"
            case .text(let text):
                cell.setAttribute("t", to: "str")
                cell.body = formula + "<v>\(Self.escape(text))</v>"
            case .error(let code):
                cell.setAttribute("t", to: "e")
                cell.body = formula + "<v>\(Self.escape(code))</v>"
            }
        }
    }

    /// Sets the width (in characters) of a single column, e.g. `"B"`, splitting any `<col>` range that spans it.
    mutating func setColumnWidth(_ width: Double, forColumn column: String) throws {
        try worksheet.setColumnWidth(Self.format(width), column: Self.columnNumber(column))
    }

    /// Asks spreadsheet apps that honour it (Excel) to recalculate every formula when the file is opened.
    mutating func forceFullCalculationOnLoad() throws {
        guard let range = workbook.range(of: #"<calcPr\b[^>]*>"#, options: .regularExpression) else {
            throw TemplateError.malformed("\(Self.workbookPath) has no <calcPr> element")
        }
        workbook.replaceSubrange(range, with: XMLTag(workbook[range]).setting("fullCalcOnLoad", to: "1").selfClosingText)
    }

    func makeData() throws -> Data {
        var archive = archive
        archive[Self.workbookPath] = Data(workbook.utf8)
        archive[Self.worksheetPath] = Data(worksheet.xml.utf8)
        archive[Self.sharedStringsPath] = Data(sharedStrings.xml(referenceCount: worksheet.sharedStringReferenceCount).utf8)
        return try archive.serialized()
    }

    // MARK: - Reading

    func value(at reference: String) -> CellValue? {
        guard let cell = worksheet.cell(reference) else { return nil }
        let type = cell.attribute("t")
        let rawValue = cell.body.flatMap { Self.firstMatch(of: #"<v>(.*?)</v>"#, in: $0) }.map(Self.unescape)
        if let formula = cell.formulaElement {
            let expression = Self.firstMatch(of: #"<f\b[^>]*>(.*?)</f>"#, in: formula).map(Self.unescape) ?? ""
            let cached: FormulaResult? = rawValue.flatMap { raw in
                switch type {
                case "e": .error(raw)
                case "str": .text(raw)
                default: Double(raw).map(FormulaResult.number)
                }
            }
            return .formula(expression, cachedResult: cached)
        }
        switch (type, rawValue) {
        case ("s", let raw?):
            return Int(raw).flatMap(sharedStrings.text(at:)).map(CellValue.string) ?? .blank
        case ("inlineStr", _):
            return cell.body.map { .string(SharedStringTable.plainText(of: $0)) } ?? .blank
        case ("str", let raw?):
            return .string(raw)
        case (_, let raw?):
            return Double(raw).map(CellValue.number) ?? .string(raw)
        default:
            return .blank
        }
    }

    func styleIndex(at reference: String) -> Int? {
        worksheet.cell(reference)?.attribute("s").flatMap(Int.init)
    }

    func columnWidth(forColumn column: String) -> Double? {
        worksheet.columnWidth(column: Self.columnNumber(column))
    }

    var isFullCalculationOnLoadEnabled: Bool {
        guard let range = workbook.range(of: #"<calcPr\b[^>]*>"#, options: .regularExpression) else { return false }
        let value = XMLTag(workbook[range]).attribute("fullCalcOnLoad")
        return value == "1" || value == "true"
    }

    // MARK: - Helpers

    private static func text(of path: String, in archive: ZipArchive) throws -> String {
        guard let data = archive[path] else { throw TemplateError.missingPart(path) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Excel's own representation: integers without a decimal point, everything else round-trippable.
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return "\(value)"
    }

    static func columnNumber(_ letters: String) -> Int {
        letters.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 }
    }

    static func escape(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "\t", "\n":
                escaped.unicodeScalars.append(scalar)
            case _ where scalar.value < 0x20 || scalar.value == 0xFFFE || scalar.value == 0xFFFF:
                // Not allowed in XML 1.0; Office escapes these (and carriage returns) as _xHHHH_.
                escaped += String(format: "_x%04X_", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }
        return escaped
    }

    static func unescape(_ text: String) -> String {
        guard text.contains("&") || text.contains("_x") else { return text }
        var result = text
        for (entity, character) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'")] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        result = replacingMatches(of: #"&#(x?)([0-9A-Fa-f]+);"#, in: result) { groups in
            UInt32(groups[2], radix: groups[1].isEmpty ? 10 : 16).flatMap(Unicode.Scalar.init).map(String.init)
        }
        result = replacingMatches(of: #"_x([0-9A-Fa-f]{4})_"#, in: result) { groups in
            UInt32(groups[1], radix: 16).flatMap(Unicode.Scalar.init).map(String.init)
        }
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func firstMatch(of pattern: String, in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound
        else { return nil }
        return nsText.substring(with: match.range(at: 1))
    }

    /// Replaces each match of `pattern` with `transform(captureGroups)`, leaving it as-is when that returns nil.
    private static func replacingMatches(of pattern: String, in text: String, with transform: ([String]) -> String?) -> String {
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            let groups = (0..<match.numberOfRanges).map { index in
                match.range(at: index).location == NSNotFound ? "" : nsText.substring(with: match.range(at: index))
            }
            result += nsText.substring(with: NSRange(location: location, length: match.range.location - location))
            result += transform(groups) ?? groups[0]
            location = match.range.location + match.range.length
        }
        return result + nsText.substring(from: location)
    }
}

enum TemplateError: LocalizedError, Equatable {
    case missingPart(String)
    case missingCell(String)
    case notAFormula(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .missingPart(let path): "The template is missing \(path)"
        case .missingCell(let reference): "The template has no cell \(reference)"
        case .notAFormula(let reference): "Cell \(reference) in the template has no formula"
        case .malformed(let reason): "The template is malformed: \(reason)"
        }
    }
}

// MARK: - Worksheet XML

/// `<sheetData>` split into rows and cells; text outside it is kept verbatim.
private struct Worksheet {
    struct Row {
        /// The original `<row …>` start tag, or the whole element when it's self-closing.
        var start: String
        var cells: [Cell]
        var isSelfClosing: Bool
    }

    private var head: String
    private var rows: [Row]
    private let tail: String
    private var cellLocations: [String: (row: Int, cell: Int)] = [:]

    init(xml: String) throws {
        guard let open = xml.range(of: "<sheetData>"), let close = xml.range(of: "</sheetData>") else {
            throw TemplateError.malformed("\(XlsxTemplate.worksheetPath) has no <sheetData>")
        }
        head = String(xml[..<open.upperBound])
        tail = String(xml[close.lowerBound...])

        let body = String(xml[open.upperBound..<close.lowerBound])
        let rowPattern = try! NSRegularExpression(pattern: #"<row\b[^>]*?(?:/>|>(.*?)</row>)"#, options: .dotMatchesLineSeparators)
        let cellPattern = try! NSRegularExpression(pattern: #"<c\b[^>]*?(?:/>|>.*?</c>)"#, options: .dotMatchesLineSeparators)
        let nsBody = body as NSString
        rows = rowPattern.matches(in: body, range: NSRange(location: 0, length: nsBody.length)).map { match in
            let element = nsBody.substring(with: match.range)
            guard match.range(at: 1).location != NSNotFound else {
                return Row(start: element, cells: [], isSelfClosing: true)
            }
            let contents = nsBody.substring(with: match.range(at: 1))
            let nsContents = contents as NSString
            let cells = cellPattern.matches(in: contents, range: NSRange(location: 0, length: nsContents.length)).map {
                Cell(xml: nsContents.substring(with: $0.range))
            }
            let start = String(element[..<element.firstIndex(of: ">")!]) + ">"
            return Row(start: start, cells: cells, isSelfClosing: false)
        }

        for (rowIndex, row) in rows.enumerated() {
            for (cellIndex, cell) in row.cells.enumerated() {
                if let reference = cell.attribute("r") {
                    cellLocations[reference] = (rowIndex, cellIndex)
                }
            }
        }
        // Everything must survive the round trip, or edits could silently drop content.
        guard self.xml == xml else {
            throw TemplateError.malformed("unexpected content in \(XlsxTemplate.worksheetPath)")
        }
    }

    var xml: String {
        head + rows.map { row in
            row.isSelfClosing ? row.start : row.start + row.cells.map(\.xml).joined() + "</row>"
        }.joined() + tail
    }

    var sharedStringReferenceCount: Int {
        rows.reduce(0) { count, row in count + row.cells.filter { $0.attribute("t") == "s" }.count }
    }

    func cell(_ reference: String) -> Cell? {
        cellLocations[reference].map { rows[$0.row].cells[$0.cell] }
    }

    mutating func updateCell(_ reference: String, _ update: (inout Cell) throws -> Void) throws {
        guard let location = cellLocations[reference] else { throw TemplateError.missingCell(reference) }
        try update(&rows[location.row].cells[location.cell])
    }

    // MARK: Columns

    func columnWidth(column: Int) -> Double? {
        columns().first { $0.covers(column) }?.tag.attribute("width").flatMap(Double.init)
    }

    mutating func setColumnWidth(_ width: String, column: Int) throws {
        guard let colsRange = head.range(of: #"(?s)<cols>.*?</cols>"#, options: .regularExpression) else {
            throw TemplateError.malformed("\(XlsxTemplate.worksheetPath) has no <cols>")
        }
        var updated: [Column] = []
        for existing in columns() {
            guard existing.covers(column) else {
                updated.append(existing)
                continue
            }
            // Split min…max around the target so neighbouring columns keep their width.
            if existing.min < column {
                updated.append(existing.withRange(existing.min, column - 1))
            }
            var target = existing.withRange(column, column)
            target.tag = target.tag.setting("width", to: width).setting("customWidth", to: "1")
            updated.append(target)
            if column < existing.max {
                updated.append(existing.withRange(column + 1, existing.max))
            }
        }
        if !updated.contains(where: { $0.covers(column) }) {
            let tag = XMLTag("<col/>")
                .setting("min", to: String(column)).setting("max", to: String(column))
                .setting("width", to: width).setting("customWidth", to: "1")
            updated.append(Column(tag: tag))
        }
        updated.sort { $0.min < $1.min }
        head.replaceSubrange(colsRange, with: "<cols>" + updated.map(\.tag.selfClosingText).joined() + "</cols>")
    }

    private func columns() -> [Column] {
        guard let cols = XlsxTemplate.firstMatch(of: #"<cols>(.*?)</cols>"#, in: head) else { return [] }
        let regex = try! NSRegularExpression(pattern: #"<col\b[^>]*/>"#)
        let nsCols = cols as NSString
        return regex.matches(in: cols, range: NSRange(location: 0, length: nsCols.length)).map {
            Column(tag: XMLTag(nsCols.substring(with: $0.range)))
        }
    }

    private struct Column {
        var tag: XMLTag

        var min: Int { tag.attribute("min").flatMap(Int.init) ?? 0 }
        var max: Int { tag.attribute("max").flatMap(Int.init) ?? 0 }

        func covers(_ column: Int) -> Bool { (min...max).contains(column) }

        func withRange(_ min: Int, _ max: Int) -> Column {
            Column(tag: tag.setting("min", to: String(min)).setting("max", to: String(max)))
        }
    }
}

/// A `<c>` element.
private struct Cell {
    private var tag: XMLTag
    /// Inner XML, or nil for an empty `<c …/>` element.
    var body: String?

    init(xml: String) {
        let startEnd = xml.firstIndex(of: ">")!
        if xml[xml.index(before: startEnd)] == "/" {
            tag = XMLTag(xml)
            body = nil
        } else {
            tag = XMLTag(String(xml[...startEnd]))
            body = String(xml[xml.index(after: startEnd)..<xml.index(xml.endIndex, offsetBy: -"</c>".count)])
        }
    }

    var xml: String {
        guard let body else { return tag.selfClosingText }
        return tag.openingText + body + "</c>"
    }

    /// The `<f>` element, when this cell holds a formula.
    var formulaElement: String? {
        guard let body,
              let range = body.range(of: #"(?s)<f\b[^>]*?(?:/>|>.*?</f>)"#, options: .regularExpression)
        else { return nil }
        return String(body[range])
    }

    func attribute(_ name: String) -> String? { tag.attribute(name) }

    mutating func setAttribute(_ name: String, to value: String) { tag = tag.setting(name, to: value) }

    mutating func removeAttribute(_ name: String) { tag = tag.removing(name) }
}

/// A start tag (or empty-element tag) with its attributes kept in their original order.
private struct XMLTag {
    private(set) var name: String
    private var attributes: [(name: String, value: String)]

    init<S: StringProtocol>(_ text: S) {
        let text = String(text)
        name = XlsxTemplate.firstMatch(of: #"^<([\w:]+)"#, in: text) ?? ""
        let regex = try! NSRegularExpression(pattern: #"([\w:]+)="([^"]*)""#)
        let nsText = text as NSString
        attributes = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map {
            (nsText.substring(with: $0.range(at: 1)), nsText.substring(with: $0.range(at: 2)))
        }
    }

    /// The (still XML-escaped) value of an attribute.
    func attribute(_ name: String) -> String? {
        attributes.first { $0.name == name }?.value
    }

    func setting(_ name: String, to value: String) -> XMLTag {
        var copy = self
        if let index = copy.attributes.firstIndex(where: { $0.name == name }) {
            copy.attributes[index].value = value
        } else {
            copy.attributes.append((name, value))
        }
        return copy
    }

    func removing(_ name: String) -> XMLTag {
        var copy = self
        copy.attributes.removeAll { $0.name == name }
        return copy
    }

    var openingText: String { "<\(name)\(attributeText)>" }
    var selfClosingText: String { "<\(name)\(attributeText)/>" }

    private var attributeText: String {
        attributes.map { " \($0.name)=\"\($0.value)\"" }.joined()
    }
}

// MARK: - Shared strings

private struct SharedStringTable {
    private var xml: String
    private var items: [String]
    private var added: [String] = []
    private var indexByText: [String: Int] = [:]

    init(xml: String) throws {
        guard xml.range(of: #"<sst\b[^>]*>"#, options: .regularExpression) != nil, xml.contains("</sst>") else {
            throw TemplateError.malformed("\(XlsxTemplate.sharedStringsPath) has no <sst>")
        }
        self.xml = xml
        let regex = try! NSRegularExpression(pattern: #"<si>(.*?)</si>|<si/>"#, options: .dotMatchesLineSeparators)
        let nsXML = xml as NSString
        items = regex.matches(in: xml, range: NSRange(location: 0, length: nsXML.length)).map { match in
            match.range(at: 1).location == NSNotFound ? "" : nsXML.substring(with: match.range(at: 1))
        }
        // Reuse existing plain entries the way Excel and POI do; rich-text entries are left alone.
        for (index, item) in items.enumerated() where indexByText[Self.plainText(of: item)] == nil {
            if item.range(of: #"^<t(?: xml:space="preserve")?>[^<]*</t>$"#, options: .regularExpression) != nil {
                indexByText[Self.plainText(of: item)] = index
            }
        }
    }

    mutating func index(of text: String) -> Int {
        if let index = indexByText[text] { return index }
        let index = items.count + added.count
        added.append(text)
        indexByText[text] = index
        return index
    }

    func text(at index: Int) -> String? {
        if items.indices.contains(index) { return Self.plainText(of: items[index]) }
        let addedIndex = index - items.count
        return added.indices.contains(addedIndex) ? added[addedIndex] : nil
    }

    func xml(referenceCount: Int) -> String {
        let newItems = added.map { text -> String in
            let preserve = text.first?.isWhitespace == true || text.last?.isWhitespace == true
            return "<si><t\(preserve ? #" xml:space="preserve""# : "")>\(XlsxTemplate.escape(text))</t></si>"
        }.joined()
        var result = xml
        let closing = result.range(of: "</sst>", options: .backwards)!
        result.replaceSubrange(closing, with: newItems + "</sst>")
        let rootRange = result.range(of: #"<sst\b[^>]*>"#, options: .regularExpression)!
        let root = XMLTag(result[rootRange])
            .setting("count", to: String(referenceCount))
            .setting("uniqueCount", to: String(items.count + added.count))
        result.replaceSubrange(rootRange, with: root.openingText)
        return result
    }

    /// The visible text of a string item: its `<t>` runs, minus phonetic (furigana) hints.
    static func plainText(of item: String) -> String {
        let withoutPhonetics = item.replacingOccurrences(of: #"(?s)<rPh\b.*?</rPh>"#, with: "", options: .regularExpression)
        let regex = try! NSRegularExpression(pattern: #"<t\b[^>]*>(.*?)</t>"#, options: .dotMatchesLineSeparators)
        let nsItem = withoutPhonetics as NSString
        return regex.matches(in: withoutPhonetics, range: NSRange(location: 0, length: nsItem.length))
            .map { XlsxTemplate.unescape(nsItem.substring(with: $0.range(at: 1))) }
            .joined()
    }
}
