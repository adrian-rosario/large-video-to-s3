import SwiftUI
import TransferKit

@MainActor
struct TransferRow: View {
    let item: TransferItem
    let model: TransferListModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: item.progress)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()
            if item.state == .uploading {
                ProgressView().controlSize(.small)
            }
            actionButton
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var actionButton: some View {
        switch item.state {
        case .uploading:
            Button("Pause") { model.pause(item.id) }
                .help("Pause this upload")
        case .paused, .failed:
            Button("Resume") { model.resume(item.id) }
                .help("Resume this upload")
        default:
            EmptyView()
        }
    }

    private var icon: String {
        switch item.state {
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .paused: "pause.circle"
        default: "arrow.up.circle"
        }
    }

    private var statusText: String {
        let pct = Int((item.progress * 100).rounded())
        return switch item.state {
        case .pending: "Pending"
        case .uploading:
            item.total > 0 ? "Uploading… \(item.completed)/\(item.total) parts (\(pct)%)" : "Starting…"
        case .paused: "Paused — \(pct)%"
        case .completed: "Completed"
        case .failed: "Failed — Resume to retry"
        case .aborted: "Aborted"
        }
    }
}
