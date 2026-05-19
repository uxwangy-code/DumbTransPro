//
//  KS_RunLoopLocalEventMonitor.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit

/// A local event monitor that processes events during a specific run loop mode.
/// Used by KS_HotKeyCenter for raw key event handling when a menu is open (macOS 14+).
final class KS_RunLoopLocalEventMonitor {
    private let runLoopMode: RunLoop.Mode
    // ARC anchor: keeps the closure alive for CFRunLoop observer lifetime.
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
