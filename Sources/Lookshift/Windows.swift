import AppKit
import ApplicationServices
import LookshiftCore

/// An on-screen window of another app.
struct WindowInfo {
    let number: CGWindowID
    let pid: pid_t
    let bounds: CGRect
}

/// Finding, raising and inspecting other apps' windows through CoreGraphics and Accessibility.
@MainActor
enum Windows {
    /// Normal windows, frontmost first. Lookshift's own windows are left out unless
    /// `includingOwn`, which hit-testing needs so it never looks "through" them.
    static func visible(includingOwn: Bool = false) -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let ownPID = getpid()
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  includingOwn || pid != ownPID,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0.01,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 80, bounds.height > 80 else { return nil }
            return WindowInfo(number: number, pid: pid, bounds: bounds)
        }
    }

    /// Activates the window's app and brings that exact window to the front.
    static func raise(_ window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.pid)?.activate()
        let app = application(window.pid)
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
              let match = windows.first(where: { frame(of: $0).map { same($0, window.bounds) } ?? false })
        else {
            Log.focus.debug("Activated app \(window.pid) without a matching window")
            return
        }
        let raiseWindow = {
            AXUIElementSetAttributeValue(match, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(match, kAXRaiseAction as CFString)
        }
        _ = raiseWindow()
        // Activation is asynchronous and may bring another of the app's windows
        // forward; raise ours again once it has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { _ = raiseWindow() }
    }

    static var focusedWindowFrame: CGRect? {
        guard let app = element(attribute(systemWide, kAXFocusedApplicationAttribute)),
              let window = element(attribute(app, kAXFocusedWindowAttribute)) else { return nil }
        return frame(of: window)
    }

    static var focusedElement: AXUIElement? {
        element(attribute(systemWide, kAXFocusedUIElementAttribute))
    }

    // MARK: - Accessibility helpers

    private static let systemWide: AXUIElement = {
        let element = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(element, 0.15)
        return element
    }()

    /// An app's Accessibility element, with a short timeout so a hung app can't stall us.
    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        return app
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ name: String) -> String? {
        attribute(element, name) as? String
    }

    static func isSettable(_ element: AXUIElement, _ name: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success && settable.boolValue
    }

    static func element(_ ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero, size = CGSize.zero
        guard let position = value(attribute(element, kAXPositionAttribute)),
              let extent = value(attribute(element, kAXSizeAttribute)),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func value(_ ref: CFTypeRef?) -> AXValue? {
        guard let ref, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        return (ref as! AXValue)
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 && abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }
}
