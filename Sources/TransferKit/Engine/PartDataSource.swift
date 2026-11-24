import Foundation

/// Supplies the bytes for a part. Abstracting "where the data comes from" keeps
/// the engine testable without a real file (tests use `InMemoryPartSource`; the
/// app uses a file-backed source).
public protocol PartDataSource: Sendable {
    func read(offset: Int64, size: Int64) async throws -> Data
}

/// Reads parts from an in-memory blob — for tests and previews.
public struct InMemoryPartSource: PartDataSource {
    private let data: Data

    public init(_ data: Data) {
        self.data = data
    }

    public func read(offset: Int64, size: Int64) async throws -> Data {
        let start = Int(offset)
        let end = min(start + Int(size), data.count)
        guard start >= 0, start <= end else { return Data() }
        return data.subdata(in: start..<end)
    }
}
