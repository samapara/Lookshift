import AppKit
import LookshiftCore
import QuartzCore

/// The 9-dot calibration for window focus: a dot moves around a 3×3 grid on each
/// screen and the user follows it, so readings can be mapped to points on screen.
@MainActor
final class PointCalibrationFlow {
    enum Outcome {
        case finished([DisplayID: [PointSample]])
        case noFace
        case cancelled
    }

    private let intro: TimeInterval = 2.5
    private let move: TimeInterval = 0.45
    private let settle: TimeInterval = 0.5
    private let collect: TimeInterval = 1.3

    private let displays: [DisplayInfo]
    private var collected: [Features] = []
    private var collecting = false
    private var task: Task<Void, Never>?
    private var completion: ((Outcome) -> Void)?
    private let overlay = DotOverlay()

    init(displays: [DisplayInfo], completion: @escaping (Outcome) -> Void) {
        self.displays = displays
        self.completion = completion
        overlay.onCancel = { [weak self] in self?.cancel() }
    }

    func start() {
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
    }

    func feed(_ reading: FaceReading?) {
        if collecting, let reading { collected.append(reading.all) }
    }

    private func run() async {
        defer { overlay.close() }
        var results: [DisplayID: [PointSample]] = [:]
        do {
            for (screenIndex, display) in displays.enumerated() {
                let screenLabel = displays.count > 1 ? "Screen \(screenIndex + 1) of \(displays.count) · " : ""
                overlay.show(on: display)
                overlay.setText("Follow the dot with your eyes",
                                detail: "Look at it the way you'd look at that part of the screen. Moving your head is fine.")
                overlay.moveDot(to: PointCalibration.grid[0], duration: 0)
                try await Task.sleep(for: .seconds(intro))

                var samples: [PointSample] = []
                var missedDots = 0
                for (dotIndex, dot) in PointCalibration.grid.enumerated() {
                    overlay.setText("\(screenLabel)Dot \(dotIndex + 1) of \(PointCalibration.grid.count)", detail: nil)
                    overlay.moveDot(to: dot, duration: dotIndex == 0 ? 0 : move)
                    try await Task.sleep(for: .seconds(move + settle))
                    collected = []
                    collecting = true
                    overlay.pulse(duration: collect)
                    try await Task.sleep(for: .seconds(collect))
                    collecting = false
                    if collected.count < 4 { missedDots += 1 }
                    samples += collected.map { PointSample(target: dot, features: $0) }
                }
                guard missedDots <= 2 else {
                    finish(.noFace)
                    return
                }
                results[display.id] = samples
            }
            finish(.finished(results))
        } catch {
            finish(.cancelled)
        }
    }

    /// Closes the overlay before reporting, and reports on the next run-loop turn,
    /// so a result alert is never stuck underneath the full-screen calibration window.
    private func finish(_ outcome: Outcome) {
        collecting = false
        overlay.close()
        guard let completion else { return }
        self.completion = nil
        DispatchQueue.main.async { completion(outcome) }
    }
}

/// A dimmed full-screen overlay with one dot to follow.
@MainActor
private final class DotOverlay {
    var onCancel: (() -> Void)?

    private var panel: KeyPanel?
    private let dot = CALayer()
    private let ring = CALayer()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let dotSize: CGFloat = 22

    func show(on display: DisplayInfo) {
        close()
        let screen = Screens.screen(for: display.id) ?? NSScreen.main ?? NSScreen.screens[0]
        let panel = KeyPanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = NSColor.black.withAlphaComponent(0.82)
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.onCancel?() }

        let content = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        content.wantsLayer = true
        for layer in [ring, dot] {
            layer.removeFromSuperlayer()
            content.layer?.addSublayer(layer)
        }
        ring.bounds = CGRect(x: 0, y: 0, width: dotSize * 2.4, height: dotSize * 2.4)
        ring.cornerRadius = dotSize * 1.2
        ring.borderWidth = 2
        ring.borderColor = NSColor.white.withAlphaComponent(0.5).cgColor
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.backgroundColor = Theme.brandOnDark.cgColor

        titleLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        titleLabel.textColor = .white
        detailLabel.font = .systemFont(ofSize: 15)
        detailLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        detailLabel.alignment = .center
        detailLabel.preferredMaxLayoutWidth = 520
        let cancel = ActionButton("Cancel") { [weak self] in self?.onCancel?() }
        cancel.keyEquivalent = "\u{1b}"

        // Text sits in the band between the top and middle rows of dots.
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .centerX
        text.spacing = 6
        text.translatesAutoresizingMaskIntoConstraints = false
        cancel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(text)
        content.addSubview(cancel)
        NSLayoutConstraint.activate([
            text.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            text.centerYAnchor.constraint(equalTo: content.topAnchor, constant: screen.frame.height * 0.3),
            cancel.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -screen.frame.height * 0.2),
        ])
        panel.contentView = content
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }

    func setText(_ title: String, detail: String?) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail ?? ""
        detailLabel.isHidden = detail == nil
    }

    /// `target` is a fraction of the screen with a top-left origin.
    func moveDot(to target: CGPoint, duration: TimeInterval) {
        guard let size = panel?.contentView?.bounds.size else { return }
        let position = CGPoint(x: target.x * size.width, y: (1 - target.y) * size.height)
        CATransaction.begin()
        CATransaction.setAnimationDuration(duration)
        CATransaction.setDisableActions(duration == 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        dot.position = position
        ring.position = position
        CATransaction.commit()
    }

    /// The ring closes in on the dot while readings are taken.
    func pulse(duration: TimeInterval) {
        let shrink = CABasicAnimation(keyPath: "transform.scale")
        shrink.fromValue = 1
        shrink.toValue = 0.45
        shrink.duration = duration
        ring.add(shrink, forKey: "pulse")
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
