//
//  KS_LocalEventMonitor.swift
//  Vendored from KeyboardShortcuts by Sindre Sorhus
//  https://github.com/sindresorhus/KeyboardShortcuts (MIT License)
//

#if os(macOS)
import AppKit

final class KS_LocalEventMonitor {
    private let events: NSEvent.EventTypeMask
    private let callback: (NSEvent) -> NSEvent?
    private var monitor: Any?

    init(events: NSEvent.EventTypeMask, callback: @escaping (NSEvent) -> NSEvent?) {
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

    deinit { stop() }
}
#endif
