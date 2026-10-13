import Foundation
import Testing
@testable import SitterSubmitter

struct ZipArchiveTests {
    @Test func readsTheTemplate() throws {
        let archive = try ZipArchive(data: Data(contentsOf: TestPaths.template))

        #expect(archive.entries.map(\.path) == [
            "[Content_Types].xml", "_rels/.rels", "xl/workbook.xml", "xl/_rels/workbook.xml.rels",
            "xl/worksheets/sheet1.xml", "xl/worksheets/_rels/sheet1.xml.rels", "xl/theme/theme1.xml",
            "xl/styles.xml", "xl/sharedStrings.xml", "xl/drawings/drawing1.xml",
            "xl/printerSettings/printerSettings1.bin", "xl/persons/person.xml", "xl/calcChain.xml",
            "docProps/core.xml", "docProps/app.xml", "docProps/custom.xml", "docMetadata/LabelInfo.xml",
        ])
        // Sizes and CRC-32s as listed by `unzip -v`.
        #expect(archive["xl/worksheets/sheet1.xml"]?.count == 26950)
        #expect(ZipArchive.checksum(try #require(archive["[Content_Types].xml"])) == 0xADB5_C013)
        #expect(ZipArchive.checksum(try #require(archive["xl/worksheets/sheet1.xml"])) == 0xDD1E_C7C9)
    }

    @Test func rewritingTheTemplateKeepsEveryPart() throws {
        let original = try ZipArchive(data: Data(contentsOf: TestPaths.template))

        let rewritten = try ZipArchive(data: original.serialized())

        #expect(rewritten.entries == original.entries)
    }

    @Test func roundTripsStoredAndDeflatedEntries() throws {
        var archive = ZipArchive()
        archive["compressible.txt"] = Data(String(repeating: "ベビーシッター ", count: 200).utf8)
        archive["empty"] = Data()
        archive["random.bin"] = Data((0..<1000).map { _ in UInt8.random(in: .min ... .max) }) // Stored: won't compress
        archive["日本語/名前.xml"] = Data("<a>杏</a>".utf8)

        let reread = try ZipArchive(data: archive.serialized())

        #expect(reread.entries.map(\.path) == ["compressible.txt", "empty", "random.bin", "日本語/名前.xml"])
        #expect(reread.entries.map(\.data) == archive.entries.map(\.data))
    }

    @Test func replacesAndRemovesEntriesInPlace() {
        var archive = ZipArchive(entries: [
            .init(path: "a", data: Data("1".utf8)),
            .init(path: "b", data: Data("2".utf8)),
        ])

        archive["a"] = Data("3".utf8)
        archive["c"] = Data("4".utf8)
        archive["b"] = nil

        #expect(archive.entries.map(\.path) == ["a", "c"])
        #expect(archive["a"] == Data("3".utf8))
        #expect(archive["b"] == nil)
    }

    @Test func rejectsDataThatIsNotAZip() {
        #expect(throws: ZipError.self) {
            try ZipArchive(data: Data("not a zip file".utf8))
        }
    }

    @Test func detectsCorruptedEntries() throws {
        var data = try ZipArchive(entries: [.init(path: "a.txt", data: Data(repeating: 65, count: 100))]).serialized()
        data[30 + "a.txt".count] ^= 0xFF // First byte of the compressed data

        #expect(throws: ZipError.self) {
            try ZipArchive(data: data)
        }
    }
}
