import DiskArbitration
import Foundation

/// Watches external volumes mount/unmount via DiskArbitration and reports the
/// change as a volume path. Used to pause a transfer whose source drive is
/// pulled, and to allow resume when the drive returns.
///
/// `@unchecked Sendable`: the only mutable state is the DA session, created and
/// torn down on the main actor, and callbacks are delivered on a private queue.
public final class VolumeMonitor: @unchecked Sendable {
    public enum Event: Sendable {
        case appeared(volumePath: String)
        case disappeared(volumePath: String)
    }

    private let onEvent: @Sendable (Event) -> Void
    private let queue = DispatchQueue(label: "com.largevideotos3.volume-monitor")
    private var session: DASession?

    public init(onEvent: @escaping @Sendable (Event) -> Void) {
        self.onEvent = onEvent
    }

    public func start() {
        guard session == nil, let session = DASessionCreate(kCFAllocatorDefault) else { return }
        self.session = session
        DASessionSetDispatchQueue(session, queue)

        let context = Unmanaged.passUnretained(self).toOpaque()

        DARegisterDiskDisappearedCallback(
            session, nil,
            { disk, context in VolumeMonitor.deliver(disk, context, appeared: false) }, context)
        DARegisterDiskAppearedCallback(
            session, nil,
            { disk, context in VolumeMonitor.deliver(disk, context, appeared: true) }, context)
    }

    public func stop() {
        if let session { DASessionSetDispatchQueue(session, nil) }
        session = nil
    }

    deinit {
        // Safety net: tear down the DA session so queued callbacks can't fire
        // against a freed instance if the owner forgot to call stop().
        stop()
    }

    private static func deliver(
        _ disk: DADisk, _ context: UnsafeMutableRawPointer?, appeared: Bool
    ) {
        guard let context else { return }
        let monitor = Unmanaged<VolumeMonitor>.fromOpaque(context).takeUnretainedValue()
        guard
            let description = DADiskCopyDescription(disk) as? [String: Any],
            let volumeURL = description[kDADiskDescriptionVolumePathKey as String] as? URL
        else { return }
        let path = volumeURL.path
        monitor.onEvent(appeared ? .appeared(volumePath: path) : .disappeared(volumePath: path))
    }
}
