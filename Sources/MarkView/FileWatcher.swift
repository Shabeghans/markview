import Foundation

/// Watches a file path and calls `onChange` (debounced, on the main queue) when
/// it is written, replaced or recreated. Handles editors that save atomically
/// by writing a new file and renaming it over the old one.
final class FileWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private var stopped = false

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        start(retries: 0)
    }

    deinit { stop() }

    func stop() {
        stopped = true
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func start(retries: Int) {
        guard !stopped else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File temporarily missing during an atomic save; try again shortly.
            if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.start(retries: retries - 1)
                }
            }
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let events = src.data
            if events.contains(.delete) || events.contains(.rename) {
                // The inode we watch is gone; re-attach to whatever is at the path now.
                src.cancel()
                self.source = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.start(retries: 30)
                    self?.scheduleChange()
                }
            } else {
                self.scheduleChange()
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        source = src
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.onChange()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}
