import AWSS3
import Foundation
import TransferKit

/// Generates presigned S3 URLs. Background uploads send a request body from a
/// file to a URL (not through the in-process SDK client), so they need one of
/// these.
///
/// VERIFY: the exact presign API is version-specific. This uses
/// `PutObjectInput.presignURL(config:expiration:)`; adjust the config type or
/// method name if your aws-sdk-swift version differs.
public struct PresignedURLProvider: Sendable {
    private let region: String

    public init(region: String) {
        self.region = region
    }

    /// A presigned PUT URL for uploading an object directly to S3.
    public func presignPutObject(
        bucket: String, key: String, expiresIn: TimeInterval = 3600
    ) async throws -> URL {
        let config = try await S3Client.S3ClientConfiguration(region: region)
        let input = PutObjectInput(bucket: bucket, key: key)
        guard let url = try await input.presignURL(config: config, expiration: expiresIn) else {
            throw S3Error.fatal("could not presign PutObject for \(key)")
        }
        return url
    }
}
