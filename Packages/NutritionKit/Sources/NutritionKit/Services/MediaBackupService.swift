import Foundation

public enum MediaBackupError: Error, LocalizedError, Sendable {
    case invalidArchive
    case unsupportedCompression
    case checksumMismatch(String)
    case missingBackupJSON
    case invalidFilename(String)

    public var errorDescription: String? {
        switch self {
        case .invalidArchive: "The media backup archive is invalid"
        case .unsupportedCompression: "The media backup uses an unsupported compression method"
        case .checksumMismatch(let path): "Checksum mismatch for \(path)"
        case .missingBackupJSON: "The media backup does not contain backup.json"
        case .invalidFilename(let name): "The media backup contains an invalid filename: \(name)"
        }
    }
}

public struct MediaBackupContents: Sendable {
    public let backupJSON: Data
    public let photos: [String: Data]

    public init(backupJSON: Data, photos: [String: Data]) {
        self.backupJSON = backupJSON
        self.photos = photos
    }
}

public struct MediaBackupService: Sendable {
    public init() {}

    public func make(backupJSON: Data, photos: [String: Data]) throws -> Data {
        var files: [String: Data] = ["backup.json": backupJSON]
        for (filename, data) in photos {
            guard Self.isSafeFilename(filename) else { throw MediaBackupError.invalidFilename(filename) }
            files["MealPhotos/\(filename)"] = data
        }
        return try StoredZIPArchive.write(files)
    }

    public func read(_ archive: Data) throws -> MediaBackupContents {
        let files = try StoredZIPArchive.read(archive)
        guard let backupJSON = files["backup.json"] else { throw MediaBackupError.missingBackupJSON }
        var photos: [String: Data] = [:]
        for (path, data) in files where path.hasPrefix("MealPhotos/") {
            let filename = String(path.dropFirst("MealPhotos/".count))
            guard Self.isSafeFilename(filename) else { throw MediaBackupError.invalidFilename(filename) }
            photos[filename] = data
        }
        return MediaBackupContents(backupJSON: backupJSON, photos: photos)
    }

    private static func isSafeFilename(_ filename: String) -> Bool {
        !filename.isEmpty && !filename.contains("/") && !filename.contains("\\") && filename != "." && filename != ".."
    }
}

private enum StoredZIPArchive {
    private struct Entry {
        let path: String
        let data: Data
        let crc: UInt32
        let localOffset: UInt32
    }

    static func write(_ files: [String: Data]) throws -> Data {
        var output = Data()
        var entries: [Entry] = []
        for path in files.keys.sorted() {
            guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw MediaBackupError.invalidFilename(path)
            }
            let data = files[path]!
            let name = Data(path.utf8)
            let crc = crc32(data)
            let offset = UInt32(output.count)
            output.appendUInt32(0x04034b50)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(crc)
            output.appendUInt32(UInt32(data.count))
            output.appendUInt32(UInt32(data.count))
            output.appendUInt16(UInt16(name.count))
            output.appendUInt16(0)
            output.append(name)
            output.append(data)
            entries.append(Entry(path: path, data: data, crc: crc, localOffset: offset))
        }

        let centralOffset = UInt32(output.count)
        for entry in entries {
            let name = Data(entry.path.utf8)
            output.appendUInt32(0x02014b50)
            output.appendUInt16(20)
            output.appendUInt16(20)
            output.appendUInt16(0x0800)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(entry.crc)
            output.appendUInt32(UInt32(entry.data.count))
            output.appendUInt32(UInt32(entry.data.count))
            output.appendUInt16(UInt16(name.count))
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt16(0)
            output.appendUInt32(0)
            output.appendUInt32(entry.localOffset)
            output.append(name)
        }
        let centralSize = UInt32(output.count) - centralOffset
        output.appendUInt32(0x06054b50)
        output.appendUInt16(0)
        output.appendUInt16(0)
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt16(UInt16(entries.count))
        output.appendUInt32(centralSize)
        output.appendUInt32(centralOffset)
        output.appendUInt16(0)
        return output
    }

    static func read(_ archive: Data) throws -> [String: Data] {
        guard archive.count >= 22,
              let endOffset = findEndRecord(archive) else { throw MediaBackupError.invalidArchive }
        let count = Int(archive.uint16(at: endOffset + 10))
        let centralOffset = Int(archive.uint32(at: endOffset + 16))
        guard centralOffset >= 0, centralOffset < archive.count else { throw MediaBackupError.invalidArchive }
        var cursor = centralOffset
        var result: [String: Data] = [:]
        for _ in 0..<count {
            guard cursor + 46 <= archive.count, archive.uint32(at: cursor) == 0x02014b50 else { throw MediaBackupError.invalidArchive }
            let method = archive.uint16(at: cursor + 10)
            let expectedCRC = archive.uint32(at: cursor + 16)
            let compressedSize = Int(archive.uint32(at: cursor + 20))
            let uncompressedSize = Int(archive.uint32(at: cursor + 24))
            let nameLength = Int(archive.uint16(at: cursor + 28))
            let extraLength = Int(archive.uint16(at: cursor + 30))
            let commentLength = Int(archive.uint16(at: cursor + 32))
            let localOffset = Int(archive.uint32(at: cursor + 42))
            guard method == 0 else { throw MediaBackupError.unsupportedCompression }
            guard cursor + 46 + nameLength <= archive.count else { throw MediaBackupError.invalidArchive }
            let nameData = archive.subdata(in: (cursor + 46)..<(cursor + 46 + nameLength))
            guard let path = String(data: nameData, encoding: .utf8) else { throw MediaBackupError.invalidArchive }
            guard localOffset + 30 <= archive.count, archive.uint32(at: localOffset) == 0x04034b50 else { throw MediaBackupError.invalidArchive }
            let localNameLength = Int(archive.uint16(at: localOffset + 26))
            let localExtraLength = Int(archive.uint16(at: localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= archive.count, compressedSize == uncompressedSize else { throw MediaBackupError.invalidArchive }
            let data = archive.subdata(in: dataStart..<(dataStart + compressedSize))
            guard crc32(data) == expectedCRC else { throw MediaBackupError.checksumMismatch(path) }
            result[path] = data
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return result
    }

    private static func findEndRecord(_ data: Data) -> Int? {
        guard data.count >= 22 else { return nil }
        let minimum = max(0, data.count - 65_557)
        for offset in stride(from: data.count - 22, through: minimum, by: -1) where data.uint32(at: offset) == 0x06054b50 {
            return offset
        }
        return nil
    }

    private static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 == 1 ? 0xEDB88320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
    }

    mutating func appendUInt32(_ value: UInt32) {
        append(UInt8(truncatingIfNeeded: value))
        append(UInt8(truncatingIfNeeded: value >> 8))
        append(UInt8(truncatingIfNeeded: value >> 16))
        append(UInt8(truncatingIfNeeded: value >> 24))
    }

    func uint16(at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
