import AppKit

/// A small click-through dot showing where Lookshift thinks you're looking.
@MainActor
final class GazeDot {
    enum State {
        case steady, switching, waitingForTyping

        @MainActor var color: NSColor {
            switch self {
            case .steady: Theme.success
            case .switching: Theme.amber
            case .waitingForTyping: Theme.brand
            }
        }
    }

    private let size: CGFloat = 22
    private lazy var window: NSWindow = makeWindow()
    private lazy var dot: NSView = makeDot()

    /// Moves the dot to a point in global Quartz coordinates (top-left origin), or hides it.
    func show(at point: CGPoint?, state: State) {
        guard let point, let primary = NSScreen.screens.first else {
            hide()
            return
        }
        // Quartz measures y down from the top of the primary screen; AppKit measures up from its bottom.
        let origin = NSPoint(x: point.x - size / 2, y: primary.frame.height - point.y - size / 2)
        window.setFrameOrigin(origin)
        dot.layer?.borderColor = state.color.cgColor
        dot.layer?.backgroundColor = state.color.withAlphaComponent(0.35).cgColor
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func hide() {
        if window.isVisible { window.orderOut(nil) }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: size, height: size), styleMask: .borderless,
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.contentView = dot
        return window
    }

    private func makeDot() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.wantsLayer = true
        view.layer?.cornerRadius = size / 2
        view.layer?.borderWidth = 3
        return view
    }
}
