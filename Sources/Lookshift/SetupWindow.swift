import AppKit
import AVFoundation

/// What the setup window shows. Rebuilt from live state on every refresh.
struct SetupStatus {
    enum Step { case camera, accessibility, windows, screens }

    var camera: AVAuthorizationStatus
    var accessibility: Bool
    var hasBuiltinDisplay: Bool
    /// Accuracy of the window-focus calibration for the current screens, if calibrated.
    var windowAccuracy: String?
    var monitorName: String?
    var screensCalibrated: Bool
    var usesEyes: Bool
    var isInApplicationsFolder: Bool
    var shortcut: String

    var permissionsGranted: Bool { camera == .authorized && accessibility }

    /// The step to do next, or nil when everything that can be done is done.
    var nextStep: Step? {
        if camera != .authorized { return .camera }
        if !accessibility { return .accessibility }
        if !hasBuiltinDisplay { return nil }   // calibration needs the built-in camera
        if windowAccuracy == nil { return .windows }
        if monitorName != nil && !screensCalibrated { return .screens }
        return nil
    }

    /// Every step that applies to this Mac is done, the second screen included.
    var isComplete: Bool { nextStep == nil && hasBuiltinDisplay }
}

/// The first-run guide. Each step explains why it's needed and ticks itself
/// off as soon as it's done, without restarting the app. The next step to do
/// is highlighted and answers to Return.
@MainActor
final class SetupWindowController: NSWindowController, NSWindowDelegate {
    struct Actions {
        var allowCamera: () -> Void
        var openCameraSettings: () -> Void
        var allowAccessibility: () -> Void
        var calibrateWindows: () -> Void
        var calibrateScreens: () -> Void
        var finish: () -> Void
    }

    var onClose: (() -> Void)?
    var isVisible: Bool { window?.isVisible ?? false }

    private let actions: Actions
    private let headline = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let lidNotice = Notice("Open your Mac's lid to calibrate. Lookshift uses the built-in camera, so it can't see you while the lid is closed.")
    private let locationNotice = Notice("Lookshift is running from outside your Applications folder. Quit, move it to Applications and open it from there, or macOS may forget its permissions.")
    private let cameraRow = StepRow(number: 1)
    private let accessibilityRow = StepRow(number: 2)
    private let windowsRow = StepRow(number: 3)
    private let screensRow = StepRow(number: 4)
    private let tip = NSTextField(wrappingLabelWithString: "")
    private let finishButton = ActionButton("")
    private let content = NSStackView()

