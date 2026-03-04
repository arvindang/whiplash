import Foundation

/// Watches process IDs for exit using kernel-level dispatch sources.
/// Fires a callback immediately when a watched process terminates.
final class ProcessWatcher: @unchecked Sendable {
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private let lock = NSLock()
    private let onExit: @MainActor (Int32) -> Void

    init(onExit: @escaping @MainActor (Int32) -> Void) {
        self.onExit = onExit
    }

    func watchPID(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }

        guard sources[pid] == nil else { return }

        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { [weak self, onExit] in
            self?.removeSource(pid)
            Task { @MainActor in
                onExit(pid)
            }
        }
        source.setCancelHandler { /* cleanup */ }
        sources[pid] = source
        source.resume()
    }

    func stopWatching(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if let source = sources.removeValue(forKey: pid) {
            source.cancel()
        }
    }

    func stopAll() {
        lock.lock()
        defer { lock.unlock() }
        for (_, source) in sources {
            source.cancel()
        }
        sources.removeAll()
    }

    /// Sync watched PIDs to match the given set. Starts watching new PIDs, stops watching stale ones.
    func sync(to activePIDs: Set<Int32>) {
        lock.lock()
        let currentlyWatched = Set(sources.keys)
        lock.unlock()

        // Stop watching PIDs no longer active
        for pid in currentlyWatched.subtracting(activePIDs) {
            stopWatching(pid)
        }

        // Start watching new PIDs
        for pid in activePIDs.subtracting(currentlyWatched) {
            watchPID(pid)
        }
    }

    private func removeSource(_ pid: Int32) {
        lock.lock()
        defer { lock.unlock() }
        if let source = sources.removeValue(forKey: pid) {
            source.cancel()
        }
    }
}
