import AppKit
import SwiftUI

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var clickMonitor: Any?
    private let hotKeyManager = HotKeyManager()
    private let processScanner = ProcessScanner()
    private var scanTimer: Timer?
    private let taskStore = TaskStore.shared

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()

        setupButton()
        setupPopover()
        setupHotKey()
        startProcessScanning()
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

        let contentView = TaskListView(store: taskStore)
        popover.contentViewController = NSHostingController(rootView: contentView)
    }

    private func setupHotKey() {
        hotKeyManager.register { [weak self] in
            self?.togglePopover()
        }
    }

    private func startProcessScanning() {
        scanTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let processes = await self.processScanner.scanForClaudeProcesses()
                for process in processes {
                    let title = process.workingDirectory.isEmpty
                        ? "Claude (pid \(process.pid))"
                        : URL(fileURLWithPath: process.workingDirectory).lastPathComponent
                    self.taskStore.addAutoDetectedTask(
                        title: title,
                        context: "Claude Code"
                    )
                }
            }
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
