import SwiftUI
import TransferKit
import UniformTypeIdentifiers

@MainActor
struct ContentView: View {
    let model: TransferListModel
    @State private var importing = false

    var body: some View {
        List(model.items) { item in
            TransferRow(item: item, model: model)
        }
        .overlay {
            if model.items.isEmpty {
                ContentUnavailableView(
                    "No Transfers",
                    systemImage: "arrow.up.circle",
                    description: Text("Add a file to upload it to S3."))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importing = true
                } label: {
                    Label("Add Files", systemImage: "plus")
                }
                .help("Add files to upload")
            }
        }
        .fileImporter(
            isPresented: $importing,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                model.addFiles(urls)
            }
        }
        .navigationTitle("Uploads")
        .toolbarBackground(.hidden, for: .windowToolbar)
        .background(WindowConfigurator())
    }
}
