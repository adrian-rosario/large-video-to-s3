import AppKit
import SwiftUI

/// Reaches the hosting `NSWindow` to apply native tweaks SwiftUI doesn't expose
/// — here, removing the title-bar separator hairline and keeping it removed
/// across view updates.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { Self.apply(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.apply(nsView.window) }
    }

    private static func apply(_ window: NSWindow?) {
        window?.titlebarSeparatorStyle = .none
    }
}