    init(actions: Actions) {
        self.actions = actions
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Lookshift Setup"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.surface
        super.init(window: window)
        window.delegate = self
        build()
    }

    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    func update(_ status: SetupStatus) {
        let next = status.nextStep
        let behaviour = "Typing or using the mouse keeps focus where it is."
        if status.isComplete {
            headline.stringValue = "You're all set"
            subtitle.stringValue = status.monitorName == nil
                ? "Look at a window or pane and focus moves there. \(behaviour)"
                : "Look at a window, a pane or the other screen and focus moves there. \(behaviour)"
        } else if status.permissionsGranted && status.windowAccuracy != nil && next == .screens {
            headline.stringValue = "Almost there"
            subtitle.stringValue = "Window focus is ready. Calibrate your second screen so looking at it moves focus there too."
        } else {
            headline.stringValue = "Welcome to Lookshift"
            subtitle.stringValue = "Look at a window, pane or screen and your keyboard focus moves there. Everything runs on this Mac: video is analysed in memory and never stored or sent anywhere."
        }
        lidNotice.isHidden = status.hasBuiltinDisplay
        locationNotice.isHidden = status.isInApplicationsFolder

        switch status.camera {
        case .authorized:
            cameraRow.configure(.done, title: "Camera allowed",
                                detail: "Used only to see where your head and eyes point.")
        case .notDetermined:
            cameraRow.configure(.todo, title: "Allow camera access",
                                detail: "Used only to see where your head and eyes point. Frames are processed on this Mac and never recorded.",
                                button: "Allow Camera", next: next == .camera, action: actions.allowCamera)
        default:
            cameraRow.configure(.problem, title: "Camera access is off",
                                detail: "Turn on Lookshift under Camera in System Settings, then come back here.",
                                button: "Open Settings", next: next == .camera, action: actions.openCameraSettings)
        }

        if status.accessibility {
            accessibilityRow.configure(.done, title: "Accessibility allowed",
                                       detail: "Lookshift can bring the window you look at to the front.")
        } else {
            accessibilityRow.configure(.todo, title: "Allow Accessibility",
                                       detail: "Lets Lookshift bring the window you look at to the front. In the list that opens, switch Lookshift on.",
                                       button: "Open Settings", next: next == .accessibility, action: actions.allowAccessibility)
        }

        let canCalibrate = status.hasBuiltinDisplay && status.camera != .denied && status.camera != .restricted
        if let accuracy = status.windowAccuracy {
            windowsRow.configure(.done, title: "Window focus calibrated", detail: accuracy,
                                 button: "Recalibrate", enabled: canCalibrate, action: actions.calibrateWindows)
        } else {
            windowsRow.configure(.todo, title: "Calibrate window focus",
                                 detail: "About 25 seconds. Follow a dot around the screen with your eyes. Then the window or pane you look at gets focus.",
                                 button: "Start", enabled: canCalibrate, next: next == .windows, action: actions.calibrateWindows)
        }

        if let name = status.monitorName {
            if status.screensCalibrated {
                screensRow.configure(.done, title: status.usesEyes ? "Screens calibrated: head and eyes" : "Screens calibrated: head only",
                                     detail: "Looking at \(name) or your Mac moves focus there.",
                                     button: "Recalibrate", enabled: canCalibrate, action: actions.calibrateScreens)
            } else {
                screensRow.configure(.todo, title: "Calibrate your second screen",
                                     detail: "About 15 seconds. Cards on each screen tell you where to look, first with your head, then with just your eyes.",
                                     button: "Start", enabled: canCalibrate, next: next == .screens,
                                     action: actions.calibrateScreens)
            }
        } else {
            screensRow.configure(.optional, title: "Second screen (optional)",
                                 detail: "Connect a monitor beside your Mac to also switch between screens by looking at them.")
        }

        tip.stringValue = "Pause any time with \(status.shortcut) or from the eye icon in the menu bar."
        finishButton.title = status.isComplete ? "Done" : "Finish Later"
        finishButton.makePrimary(status.isComplete)
        window?.setContentSize(content.fittingSize)
    }

    private func build() {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        headline.font = .systemFont(ofSize: 24, weight: .semibold)
        headline.textColor = Theme.ink
        subtitle.textColor = Theme.inkMuted
        subtitle.preferredMaxLayoutWidth = 440
        let titles = NSStackView(views: [headline, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 4
        let header = NSStackView(views: [icon, titles])
        header.alignment = .top
        header.spacing = 16

        tip.textColor = Theme.inkMuted
        tip.font = .systemFont(ofSize: 12)
        tip.preferredMaxLayoutWidth = 380
        finishButton.handler = actions.finish
        let footer = NSStackView(views: [tip, NSView(), finishButton])
        footer.spacing = 12

        let rows = [cameraRow, accessibilityRow, windowsRow, screensRow]
        let steps = NSStackView(views: rows)
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 20
        steps.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let card = Card(steps)

        content.setViews([header, lidNotice, locationNotice, card, footer], in: .top)
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 20
        content.edgeInsets = NSEdgeInsets(top: 28, left: 28, bottom: 24, right: 28)
        content.widthAnchor.constraint(equalToConstant: 600).isActive = true
        for view in [lidNotice, locationNotice, card, footer] as [NSView] {
            view.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -56).isActive = true
        }
        for row in rows {
            row.widthAnchor.constraint(equalTo: steps.widthAnchor, constant: -40).isActive = true
        }
        window?.contentView = content
    }
}

/// A rounded panel that sizes to its content and paints Jive colours, which
/// follow light and dark mode because they're resolved at draw time.
@MainActor
private class Panel: NSView {
    private let fill: NSColor
    private let border: NSColor?
    private let radius: CGFloat

