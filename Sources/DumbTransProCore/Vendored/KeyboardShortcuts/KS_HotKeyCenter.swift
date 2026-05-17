//
//  KS_HotKeyCenter.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit
import Carbon.HIToolbox

/**
Manages global keyboard shortcut registrations and event routing.

This is an internal coordinator that handles:
- The shared Carbon event handler
- Routing events to the correct `KS_HotKey` instance
- Switching between normal mode and menu mode (raw key events)
*/
@MainActor
final class KS_HotKeyCenter {
    static let shared = KS_HotKeyCenter()

    enum Mode {
        /// All hotkeys are disabled.
        case disabled

        /// Normal hotkey handling.
        case normal

        /// Menu is open — use raw key events instead of Carbon hotkeys.
        case menuOpen
    }

    private struct WeakHotKey {
        weak var value: KS_HotKey?
    }

    private var lastHotKeyId = 0
    private var hotKeys = [Int: WeakHotKey]()
    private var eventHandler: EventHandlerRef?
    private var openMenuObserver: NSObjectProtocol?
    private var closeMenuObserver: NSObjectProtocol?
    private var isEnabled = true
    private(set) var isMenuOpen = false

    // "DTPR" — matches the existing HotkeyManager signature so we share the same event target.
    private let signature: UInt32 = 0x44545052

