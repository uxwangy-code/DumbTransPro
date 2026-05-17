//
//  KS_LocalEventMonitor.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit

@MainActor
final class KS_LocalEventMonitor {
    private let events: NSEvent.EventTypeMask
    private let callback: @MainActor (NSEvent) -> NSEvent?
    private var monitor: Any?

    init(events: NSEvent.EventTypeMask, callback: @escaping @MainActor (NSEvent) -> NSEvent?) {
        self.events = events
        self.callback = callback
    }

    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: callback)
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    nonisolated func cleanUp() {
        // Called from deinit — must hop to main actor to access monitor.
        MainActor.assumeIsolated { stop() }
    }

    deinit { cleanUp() }
}
#endif