    init(_ content: NSView, fill: NSColor, border: NSColor?, radius: CGFloat) {
        self.fill = fill
        self.border = border
        self.radius = radius
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()
        if let border {
            border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

/// The raised card holding the steps.
@MainActor
private final class Card: Panel {
    init(_ content: NSView) {
        super.init(content, fill: Theme.surfaceRaised, border: Theme.line, radius: 12)
    }

    required init?(coder: NSCoder) { nil }
}

/// A warning shown above the steps, in Jive's warning colours.
@MainActor
private final class Notice: Panel {
    init(_ text: String) {
        let icon = NSImageView(image: NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Warning")!)
        icon.contentTintColor = Theme.warning
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(wrappingLabelWithString: text)
        label.textColor = Theme.warning
        label.preferredMaxLayoutWidth = 480
        let row = NSStackView(views: [icon, label])
        row.alignment = .top
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        super.init(row, fill: Theme.warningBackground, border: nil, radius: 8)
    }

    required init?(coder: NSCoder) { nil }
}

/// One numbered setup step: status icon, title and explanation, and an optional
/// button in a fixed-width column so the buttons of all steps line up.
@MainActor
private final class StepRow: NSStackView {
    enum State { case todo, done, problem, optional }

    private let number: Int
    private let icon = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let button = ActionButton("")

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        detailLabel.preferredMaxLayoutWidth = 330
        icon.widthAnchor.constraint(equalToConstant: 26).isActive = true
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let buttonColumn = NSView()
        buttonColumn.translatesAutoresizingMaskIntoConstraints = false
        button.translatesAutoresizingMaskIntoConstraints = false
        buttonColumn.addSubview(button)
        NSLayoutConstraint.activate([
            buttonColumn.widthAnchor.constraint(equalToConstant: 130),
            button.trailingAnchor.constraint(equalTo: buttonColumn.trailingAnchor),
            button.topAnchor.constraint(equalTo: buttonColumn.topAnchor),
            buttonColumn.heightAnchor.constraint(greaterThanOrEqualTo: button.heightAnchor),
        ])
        setViews([icon, text], in: .leading)
        setViews([buttonColumn], in: .trailing)
        alignment = .top
        spacing = 12
    }

    required init?(coder: NSCoder) { nil }

    /// `next` marks the step to do now: a filled brand number and a primary button.
    func configure(_ state: State, title: String, detail: String, button buttonTitle: String? = nil,
                   enabled: Bool = true, next: Bool = false, action: (() -> Void)? = nil) {
        switch state {
        case .done:
            icon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Done")
            icon.contentTintColor = Theme.success
        case .todo, .optional:
            icon.image = NSImage(systemSymbolName: next ? "\(number).circle.fill" : "\(number).circle",
                                 accessibilityDescription: "Step \(number)")
            icon.contentTintColor = next ? Theme.brand : Theme.lineStrong
        case .problem:
            icon.image = NSImage(systemSymbolName: "exclamationmark.circle.fill", accessibilityDescription: "Needs attention")
            icon.contentTintColor = Theme.warning
        }
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .regular)
        titleLabel.stringValue = title
        titleLabel.textColor = state == .optional ? Theme.inkMuted : Theme.ink
        detailLabel.stringValue = detail
        detailLabel.textColor = Theme.inkMuted
        button.isHidden = buttonTitle == nil
        button.title = buttonTitle ?? ""
        button.makePrimary(next && enabled)
        button.isEnabled = enabled
        button.handler = action
    }
}
