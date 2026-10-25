import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = AppController()
        self.controller = controller
        controller.start()
    }

    /// Opening the app again while it runs (Finder, Spotlight, Dock) shows the
    /// setup window, so a menu-bar-only app never looks like it did nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.showSetup()
        return false
    }
}

#if DEBUG
// Developer aids, compiled into debug builds only (`swift build`). Release builds must
// not have them: another process could launch the app with these arguments and use
// its camera permission without showing any UI.
if CommandLine.arguments.contains("--print-readings") {
    // Developer aid: streams raw readings to the terminal: head turn, eyes ×2, head tilt,
    // eyes up/down ×2, face position x/y and size.
    let tracker = HeadTracker { reading in
        print(reading.map { $0.all.map { String(format: "%+.3f", $0) }.joined(separator: "  ") } ?? "no face / eyes closed")
    }
    Task {
        guard await Permissions.requestCamera() else {
            print("Camera access denied")
            exit(1)
        }
        tracker.start()
    }
    RunLoop.main.run()
}

if let index = CommandLine.arguments.firstIndex(of: "--preview-onboarding") {
    let folder = CommandLine.arguments.dropFirst(index + 1).first ?? "onboarding-preview"
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        do {
            try OnboardingPreview.render(to: URL(fileURLWithPath: folder))
            print("Wrote previews to \(folder)")
        } catch {
            print("Preview failed: \(error)")
            exit(1)
        }
    }
    exit(0)
}
#endif

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
