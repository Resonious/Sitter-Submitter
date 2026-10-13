import Compression
import Foundation
import zlib

/// Just enough of the ZIP format to read and rewrite an .xlsx package: stored or deflated entries on a
/// single disk, without encryption or ZIP64. Entries keep their order and timestamps.
struct ZipArchive {
    struct Entry: Equatable {
        var path: String
        var data: Data
        /// MS-DOS modification time and date, carried through unchanged so output is deterministic.
        var dosTime: UInt16 = 0
        var dosDate: UInt16 = 0x21 // 1980-01-01
    }

    private(set) var entries: [Entry]

    init(entries: [Entry] = []) {
        self.entries = entries
    }

    init(data: Data) throws {
        let reader = ByteReader(bytes: [UInt8](data))
        let endOfCentralDirectory = try reader.findEndOfCentralDirectory()
        let entryCount = Int(try reader.uint16(at: endOfCentralDirectory + 10))
        var offset = Int(try reader.uint32(at: endOfCentralDirectory + 16))

        var entries: [Entry] = []
        entries.reserveCapacity(entryCount)
        for _ in 0..<entryCount {
            guard try reader.uint32(at: offset) == Signature.centralDirectoryHeader else {
                throw ZipError.malformed("Bad central directory header at offset \(offset)")
            }
            let flags = try reader.uint16(at: offset + 8)
            let method = try reader.uint16(at: offset + 10)
            let dosTime = try reader.uint16(at: offset + 12)
            let dosDate = try reader.uint16(at: offset + 14)
            let crc = try reader.uint32(at: offset + 16)
            let compressedSize = Int(try reader.uint32(at: offset + 20))
            let uncompressedSize = Int(try reader.uint32(at: offset + 24))
            let nameLength = Int(try reader.uint16(at: offset + 28))
            let extraLength = Int(try reader.uint16(at: offset + 30))
            let commentLength = Int(try reader.uint16(at: offset + 32))
            let localHeaderOffset = Int(try reader.uint32(at: offset + 42))
            let path = String(decoding: try reader.bytes(at: offset + 46, count: nameLength), as: UTF8.self)

            guard flags & 0x1 == 0 else { throw ZipError.unsupported("\(path) is encrypted") }
            guard try reader.uint32(at: localHeaderOffset) == Signature.localFileHeader else {
                throw ZipError.malformed("Bad local file header for \(path)")
            }
            // Sizes come from the central directory: the local header may defer them to a data descriptor.
            let dataOffset = localHeaderOffset + 30
                + Int(try reader.uint16(at: localHeaderOffset + 26))
                + Int(try reader.uint16(at: localHeaderOffset + 28))
            let stored = try reader.bytes(at: dataOffset, count: compressedSize)

            let contents: Data
            switch method {
            case Method.stored:
                contents = Data(stored)
            case Method.deflated:
                contents = try Self.inflate(stored, uncompressedSize: uncompressedSize, path: path)
            default:
                throw ZipError.unsupported("\(path) uses compression method \(method)")
            }
            guard Self.checksum(contents) == crc else { throw ZipError.malformed("Checksum mismatch for \(path)") }

            entries.append(Entry(path: path, data: contents, dosTime: dosTime, dosDate: dosDate))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    /// The contents of the entry at `path`. Assigning replaces the entry in place (or appends a new one);
    /// assigning `nil` removes it.
    subscript(path: String) -> Data? {
        get { entries.first { $0.path == path }?.data }
        set {
            let index = entries.firstIndex { $0.path == path }
            switch (index, newValue) {
            case let (index?, data?): entries[index].data = data
            case let (nil, data?): entries.append(Entry(path: path, data: data))
            case let (index?, nil): entries.remove(at: index)
            case (nil, nil): break
            }
        }
    }

    func serialized() throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw ZipError.tooLarge }
        var output = Data()
        var centralDirectory = Data()

        for entry in entries {
            let name = Array(entry.path.utf8)
            let crc = Self.checksum(entry.data)
            let deflated = Self.deflate(entry.data)
            let payload = deflated ?? entry.data
            let method = deflated == nil ? Method.stored : Method.deflated
            // Bit 11: the file name is UTF-8.
            let flags: UInt16 = name.contains { $0 >= 0x80 } ? 0x0800 : 0
            guard name.count <= Int(UInt16.max),
                  let localHeaderOffset = UInt32(exactly: output.count),
                  let compressedSize = UInt32(exactly: payload.count),
                  let uncompressedSize = UInt32(exactly: entry.data.count)
            else { throw ZipError.tooLarge }

            output.appendLittleEndian(Signature.localFileHeader)
            output.appendLittleEndian(Version.neededToExtract)
            output.appendLittleEndian(flags)
            output.appendLittleEndian(method)
            output.appendLittleEndian(entry.dosTime)
            output.appendLittleEndian(entry.dosDate)
            output.appendLittleEndian(crc)
            output.appendLittleEndian(compressedSize)
            output.appendLittleEndian(uncompressedSize)
            output.appendLittleEndian(UInt16(name.count))
            output.appendLittleEndian(UInt16(0)) // extra field length
            output.append(contentsOf: name)
            output.append(payload)

            centralDirectory.appendLittleEndian(Signature.centralDirectoryHeader)
            centralDirectory.appendLittleEndian(Version.madeBy)
            centralDirectory.appendLittleEndian(Version.neededToExtract)
            centralDirectory.appendLittleEndian(flags)
            centralDirectory.appendLittleEndian(method)
            centralDirectory.appendLittleEndian(entry.dosTime)
            centralDirectory.appendLittleEndian(entry.dosDate)
            centralDirectory.appendLittleEndian(crc)
            centralDirectory.appendLittleEndian(compressedSize)
            centralDirectory.appendLittleEndian(uncompressedSize)
            centralDirectory.appendLittleEndian(UInt16(name.count))
            centralDirectory.appendLittleEndian(UInt16(0)) // extra field length
            centralDirectory.appendLittleEndian(UInt16(0)) // comment length
            centralDirectory.appendLittleEndian(UInt16(0)) // disk number start
            centralDirectory.appendLittleEndian(UInt16(0)) // internal attributes
            centralDirectory.appendLittleEndian(UInt32(0)) // external attributes
            centralDirectory.appendLittleEndian(localHeaderOffset)
            centralDirectory.append(contentsOf: name)
        }

        guard let centralDirectoryOffset = UInt32(exactly: output.count),
              let centralDirectorySize = UInt32(exactly: centralDirectory.count)
        else { throw ZipError.tooLarge }
        output.append(centralDirectory)
        output.appendLittleEndian(Signature.endOfCentralDirectory)
        output.appendLittleEndian(UInt16(0)) // this disk
        output.appendLittleEndian(UInt16(0)) // disk with the central directory
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(UInt16(entries.count))
        output.appendLittleEndian(centralDirectorySize)
        output.appendLittleEndian(centralDirectoryOffset)
        output.appendLittleEndian(UInt16(0)) // comment length
        return output
    }

