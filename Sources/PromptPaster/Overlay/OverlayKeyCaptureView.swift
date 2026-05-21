import AppKit
import SwiftUI

struct OverlayKeyCaptureView: NSViewRepresentable {
    let handleKeyDown: (NSEvent) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(handleKeyDown: handleKeyDown)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.handleKeyDown = handleKeyDown
        context.coordinator.view = nsView
        context.coordinator.installMonitor()
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var view: NSView?
        var handleKeyDown: (NSEvent) -> Bool
        private var monitor: Any?

        init(handleKeyDown: @escaping (NSEvent) -> Bool) {
            self.handleKeyDown = handleKeyDown
        }

        func installMonitor() {
            guard monitor == nil else {
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let view,
                      event.window === view.window,
                      view.window?.isKeyWindow == true
                else {
                    return event
                }

                return self.handleKeyDown(event) ? nil : event
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

    }
}
