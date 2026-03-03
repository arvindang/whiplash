import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var clickMonitor: Any?
    private let hotKeyManager = HotKeyManager()
    private let sessionScanner = SessionScanner()
    private let summaryProvider = SummaryProvider()
    private var scanTimer: Timer?
    private var historyWatcher: FileWatcher?
    private var geminiWatcher: FileWatcher?
    private let taskStore = TaskStore.shared

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        setupButton()
        setupPopover()
        setupHotKey()
        startSessionScanning()
    }

    private func setupButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "bolt.fill",
            accessibilityDescription: "Whiplash"
        )
        button.image?.size = NSSize(width: 16, height: 16)
        button.action = #selector(togglePopover)
        button.target = self
    }

    private func setupPopover() {
        popover.contentSize = NSSize(width: 320, height: 400)
        popover.behavior = .transient
        popover.animates = true

        let contentView = TaskListView(store: taskStore, sessionScanner: sessionScanner, summaryProvider: summaryProvider)
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupHotKey() {
        hotKeyManager.register { [weak self] in
            self?.togglePopover()
        }
    }

    private func startSessionScanning() {
        // Initial scan on startup
        performScan()

        // Watch history.jsonl for immediate detection of new Claude prompts
        let historyURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/history.jsonl")
        historyWatcher = FileWatcher(url: historyURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.performScan()
            }
        }

        // Watch Gemini projects.json for immediate detection of new Gemini sessions
        let geminiProjectsURL = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".gemini/projects.json")
        geminiWatcher = FileWatcher(url: geminiProjectsURL) { [weak self] in
            Task { @MainActor [weak self] in
                self?.performScan()
            }
        }

        // Timer-based polling at 15s for detecting process exits
        scanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.performScan()
            }
        }
    }

    private func performScan() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let sessions = await self.sessionScanner.scanForSessions()
            self.taskStore.reconcileAISessions(sessions)
        }
    }

    @objc private func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        // Capture frontmost app BEFORE showing popover (showing moves focus to Whiplash)
        let frontmostApp = NSWorkspace.shared.frontmostApplication
        taskStore.lastFrontmostPID = frontmostApp?.processIdentifier
        taskStore.lastFrontmostBundleID = frontmostApp?.bundleIdentifier

        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Monitor for clicks outside to close
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }
}
