import Foundation

final class FileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: CInt

    init(url: URL, callback: @escaping @Sendable () -> Void) {
        fileDescriptor = open(url.path, O_EVTONLY)

        guard fileDescriptor >= 0 else {
            print("FileWatcher: failed to open \(url.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler {
            callback()
        }

        source.setCancelHandler { [fileDescriptor] in
            close(fileDescriptor)
        }

        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
