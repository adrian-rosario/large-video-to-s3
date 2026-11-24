import Foundation

/// Retries an async operation on retryable `S3Error`s with exponential backoff
/// and jitter. Rethrows immediately on non-retryable errors, and rethrows the
/// last error once attempts are exhausted. Honors task cancellation.
enum Retry {
    static func run<T: Sendable>(
        maxAttempts: Int,
        baseSeconds: Double,
        operation: @Sendable () async throws -> T
    ) async throws -> T {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch let error as S3Error {
                attempt += 1
                guard error.isRetryable, attempt < maxAttempts else { throw error }
                try Task.checkCancellation()
                let delay = backoffSeconds(attempt: attempt, base: baseSeconds)
                if delay > 0 {
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    /// base * 2^(attempt-1), plus up to 50% random jitter.
    static func backoffSeconds(attempt: Int, base: Double) -> Double {
        guard base > 0 else { return 0 }
        let exponential = base * pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.5)
        return exponential * (1.0 + jitter)
    }
}
