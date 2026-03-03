import AppKit
import Carbon.HIToolbox

@MainActor
final class HotKeyManager {
    private nonisolated(unsafe) var monitor: Any?

    func register(toggle: @escaping @MainActor () -> Void) {
        // ⌥⇧T — Option+Shift+T
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let optionShift: NSEvent.ModifierFlags = [.option, .shift]
            let masked = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if masked == optionShift && event.keyCode == UInt16(kVK_ANSI_T) {
                Task { @MainActor in
                    toggle()
                }
            }
        }
    }

    func unregister() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
