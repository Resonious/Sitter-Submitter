import Foundation
import Testing
@testable import SitterSubmitter

struct IncomingFileTests {
    private func makeFile(in folder: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("receipt-\(UUID().uuidString).pdf")
        try Data("%PDF-1.4".utf8).write(to: file)
        return file
    }

    @Test func removesTheCopyIOSMadeForTheApp() throws {
        let file = try makeFile(in: "dev.baillie.sittersubmitter-Inbox")

        IncomingFile.removeIfInboxCopy(file)

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func leavesOtherFilesAlone() throws {
        let file = try makeFile(in: "SitterSubmitterTests-\(UUID().uuidString)")

        IncomingFile.removeIfInboxCopy(file)

        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
