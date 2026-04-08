import Foundation

public final class FileWatcher: @unchecked Sendable {
    private let watchPaths: [String]
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var timer: Timer?
    private let pollingInterval: TimeInterval

    public init(
        watchPaths: [String],
        pollingInterval: TimeInterval = 30, // 30 seconds
        onChange: @escaping @Sendable () -> Void
    ) {
        self.watchPaths = watchPaths
        self.pollingInterval = pollingInterval
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    public func start() {
        startFSEvents()
    }

    public func startPolling() {
        stopFSEvents()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.timer = Timer.scheduledTimer(
                withTimeInterval: self.pollingInterval,
                repeats: true
            ) { [weak self] _ in
                self?.onChange()
            }
        }
    }

    public func stop() {
        stopFSEvents()
        timer?.invalidate()
        timer = nil
    }

    private func startFSEvents() {
        let pathsToWatch = watchPaths as CFArray
        var context = FSEventStreamContext()
        let unsafeSelf = Unmanaged.passUnretained(self).toOpaque()
        context.info = unsafeSelf

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange()
        }

        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, // latency in seconds
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    private func stopFSEvents() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
