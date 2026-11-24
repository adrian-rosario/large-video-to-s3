import Foundation

/// Tunables for the upload engine.
public struct UploaderConfig: Sendable {
    public var partSize: Int64  // bytes per part (>= S3's 5 MiB minimum)
    public var maxConcurrentParts: Int  // bound on parallel part uploads
    public var maxRetries: Int  // per-part attempts before failing
    public var retryBaseSeconds: Double  // backoff base; 0 disables the delay (tests)

    public init(
        partSize: Int64 = 8 * 1024 * 1024,
        maxConcurrentParts: Int = 4,
        maxRetries: Int = 5,
        retryBaseSeconds: Double = 0.2
    ) {
        self.partSize = partSize
        self.maxConcurrentParts = maxConcurrentParts
        self.maxRetries = maxRetries
        self.retryBaseSeconds = retryBaseSeconds
    }

    public static let `default` = UploaderConfig()
}
