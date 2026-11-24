import Foundation
import SwiftUI
import TransferKit
import TransferKitAWS

@main
struct LargeVideoToS3App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: TransferListModel?
    @State private var startupError: String?

    var body: some Scene {
        WindowGroup("Uploads") {
            Group {
                if let model {
                    ContentView(model: model)
                } else if let startupError {
                    ContentUnavailableView(
                        "Setup Needed",
                        systemImage: "exclamationmark.triangle",
                        description: Text(startupError))
                } else {
                    ProgressView().controlSize(.large)
                }
            }
            .frame(minWidth: 520, minHeight: 360)
            .task { await bootstrap() }
        }
        .windowResizability(.contentMinSize)
    }

    @MainActor
    private func bootstrap() async {
        guard model == nil, startupError == nil else { return }
        do {
            let config = try AppConfig.load()
            let store = try CoreDataTransferStore(url: Self.storeURL())
            let s3 = try AWSS3Client(region: config.region)
            let model = TransferListModel(store: store, s3: s3, config: config)
            await model.load()
            self.model = model
        } catch {
            self.startupError =
                "\(error)\n\nCheck that config.local.json exists and AWS_PROFILE is set."
        }
    }

    private static func storeURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("large-video-to-s3", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("transfers.sqlite")
    }
}
