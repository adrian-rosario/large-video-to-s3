import Foundation

/// Splits a file of `totalSize` bytes into S3 multipart parts of `partSize`
/// (the final part is the remainder). Pure and deterministic, so it is trivial
/// to test and gives the same plan on a resumed run.
public enum PartPlanner {
    /// S3 requires parts of at least 5 MiB (except the last) and at most 10,000 parts.
    public static let minPartSize: Int64 = 5 * 1024 * 1024
    public static let maxPartCount = 10_000

    public static func plan(totalSize: Int64, partSize: Int64) -> [TransferPart] {
        guard totalSize > 0, partSize > 0 else { return [] }

        var parts: [TransferPart] = []
        var offset: Int64 = 0
        var number = 1

        while offset < totalSize {
            let size = min(partSize, totalSize - offset)
            parts.append(TransferPart(number: number, offset: offset, size: size))
            offset += size
            number += 1
        }
        return parts
    }
}
