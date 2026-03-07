import Foundation

final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) private var fileDescriptor: CInt = -1
    private let url: URL
    private let callback: @Sendable () -> Void

    init(url: URL, callback: @escaping @Sendable () -> Void) {
        self.url = url
        self.callback = callback
        startWatching()
    }

    private func startWatching() {
        source?.cancel()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let flags = source.data
            self.callback()
            if flags.contains(.rename) || flags.contains(.delete) {
                self.startWatching()
            }
        }

        source.setCancelHandler { [fd = fileDescriptor] in
            close(fd)
        }

        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
