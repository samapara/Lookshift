import AppKit
import LookshiftCore

/// Moves keyboard focus, and optionally the cursor, to another display.
@MainActor
final class FocusSwitcher {
    var moveCursor = true
    private var lastCursor: [DisplayID: CGPoint] = [:]

    func focus(_ target: DisplayInfo, among displays: [DisplayInfo]) {
        // Never interfere with a drag or a click in progress.
        guard NSEvent.pressedMouseButtons == 0 else { return }
        let mouse = CGEvent(source: nil)?.location ?? .zero
        if let from = displays.first(where: { $0.bounds.contains(mouse) }), from.id != target.id {
            lastCursor[from.id] = mouse
        }

        var anchor: CGPoint?
        if let focused = Windows.focusedWindowFrame, target.bounds.contains(focused.center) {
            Log.focus.debug("Focus already on \(target.name)")
        } else if let window = Windows.visible().first(where: { target.bounds.contains($0.bounds.center) }) {
            Windows.raise(window)
            anchor = window.bounds.center
        }

        guard moveCursor, !target.bounds.contains(mouse) else { return }
        var point = lastCursor[target.id] ?? anchor ?? target.bounds.center
        if !target.bounds.contains(point) { point = target.bounds.center }
        CGWarpMouseCursorPosition(point)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}

/// Finds the window, or the pane inside it, under a point and gives it focus.
@MainActor
final class WindowFocuser {
    /// Also focus split panes inside a window, where the app exposes them to Accessibility.
    var paneFocus = true

    private var cachedWindows: [WindowInfo] = []
    private var cachedAt: TimeInterval = -.infinity
    private var paneElements: [String: (element: AXUIElement, pid: pid_t)] = [:]
    private var treeEnabled: Set<pid_t> = []

    private static let ownPrefix = "own:"

    /// Roles that are usually a pane: an editor, a terminal, a web view, a list.
    private static let paneRoles: Set<String> = [
        kAXTextAreaRole, "AXWebArea", kAXTableRole, kAXOutlineRole, kAXBrowserRole, kAXListRole, kAXGroupRole,
    ]

    func region(at point: CGPoint) -> Region? {
        guard let window = windows().first(where: { $0.bounds.contains(point) }) else { return nil }
        // Looking at a Lookshift window (setup, settings) keeps it in front.
        if window.pid == getpid() { return Region(id: Self.ownPrefix + "\(window.number)", frame: window.bounds) }
        if paneFocus, let pane = pane(at: point, in: window) {
            let f = pane.frame
            let id = "pane:\(window.pid):\(Int(f.minX)),\(Int(f.minY)),\(Int(f.width)),\(Int(f.height))"
            if paneElements.count > 32 { paneElements.removeAll() }
            paneElements[id] = (pane.element, window.pid)
            return Region(id: id, frame: f)
        }
        return Region(id: "window:\(window.number)", frame: window.bounds)
    }

    func focus(_ region: Region) {
        guard !region.id.hasPrefix(Self.ownPrefix), NSEvent.pressedMouseButtons == 0,
              let window = windows().first(where: { $0.bounds.contains(region.frame.center) }) else { return }
        if !(Windows.focusedWindowFrame.map { Windows.same($0, window.bounds) } ?? false) {
            Windows.raise(window)
        }
        if let pane = paneElements[region.id] {
            if let focused = Windows.focusedElement, CFEqual(focused, pane.element) { return }
            AXUIElementSetAttributeValue(pane.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            Log.focus.debug("Focused a pane in app \(pane.pid)")
        }
        cachedAt = -.infinity   // stacking order just changed
    }

    /// The window list changes slowly; reading it twice a second is plenty.
    private func windows() -> [WindowInfo] {
        let now = ProcessInfo.processInfo.systemUptime
        if now - cachedAt > 0.5 {
            cachedWindows = Windows.visible(includingOwn: true)
            cachedAt = now
        }
        return cachedWindows
    }

    /// The focusable element under the point that is smaller than its window
    /// (so it really is a pane), or nil when the window has only one pane.
    private func pane(at point: CGPoint, in window: WindowInfo) -> (element: AXUIElement, frame: CGRect)? {
        let app = Windows.application(window.pid)
        enableAccessibilityTree(app, pid: window.pid)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &hit) == .success,
              var element = hit else { return nil }

        let windowArea = window.bounds.width * window.bounds.height
        for _ in 0..<12 {
            let role = Windows.string(element, kAXRoleAttribute) ?? ""
            if role == kAXWindowRole { return nil }
            if Self.paneRoles.contains(role), Windows.isSettable(element, kAXFocusedAttribute),
               var frame = Windows.frame(of: element) {
                // Scrolling text reports its full length; the visible pane is its scroll area.
                if let parent = Windows.element(Windows.attribute(element, kAXParentAttribute)),
                   Windows.string(parent, kAXRoleAttribute) == kAXScrollAreaRole,
                   let visible = Windows.frame(of: parent) {
                    frame = visible
                }
                frame = frame.intersection(window.bounds)
                let area = frame.width * frame.height
                if area >= 0.9 * windowArea { return nil }
                if area >= 0.08 * windowArea { return (element, frame) }
            }
            guard let parent = Windows.element(Windows.attribute(element, kAXParentAttribute)) else { return nil }
            element = parent
        }
        return nil
    }

    /// Electron apps (VS Code, Slack…) only build their Accessibility tree when asked.
    private func enableAccessibilityTree(_ app: AXUIElement, pid: pid_t) {
        guard treeEnabled.insert(pid).inserted else { return }
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}
