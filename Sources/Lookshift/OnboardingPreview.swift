import AppKit
import AVFoundation

/// Developer aid: `--preview-onboarding <folder>` renders the setup window in each
/// first-run situation to PNG files, so onboarding can be reviewed without
/// resetting permissions or connecting a monitor.
@MainActor
enum OnboardingPreview {
    static func render(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let monitor = "LG ULTRAGEAR"
        let good = AppController.accuracyText(0.15)
        let base = SetupStatus(camera: .notDetermined, accessibility: false, hasBuiltinDisplay: true,
                               windowAccuracy: nil, monitorName: nil, screensCalibrated: false,
                               usesEyes: false, isInApplicationsFolder: true, shortcut: "⌃⌥⌘H")
        func with(_ change: (inout SetupStatus) -> Void) -> SetupStatus {
            var status = base
            change(&status)
            return status
        }
        let cases: [(String, SetupStatus)] = [
            ("laptop-1-fresh", base),
            ("laptop-2-from-downloads", with { $0.isInApplicationsFolder = false }),
            ("laptop-3-camera-denied", with { $0.camera = .denied }),
            ("laptop-4-permissions-done", with { $0.camera = .authorized; $0.accessibility = true }),
            ("laptop-5-all-done", with { $0.camera = .authorized; $0.accessibility = true; $0.windowAccuracy = good }),
            ("monitor-1-fresh", with { $0.monitorName = monitor }),
            ("monitor-2-permissions-done", with { $0.monitorName = monitor; $0.camera = .authorized; $0.accessibility = true }),
            ("monitor-3-windows-done", with {
                $0.monitorName = monitor; $0.camera = .authorized; $0.accessibility = true; $0.windowAccuracy = good
            }),
            ("monitor-4-all-done", with {
                $0.monitorName = monitor; $0.camera = .authorized; $0.accessibility = true
                $0.windowAccuracy = good; $0.screensCalibrated = true; $0.usesEyes = true
            }),
            ("monitor-5-lid-closed", with {
                $0.monitorName = monitor; $0.camera = .authorized; $0.accessibility = true; $0.hasBuiltinDisplay = false
            }),
        ]
        let noop = {}
        for (name, status) in cases {
            let controller = SetupWindowController(actions: .init(
                allowCamera: noop, openCameraSettings: noop, allowAccessibility: noop,
                calibrateWindows: noop, calibrateScreens: noop, finish: noop))
            controller.update(status)
            guard let view = controller.window?.contentView else { continue }
            view.layoutSubtreeIfNeeded()
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                let look = NSAppearance(named: appearance)!
                controller.window?.appearance = look
                view.layoutSubtreeIfNeeded()
                guard let content = view.bitmapImageRepForCachingDisplay(in: view.bounds),
                      let output = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: content)
                // The window background isn't part of the content view; paint it underneath.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: output)
                look.performAsCurrentDrawingAppearance {
                    Theme.surface.setFill()
                    view.bounds.fill()
                }
                content.draw(in: view.bounds, from: .zero, operation: .sourceOver, fraction: 1,
                             respectFlipped: false, hints: nil)
                NSGraphicsContext.restoreGraphicsState()
                let suffix = appearance == .aqua ? "light" : "dark"
                try output.representation(using: .png, properties: [:])?
                    .write(to: folder.appendingPathComponent("\(name)-\(suffix).png"))
            }
        }
    }
}
