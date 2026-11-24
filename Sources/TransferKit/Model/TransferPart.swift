import Foundation

/// One part of a multipart upload.
///
/// Part numbers are 1-based to match the S3 multipart API. `offset`/`size`
/// describe the byte range of the source file this part covers, so a resumed
/// run can re-read exactly the right slice.
public struct TransferPart: Codable, Sendable, Identifiable, Equatable {
    public let number: Int  // 1-based S3 part number
    public let offset: Int64  // byte offset of this part in the source file
    public let size: Int64  // byte length of this part
    public var state: PartState
    public var eTag: String?  // set once S3 confirms the part

    public var id: Int { number }

    public init(
        number: Int,
        offset: Int64,
        size: Int64,
        state: PartState = .pending,
        eTag: String? = nil
    ) {
        self.number = number
        self.offset = offset
        self.size = size
        self.state = state
        self.eTag = eTag
    }
}
