import AWSS3
import Foundation
import TransferKit

/// `TransferKit.S3Client` backed by the AWS SDK for Swift. Maps the engine's
/// small protocol onto the real multipart API and classifies SDK errors.
///
/// A struct (not an actor) so part uploads stay parallel — the SDK client is
/// built for concurrent use.
public struct AWSS3Client: TransferKit.S3Client {
    private let client: AWSS3.S3Client

    public init(region: String) throws {
        self.client = try AWSS3.S3Client(region: region)
    }

    public func createMultipartUpload(bucket: String, key: String) async throws -> String {
        do {
            let out = try await client.createMultipartUpload(
                input: CreateMultipartUploadInput(bucket: bucket, key: key))
            guard let id = out.uploadId else { throw S3Error.fatal("no uploadId returned") }
            return id
        } catch let error as S3Error {
            throw error
        } catch {
            throw Self.classify(error)
        }
    }

    public func uploadPart(
        bucket: String, key: String, uploadID: String, partNumber: Int, data: Data
    ) async throws -> String {
        do {
            let out = try await client.uploadPart(
                input: UploadPartInput(
                    body: .data(data), bucket: bucket, key: key,
                    partNumber: partNumber, uploadId: uploadID))
            guard let eTag = out.eTag else { throw S3Error.transient("no eTag for part \(partNumber)") }
            return eTag
        } catch let error as S3Error {
            throw error
        } catch {
            throw Self.classify(error)
        }
    }

    public func listParts(bucket: String, key: String, uploadID: String) async throws -> [UploadedPart] {
        do {
            let out = try await client.listParts(
                input: ListPartsInput(bucket: bucket, key: key, uploadId: uploadID))
            return (out.parts ?? []).compactMap { part in
                guard let number = part.partNumber, let eTag = part.eTag else { return nil }
                return UploadedPart(number: number, eTag: eTag)
            }
        } catch {
            throw Self.classify(error)
        }
    }

    public func completeMultipartUpload(
        bucket: String, key: String, uploadID: String, parts: [UploadedPart]
    ) async throws {
        let completed = parts.map {
            S3ClientTypes.CompletedPart(eTag: $0.eTag, partNumber: $0.number)
        }
        do {
            _ = try await client.completeMultipartUpload(
                input: CompleteMultipartUploadInput(
                    bucket: bucket, key: key,
                    multipartUpload: S3ClientTypes.CompletedMultipartUpload(parts: completed),
                    uploadId: uploadID))
        } catch {
            throw Self.classify(error)
        }
    }

    public func abortMultipartUpload(bucket: String, key: String, uploadID: String) async throws {
        do {
            _ = try await client.abortMultipartUpload(
                input: AbortMultipartUploadInput(bucket: bucket, key: key, uploadId: uploadID))
        } catch {
            throw Self.classify(error)
        }
    }

    /// Best-effort mapping of SDK errors to the engine's retry model. Refine with
    /// the SDK's modeled error types as needed.
    private static func classify(_ error: Error) -> S3Error {
        let text = "\(error)"
        if text.contains("NoSuchUpload") { return .noSuchUpload }
        // Treat the rest as transient so the engine's retry can ride out
        // throttling / 5xx / network blips; a persistent fault still fails after
        // maxRetries.
        return .transient(text)
    }
}
