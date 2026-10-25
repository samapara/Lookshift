import AppKit
import AVFoundation
import ApplicationServices
import LookshiftCore
import OSLog
import ServiceManagement

enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "Lookshift"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let camera = Logger(subsystem: subsystem, category: "camera")
    static let focus = Logger(subsystem: subsystem, category: "focus")
}

@MainActor
enum Permissions {
    static var camera: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }

    static func requestCamera() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    static var accessibility: Bool { AXIsProcessTrusted() }

    /// Adds Lookshift to the Accessibility list (switched off) and opens that pane.
    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openCameraSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

@MainActor
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
enum Screens {
    static func active() -> [DisplayInfo] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count))
            .filter { CGDisplayMirrorsDisplay($0) == kCGNullDirectDisplay }
            .map { DisplayInfo(id: $0, bounds: CGDisplayBounds($0), isBuiltin: CGDisplayIsBuiltin($0) != 0,
                               name: screen(for: $0)?.localizedName ?? "Display \($0)") }
            .sorted { $0.isBuiltin && !$1.isBuiltin }
    }

    static func screen(for id: DisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }
}

/// Seconds since the user last touched the keyboard or mouse. Needs no permission.
enum InputActivity {
    static var secondsSinceAnyInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    static var secondsSinceKeyPress: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
    }

    /// Seconds since the mouse or trackpad moved, clicked or scrolled.
    static var secondsSinceMouse: TimeInterval {
        [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseDragged, .scrollWheel]
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }
}

/// An NSButton that runs a closure, for building UI in code.
@MainActor
final class ActionButton: NSButton {
    var handler: (() -> Void)?
    /// Drawn as a filled Jive brand button instead of the system bezel.
    var isPrimary = false

    convenience init(_ title: String, handler: (() -> Void)? = nil) {
        self.init(frame: .zero)
        self.title = title
        self.bezelStyle = .rounded
        self.handler = handler
        self.target = self
        self.action = #selector(fire)
    }

    @objc private func fire() { handler?() }

    override func draw(_ dirtyRect: NSRect) {
        guard isPrimary else { return super.draw(dirtyRect) }
        // Same footprint as the system bezel, so rows don't shift when a button turns primary.
        let shape = bounds.insetBy(dx: 6, dy: 4)
        let path = NSBezierPath(roundedRect: shape, xRadius: 6, yRadius: 6)
        (isHighlighted ? Theme.brandStrong : Theme.brand).withAlphaComponent(isEnabled ? 1 : 0.4).setFill()
        path.fill()
        let text = NSAttributedString(string: title, attributes: [
            .foregroundColor: Theme.onBrand,
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
        ])
        let size = text.size()
        text.draw(at: NSPoint(x: shape.midX - size.width / 2, y: shape.midY - size.height / 2))
    }
}

/// A borderless panel that can take key focus, so Esc cancels calibration.
final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
