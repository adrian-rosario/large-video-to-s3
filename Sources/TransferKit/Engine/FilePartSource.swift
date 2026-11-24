import Foundation

/// Reads parts from a file on disk. Opens a fresh handle per read so parts can
/// be read in parallel without sharing a seek position.
public struct FilePartSource: PartDataSource {
    private let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func read(offset: Int64, size: Int64) async throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: Int(size)) ?? Data()
    }
}
