import SwiftUI
import AppKit

/// A transparent region that drags the whole panel when the user presses and
/// moves within it. Used behind the header so the panel stays repositionable
/// even though window-background dragging is disabled (which it must be, so a
/// drag that starts on a result row drags the *item*, not the window).
struct WindowMoveArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { MoveView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class MoveView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
