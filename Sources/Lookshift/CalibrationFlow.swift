import AppKit
import LookshiftCore

/// Guides the user through looking at each display, first turning the head
/// naturally and then with the eyes only, and records readings for each pose.
@MainActor
final class CalibrationFlow {
    enum Outcome {
        case finished([CalibrationSamples])
        case noFace
        case cancelled
    }

    private struct Step {
        let index: Int          // into `samples`
        let eyesOnly: Bool
        let title: String
        let detail: String
    }

    private let settle: TimeInterval = 1.5
    private let collect: TimeInterval = 2.0

    private var samples: [CalibrationSamples]
    private var steps: [Step] = []
    private var collected: [Features] = []
    private var misses = 0
    private var collecting = false
    private var task: Task<Void, Never>?
    private var completion: ((Outcome) -> Void)?
    private let prompt = CalibrationPrompt()

    init(displays: [DisplayInfo], completion: @escaping (Outcome) -> Void) {
        samples = displays.map { CalibrationSamples(display: $0) }
        self.completion = completion
        for (i, _) in displays.enumerated() {
            steps.append(Step(index: i, eyesOnly: false, title: "Look at this screen",
                              detail: "Turn your head toward it the way you normally would."))
        }
        for (i, display) in displays.enumerated() where !display.isBuiltin {
            steps.append(Step(index: i, eyesOnly: true, title: "Now just your eyes",
                              detail: "Keep your head facing the laptop and look here with your eyes only."))
        }
        if displays.count == 2, let laptop = displays.firstIndex(where: \.isBuiltin) {
            steps.append(Step(index: laptop, eyesOnly: true, title: "Head away, eyes here",
                              detail: "Turn your head toward the other screen, then look back here with your eyes only."))
        }
        prompt.onCancel = { [weak self] in self?.cancel() }
    }

    func start() {
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
    }

    func feed(_ features: Features?) {
        guard collecting else { return }
        if let features { collected.append(features) } else { misses += 1 }
    }

    private func run() async {
        defer { prompt.close() }
        do {
            for (number, step) in steps.enumerated() {
                prompt.show(on: samples[step.index].display, step: number + 1, of: steps.count,
                            title: step.title, detail: step.detail)
                collected = []
                misses = 0
                try await Task.sleep(for: .seconds(settle))

                collecting = true
                let ticks = 20
                for tick in 1...ticks {
                    try await Task.sleep(for: .seconds(collect / Double(ticks)))
                    prompt.setHolding(progress: Double(tick) / Double(ticks))
                }
                collecting = false

                guard collected.count >= 5, collected.count >= misses else {
                    finish(.noFace)
                    return
                }
                if step.eyesOnly {
                    samples[step.index].eyesOnly += collected
                } else {
                    samples[step.index].natural += collected
                }
            }
            finish(.finished(samples))
        } catch {
            finish(.cancelled)
        }
    }

    /// Closes the overlay before reporting, and reports on the next run-loop turn,
    /// so a result alert is never stuck underneath the full-screen calibration window.
    private func finish(_ outcome: Outcome) {
        collecting = false
        prompt.close()
        guard let completion else { return }
        self.completion = nil
        DispatchQueue.main.async { completion(outcome) }
    }
}

/// The card shown on the display the user should look at.
@MainActor
private final class CalibrationPrompt {
    var onCancel: (() -> Void)?

    private var panel: KeyPanel?
    private let stepLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let phaseLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()

    func show(on display: DisplayInfo, step: Int, of total: Int, title: String, detail: String) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        stepLabel.stringValue = "STEP \(step) OF \(total)"
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        phaseLabel.stringValue = "Get ready…"
        progress.doubleValue = 0

        let screen = Screens.screen(for: display.id) ?? NSScreen.main ?? NSScreen.screens[0]
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.midY - size.height / 2))
        panel.makeKeyAndOrderFront(nil)
    }

    func setHolding(progress value: Double) {
        phaseLabel.stringValue = "Hold still"
        progress.doubleValue = value
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func makePanel() -> KeyPanel {
        let size = NSSize(width: 600, height: 300)
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless],
                             backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.onCancel?() }

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 24
        background.layer?.masksToBounds = true

        stepLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        stepLabel.textColor = .secondaryLabelColor
        titleLabel.font = .systemFont(ofSize: 30, weight: .semibold)
        detailLabel.font = .systemFont(ofSize: 16)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.alignment = .center
        detailLabel.preferredMaxLayoutWidth = 480
        phaseLabel.font = .systemFont(ofSize: 14, weight: .medium)
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.style = .bar
        progress.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let cancel = ActionButton("Cancel") { [weak self] in self?.onCancel?() }
        cancel.keyEquivalent = "\u{1b}"

        let stack = NSStackView(views: [stepLabel, titleLabel, detailLabel, progress, phaseLabel, cancel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setCustomSpacing(24, after: detailLabel)
        stack.setCustomSpacing(20, after: phaseLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: background.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: background.centerYAnchor),
        ])
        panel.contentView = background
        return panel
    }
}