    // MARK: - Compression

    static func checksum(_ data: Data) -> UInt32 {
        data.withUnsafeBytes { buffer in
            UInt32(zlib.crc32(0, buffer.bindMemory(to: Bytef.self).baseAddress, uInt(buffer.count)))
        }
    }

    /// Raw DEFLATE (what ZIP calls method 8), or `nil` when compressing wouldn't make the entry smaller.
    private static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var output = Data(count: data.count)
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                // COMPRESSION_ZLIB reads and writes raw DEFLATE streams, without a zlib header.
                compression_encode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0, written < data.count else { return nil }
        output.count = written
        return output
    }

    private static func inflate(_ input: ArraySlice<UInt8>, uncompressedSize: Int, path: String) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError.malformed("Missing data for \(path)") }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBufferPointer { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!, uncompressedSize,
                    source.baseAddress!, source.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else { throw ZipError.malformed("Could not decompress \(path)") }
        return output
    }

    private enum Signature {
        static let localFileHeader: UInt32 = 0x0403_4b50
        static let centralDirectoryHeader: UInt32 = 0x0201_4b50
        static let endOfCentralDirectory: UInt32 = 0x0605_4b50
    }

    private enum Method {
        static let stored: UInt16 = 0
        static let deflated: UInt16 = 8
    }

    private enum Version {
        static let neededToExtract: UInt16 = 20 // 2.0: deflate
        static let madeBy: UInt16 = 20 // MS-DOS attribute compatibility, spec 2.0
    }

    private struct ByteReader {
        let storage: [UInt8]

        init(bytes: [UInt8]) {
            storage = bytes
        }

        func uint16(at offset: Int) throws -> UInt16 {
            let slice = try bytes(at: offset, count: 2)
            return UInt16(slice[slice.startIndex]) | UInt16(slice[slice.startIndex + 1]) << 8
        }

        func uint32(at offset: Int) throws -> UInt32 {
            let slice = try bytes(at: offset, count: 4)
            return slice.reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        }

        func bytes(at offset: Int, count: Int) throws -> ArraySlice<UInt8> {
            guard offset >= 0, count >= 0, offset <= storage.count - count else {
                throw ZipError.malformed("Unexpected end of archive")
            }
            return storage[offset..<offset + count]
        }

        func findEndOfCentralDirectory() throws -> Int {
            // The record is 22 bytes plus a comment of up to 65,535 bytes, so search backwards from the end.
            let lastCandidate = storage.count - 22
            let firstCandidate = max(0, lastCandidate - Int(UInt16.max))
            if lastCandidate >= firstCandidate {
                for offset in stride(from: lastCandidate, through: firstCandidate, by: -1) {
                    if try uint32(at: offset) == Signature.endOfCentralDirectory {
                        return offset
                    }
                }
            }
            throw ZipError.malformed("Not a ZIP archive")
        }
    }
}

enum ZipError: LocalizedError, Equatable {
    case malformed(String)
    case unsupported(String)
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .malformed(let reason): "Invalid ZIP archive: \(reason)"
        case .unsupported(let reason): "Unsupported ZIP archive: \(reason)"
        case .tooLarge: "ZIP archive is too large"
        }
    }
}

private extension Data {
    mutating func appendLittleEndian(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        appendLittleEndian(UInt16(truncatingIfNeeded: value))
        appendLittleEndian(UInt16(truncatingIfNeeded: value >> 16))
    }
}
