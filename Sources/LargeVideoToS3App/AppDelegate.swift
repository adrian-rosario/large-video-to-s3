import AppKit

/// Makes the SPM-run executable behave as a normal foreground app (Dock icon +
/// focused window), and keeps the title-bar separator hairline removed — even
/// across window moves/resizes, which otherwise let AppKit re-add it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        Self.removeSeparators()

        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
        ]
        for name in names {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { Self.removeSeparators() }
            }
        }
    }

    @MainActor
    private static func removeSeparators() {
        for window in NSApp.windows {
            window.titlebarSeparatorStyle = .none
        }
    }
}
