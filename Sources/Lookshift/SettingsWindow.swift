import AppKit
import LookshiftCore
import SwiftUI

/// Live facts the Settings window shows but doesn't own.
@MainActor
final class SettingsContext: ObservableObject {
    @Published var calibrationSummary = "Not calibrated yet"
    @Published var canCalibrate = false
    @Published var windowCalibrationSummary = "Not calibrated yet"
    @Published var canCalibrateWindows = false
    @Published var openAtLogin = LoginItem.isEnabled
    @Published var shortcutProblem: String?

    var recalibrate: () -> Void = {}
    var recalibrateWindows: () -> Void = {}
    var setOpenAtLogin: (Bool) -> Void = { _ in }
    /// The global hotkey is switched off while a new one is being recorded.
    var recordingShortcut: (Bool) -> Void = { _ in }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: Settings, context: SettingsContext) {
        let host = NSHostingController(rootView: SettingsView(settings: settings, context: context))
        let window = NSWindow(contentViewController: host)
        window.title = "Lookshift Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        if !window.isVisible {
            fitOnScreen(window)
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Never taller than the screen it opens on, so the whole window, and its
    /// scrolling form, stays reachable on a small laptop display.
    private func fitOnScreen(_ window: NSWindow) {
        guard let visible = (NSScreen.main ?? window.screen)?.visibleFrame else { return }
        var frame = window.frame
        let maxHeight = visible.height - 40
        guard frame.height > maxHeight else { return }
        frame.origin.y += frame.height - maxHeight
        frame.size.height = maxHeight
        window.setFrame(frame, display: false)
    }
}

private struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var context: SettingsContext

    var body: some View {
        Form {
            Section("Switching screens") {
                SliderRow(title: "Delay before switching",
                          detail: "Quick glances shorter than this are ignored.",
                          value: $settings.dwell, range: 0.1...1.5, step: 0.05,
                          label: { "\(Int(($0 * 1000).rounded())) ms" })
                SliderRow(title: "How far to look",
                          detail: "How far toward the other screen you look before it takes over. Higher is steadier.",
                          value: switchPoint, range: 0.5...0.9, step: 0.05,
                          label: { "\(Int(($0 * 100).rounded()))%" })
                ToggleRow(title: "Move the cursor too",
                          detail: "The cursor jumps back to where you left it on that screen.",
                          isOn: $settings.moveCursor)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Screen calibration")
                        Text(context.calibrationSummary).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Calibrate…", action: context.recalibrate).disabled(!context.canCalibrate)
                }
            }

            Section("Within the same screen") {
                ToggleRow(title: "Focus the window or pane I look at",
                          detail: "Windows in every app. Split panes in apps that expose them to Accessibility, such as Xcode, Terminal and many editors.",
                          isOn: $settings.windowFocus)
                SliderRow(title: "Delay for windows and panes",
                          detail: "How long to look at one before it gets focus.",
                          value: $settings.regionDelay, range: 0.1...1.5, step: 0.05,
                          label: { "\(Int(($0 * 1000).rounded())) ms" })
                    .disabled(!settings.windowFocus)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Window focus calibration")
                        Text(context.windowCalibrationSummary).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Calibrate…", action: context.recalibrateWindows).disabled(!context.canCalibrateWindows)
                }
            }

            Section("While typing") {
                ToggleRow(title: "Wait while I'm typing",
                          detail: "Glancing at notes mid-sentence doesn't steal focus. Windows, panes and screens switch once you pause.",
                          isOn: $settings.typingGuard)
                SliderRow(title: "Typing pause",
                          detail: "How long after your last keystroke to keep waiting.",
                          value: $settings.typingPause, range: 0.5...5, step: 0.5,
                          label: { String(format: "%g s", $0) })
                    .disabled(!settings.typingGuard)
            }

            Section("Camera") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("Turn the camera off when away", selection: $settings.idleLimit) {
                        Text("After 1 minute without input").tag(60.0)
                        Text("After 2 minutes without input").tag(120.0)
                        Text("After 5 minutes without input").tag(300.0)
                        Text("Only when no face is seen").tag(0.0)
                    }
                    Text("The camera also turns off when no face is seen for 20 seconds, the screen locks or the Mac sleeps. Any key or mouse movement turns it back on.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            Section("Extras") {
                ToggleRow(title: "Show gaze dot",
                          detail: "A dot where Lookshift thinks you're looking. Teal is steady, amber is about to switch, blue is waiting for you to stop typing.",
                          isOn: $settings.showGazeDot)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause / resume shortcut")
                        if let problem = context.shortcutProblem {
                            Text(problem).font(.callout).foregroundStyle(.orange)
                        } else {
                            Text("Works from any app.").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    ShortcutRecorder(shortcut: $settings.shortcut, onRecording: context.recordingShortcut)
                }
                Toggle("Open at login", isOn: Binding(get: { context.openAtLogin }, set: { context.setOpenAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .tint(Theme.brandColor)
        // The form scrolls itself; the window starts at a comfortable height and can be resized.
        .frame(width: 540)
        .frame(minHeight: 360, idealHeight: 720)
    }

    private var switchPoint: Binding<Double> {
        Binding(get: { GazeMap.switchPoint(forHysteresis: settings.hysteresis) },
                set: { settings.hysteresis = GazeMap.hysteresis(forSwitchPoint: $0) })
    }
}

private struct SliderRow: View {
    let title: String
    let detail: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Slider(value: $value, in: range, step: step).frame(width: 150).labelsHidden()
            Text(label(value)).monospacedDigit().frame(width: 60, alignment: .trailing)
        }
    }
}

private struct ToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
    }
}

/// Click, then press the new key combination. Esc cancels.
private struct ShortcutRecorder: View {
    @Binding var shortcut: Shortcut
    let onRecording: (Bool) -> Void
    @ObservedObject private var session = RecordingSession()

    init(shortcut: Binding<Shortcut>, onRecording: @escaping (Bool) -> Void) {
        _shortcut = shortcut
        self.onRecording = onRecording
    }

    var body: some View {
        Button(session.isRecording ? "Press keys…" : shortcut.display) {
            if session.isRecording {
                session.stop()
            } else {
                session.start(onRecording: onRecording) { shortcut = $0 }
            }
        }
        .monospaced()
        .frame(minWidth: 110)
        .onDisappear { session.stop() }
    }
}

/// Listens for the next key combination while the Settings window is in front.
@MainActor
private final class RecordingSession: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var onRecording: ((Bool) -> Void)?

    func start(onRecording: @escaping (Bool) -> Void, onShortcut: @escaping (Shortcut) -> Void) {
        isRecording = true
        self.onRecording = onRecording
        onRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {             // Esc
                    self?.stop()
                } else if let shortcut = Shortcut(event: event) {
                    onShortcut(shortcut)
                    self?.stop()
                } else {
                    NSSound.beep()                   // needs ⌘, ⌃ or ⌥
                }
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecording?(false)
    }
}
