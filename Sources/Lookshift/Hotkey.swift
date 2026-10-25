import Carbon

/// One global hotkey through Carbon, which needs no extra permission.
@MainActor
final class Hotkey {
    private static var handler: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(handler: @escaping () -> Void) {
        Hotkey.handler = handler
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { Hotkey.handler?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
        if status != noErr { Log.app.error("Couldn't install the hotkey handler (\(status))") }
    }

    /// Registers `shortcut`, replacing any previous one. nil turns the hotkey off.
    /// Returns false when macOS refuses, usually because another app owns that combination.
    @discardableResult
    func register(_ shortcut: Shortcut?) -> Bool {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        guard let shortcut else { return true }
        let id = EventHotKeyID(signature: OSType(0x4844_4643), id: 1) // "HDFC"
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { Log.app.error("Couldn't register \(shortcut.display) (\(status))") }
        return status == noErr
    }
}
