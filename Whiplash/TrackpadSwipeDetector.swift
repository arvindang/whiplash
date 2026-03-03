import SwiftUI
import AppKit

/// Detects two-finger horizontal trackpad swipes via scroll wheel events.
/// Vertical scrolling passes through to the parent (e.g., ScrollView).
struct TrackpadSwipeDetector: NSViewRepresentable {
    @Binding var offset: CGFloat
    var threshold: CGFloat = 60
    var onSwipeLeft: () -> Void
    var onSwipeRight: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SwipeNSView {
        let view = SwipeNSView()
        view.coordinator = context.coordinator
        context.coordinator.offset = $offset
        context.coordinator.threshold = threshold
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
        return view
    }

    func updateNSView(_ nsView: SwipeNSView, context: Context) {
        context.coordinator.offset = $offset
        context.coordinator.threshold = threshold
        context.coordinator.onSwipeLeft = onSwipeLeft
        context.coordinator.onSwipeRight = onSwipeRight
    }

    @MainActor
    class Coordinator {
        var offset: Binding<CGFloat> = .constant(0)
        var threshold: CGFloat = 60
        var onSwipeLeft: (() -> Void)?
        var onSwipeRight: (() -> Void)?
    }
}

class SwipeNSView: NSView {
    @MainActor var coordinator: TrackpadSwipeDetector.Coordinator?

    private var accumulatedX: CGFloat = 0
    private var accumulatedY: CGFloat = 0
    private var isHorizontalSwipe = false
    private var directionDecided = false

    override func scrollWheel(with event: NSEvent) {
        // Only handle trackpad events (they have phase info)
        guard event.phase != [] || event.momentumPhase != [] else {
            super.scrollWheel(with: event)
            return
        }

        // Ignore momentum — action already triggered on .ended
        if event.momentumPhase != [] {
            if !isHorizontalSwipe {
                super.scrollWheel(with: event)
            }
            return
        }

        switch event.phase {
        case .began:
            accumulatedX = 0
            accumulatedY = 0
            isHorizontalSwipe = false
            directionDecided = false

        case .changed:
            accumulatedX += event.scrollingDeltaX
            accumulatedY += event.scrollingDeltaY

            // Decide direction after some movement
            if !directionDecided && (abs(accumulatedX) > 8 || abs(accumulatedY) > 8) {
                directionDecided = true
                isHorizontalSwipe = abs(accumulatedX) > abs(accumulatedY)
            }

            if isHorizontalSwipe {
                let clamped = max(-120, min(120, accumulatedX))
                coordinator?.offset.wrappedValue = clamped
            } else {
                super.scrollWheel(with: event)
            }

        case .ended, .cancelled:
            if isHorizontalSwipe {
                let t = coordinator?.threshold ?? 60
                if accumulatedX < -t {
                    coordinator?.onSwipeLeft?()
                } else if accumulatedX > t {
                    coordinator?.onSwipeRight?()
                }
                withAnimation(.spring(response: 0.3)) {
                    coordinator?.offset.wrappedValue = 0
                }
            } else {
                super.scrollWheel(with: event)
            }

        default:
            super.scrollWheel(with: event)
        }
    }
}