    private let hotKeyEventTypes = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
    ]

    private let rawKeyEventTypes = [
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyDown)),
        EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyUp))
    ]

    private lazy var keyEventMonitor = KS_RunLoopLocalEventMonitor(
        events: [.keyDown, .keyUp],
        runLoopMode: .eventTracking
    ) { [weak self] event in
        guard
            let self,
            let eventRef = OpaquePointer(event.eventRef),
            handleRawKeyEvent(eventRef) == noErr
        else {
            return event
        }
        return nil
    }

    var mode: Mode = .normal {
        didSet {
            guard mode != oldValue else {
                return
            }
            updateEventHandler()
        }
    }

    private init() {
        setUpMenuTrackingObserversIfNeeded()
    }

    /// Sets whether global hotkeys are enabled and updates mode accordingly.
    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else {
            return
        }
        self.isEnabled = isEnabled
        updateMode()
    }

    /// Sets up menu tracking observers that toggle menu-open hotkey mode.
    private func setUpMenuTrackingObserversIfNeeded() {
        guard
            openMenuObserver == nil,
            closeMenuObserver == nil
        else {
            return
        }

        openMenuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.setMenuOpen(true)
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.setMenuOpen(true)
            }
        }

        closeMenuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didEndTrackingNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self?.setMenuOpen(false)
                }
                return
            }
            Task { @MainActor [weak self] in
                self?.setMenuOpen(false)
            }
        }
    }

    private func setMenuOpen(_ isMenuOpen: Bool) {
        guard self.isMenuOpen != isMenuOpen else {
            return
        }
        self.isMenuOpen = isMenuOpen
        updateMode()
    }

    private func updateMode() {
        mode = isEnabled ? (isMenuOpen ? .menuOpen : .normal) : .disabled
    }

    func nextId() -> Int {
        lastHotKeyId += 1
        return lastHotKeyId
    }

    @discardableResult
    func register(_ hotKey: KS_HotKey) -> OSStatus {
        var eventHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.carbonKeyCode),
            UInt32(hotKey.carbonModifiers),
            EventHotKeyID(signature: signature, id: UInt32(hotKey.id)),
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )

        guard status == noErr, let eventHotKey else {
            return status
        }

        hotKey.eventHotKeyRef = eventHotKey
        hotKeys[hotKey.id] = WeakHotKey(value: hotKey)
        setUpEventHandlerIfNeeded()
        updateEventHandler()

        return noErr
    }

    func unregister(_ hotKey: KS_HotKey) {
        if let eventHotKeyRef = hotKey.eventHotKeyRef {
            UnregisterEventHotKey(eventHotKeyRef)
            hotKey.eventHotKeyRef = nil
        }
        hotKeys.removeValue(forKey: hotKey.id)
    }

    private func pause(_ hotKey: KS_HotKey) {
        guard let eventHotKeyRef = hotKey.eventHotKeyRef else {
            return
        }
        UnregisterEventHotKey(eventHotKeyRef)
        hotKey.eventHotKeyRef = nil
    }

    private func resume(_ hotKey: KS_HotKey) {
        guard hotKey.eventHotKeyRef == nil else {
            return
        }

        var eventHotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotKey.carbonKeyCode),
            UInt32(hotKey.carbonModifiers),
            EventHotKeyID(signature: signature, id: UInt32(hotKey.id)),
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )

        guard status == noErr, let eventHotKey else {
            unregister(hotKey)
            hotKey.onRegistrationFailed?()
            return
        }

        hotKey.eventHotKeyRef = eventHotKey
    }

    private func pauseAllHotKeys() {
        for hotKey in hotKeys.values.compactMap(\.value) {
            pause(hotKey)
        }
    }

    private func resumeAllHotKeys() {
        for hotKey in hotKeys.values.compactMap(\.value) {
            resume(hotKey)
        }
    }

    /// Public API for HotkeyManager: temporarily unregister all active hotkeys.
    func pauseAll() { pauseAllHotKeys() }

    /// Public API for HotkeyManager: re-register all previously paused hotkeys.
    func resumeAll() { resumeAllHotKeys() }

    // MARK: - Event Handler

    private func setUpEventHandlerIfNeeded() {
        guard
            eventHandler == nil,
            let dispatcher = GetEventDispatcherTarget()
        else {
            return
        }

        var handler: EventHandlerRef?
        let error = InstallEventHandler(
            dispatcher,
            ks_carbonEventHandler,
            0,
            nil,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard
            error == noErr,
            let handler
        else {
            return
        }

        eventHandler = handler
        updateEventHandler()
    }

    private func updateEventHandler() {
        guard eventHandler != nil else {
            return
        }

        let shouldHandleHotKeys = mode == .normal
        let shouldHandleRawKeys = mode == .menuOpen

        if shouldHandleHotKeys {
            resumeAllHotKeys()
        } else {
            pauseAllHotKeys()
        }

        setHotKeyEventHandlingEnabled(shouldHandleHotKeys)
        setRawKeyEventHandlingEnabled(shouldHandleRawKeys)
    }

    private func setHotKeyEventHandlingEnabled(_ isEnabled: Bool) {
        if isEnabled {
            AddEventTypesToHandler(eventHandler, hotKeyEventTypes.count, hotKeyEventTypes)
        } else {
            RemoveEventTypesFromHandler(eventHandler, hotKeyEventTypes.count, hotKeyEventTypes)
        }
    }

    private func setRawKeyEventHandlingEnabled(_ isEnabled: Bool) {
        if #available(macOS 14, *) {
            if isEnabled {
                keyEventMonitor.start()
            } else {
                keyEventMonitor.stop()
            }
        } else if isEnabled {
            AddEventTypesToHandler(eventHandler, rawKeyEventTypes.count, rawKeyEventTypes)
        } else {
            RemoveEventTypesFromHandler(eventHandler, rawKeyEventTypes.count, rawKeyEventTypes)
        }
    }

    fileprivate func handleEvent(_ event: EventRef?) -> OSStatus {
        guard let event else {
            return OSStatus(eventNotHandledErr)
        }

        switch Int(GetEventKind(event)) {
        case kEventHotKeyPressed, kEventHotKeyReleased:
            return handleHotKeyEvent(event)
        case kEventRawKeyDown, kEventRawKeyUp:
            return handleRawKeyEvent(event)
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
        var eventHotKeyId = EventHotKeyID()
        let error = GetEventParameter(
            event,
            UInt32(kEventParamDirectObject),
            UInt32(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &eventHotKeyId
        )

        guard error == noErr else {
            return error
        }

        guard
            eventHotKeyId.signature == signature,
            let hotKey = hotKeys[Int(eventHotKeyId.id)]?.value
        else {
            return OSStatus(eventNotHandledErr)
        }

        switch Int(GetEventKind(event)) {
        case kEventHotKeyPressed:
            hotKey.onKeyDown()
            return noErr
        case kEventHotKeyReleased:
            hotKey.onKeyUp()
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func handleRawKeyEvent(_ event: EventRef) -> OSStatus {
        var eventKeyCode = UInt32()
        let keyCodeError = GetEventParameter(
            event,
            UInt32(kEventParamKeyCode),
            typeUInt32,
            nil,
            MemoryLayout<UInt32>.size,
            nil,
            &eventKeyCode
        )

        guard keyCodeError == noErr else {
            return keyCodeError
        }

        var eventKeyModifiers = UInt32()
        let keyModifiersError = GetEventParameter(
            event,
            UInt32(kEventParamKeyModifiers),
            typeUInt32,
            nil,
            MemoryLayout<UInt32>.size,
            nil,
            &eventKeyModifiers
        )

        guard keyModifiersError == noErr else {
            return keyModifiersError
        }

        let normalizedEventModifiers = normalizeModifiers(Int(eventKeyModifiers))

        guard let hotKey = hotKeys.values.lazy.compactMap(\.value).first(where: {
            $0.carbonKeyCode == Int(eventKeyCode) && normalizeModifiers($0.carbonModifiers) == normalizedEventModifiers
        }) else {
            return OSStatus(eventNotHandledErr)
        }

        switch Int(GetEventKind(event)) {
        case kEventRawKeyDown:
            hotKey.onKeyDown()
            return noErr
        case kEventRawKeyUp:
            hotKey.onKeyUp()
            return noErr
        default:
            return OSStatus(eventNotHandledErr)
        }
    }

    private func normalizeModifiers(_ carbonModifiers: Int) -> Int {
        NSEvent.ModifierFlags(carbonModifiers: carbonModifiers).carbonRepresentation
    }
}

// Global C callback for Carbon event handler
nonisolated private func ks_carbonEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else {
        return OSStatus(eventNotHandledErr)
    }

    let center = Unmanaged<KS_HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    let eventAddress = event.map { UInt(bitPattern: $0) }

    guard Thread.isMainThread else {
        assertionFailure("Carbon event callback must execute on the main thread.")
        return OSStatus(eventNotHandledErr)
    }

    return MainActor.assumeIsolated {
        center.handleEvent(eventAddress.flatMap { EventRef(bitPattern: $0) })
    }
}

// MARK: - RunLoopLocalEventMonitor (vendored dependency)

/// A local event monitor that processes events during a specific run loop mode.
/// Used by KS_HotKeyCenter for raw key event handling when a menu is open (macOS 14+).
private final class KS_RunLoopLocalEventMonitor {
    private let runLoopMode: RunLoop.Mode
    private let callback: @MainActor (NSEvent) -> NSEvent?
    private let observer: CFRunLoopObserver

    init(
        events: NSEvent.EventTypeMask,
        runLoopMode: RunLoop.Mode,
        callback: @escaping @MainActor (NSEvent) -> NSEvent?
    ) {
        self.runLoopMode = runLoopMode
        self.callback = callback

        self.observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeSources.rawValue,
            true,
            0
        ) { _, _ in
            // This observer fires on the main run loop (event-tracking mode), so
            // assuming MainActor isolation is safe.
            MainActor.assumeIsolated {
                var eventsToHandle = [NSEvent]()

                while let eventToHandle = NSApp.nextEvent(
                    matching: .any,
                    until: nil,
                    inMode: runLoopMode,
                    dequeue: true
                ) {
                    eventsToHandle.append(eventToHandle)
                }

                for eventToHandle in eventsToHandle {
                    var handledEvent: NSEvent?

                    if !events.contains(NSEvent.EventTypeMask(rawValue: 1 << eventToHandle.type.rawValue)) {
                        handledEvent = eventToHandle
                    } else if let callbackEvent = callback(eventToHandle) {
                        handledEvent = callbackEvent
                    }

                    guard let handledEvent else {
                        continue
                    }

                    NSApp.postEvent(handledEvent, atStart: false)
                }
            }
        }
    }

    deinit {
        stop()
    }

    @discardableResult
    func start() -> Self {
        CFRunLoopAddObserver(
            RunLoop.current.getCFRunLoop(),
            observer,
            CFRunLoopMode(runLoopMode.rawValue as CFString)
        )
        return self
    }

    func stop() {
        CFRunLoopRemoveObserver(
            RunLoop.current.getCFRunLoop(),
            observer,
            CFRunLoopMode(runLoopMode.rawValue as CFString)
        )
    }
}
#endif
