import SwiftUI
import AppKit

/// A menu item that runs a Swift closure — lets us build an AppKit context menu
/// from the same actions used elsewhere.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(_ title: String, image: NSImage? = nil, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        self.image = image
    }
    required init(coder: NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func fire() { handler() }
}

/// AppKit mouse handling for a result row, sitting behind the (hit-testing
/// disabled) SwiftUI row. It owns click, double-click, right-click menu, and
/// drag — the last of which SwiftUI's `.onDrag` can't do for *multiple* items,
/// which is the whole point: dragging a multi-selection drags every file.
struct ResultInteractionView: NSViewRepresentable {
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var dragItems: () -> [NSPasteboardWriting]
    var makeMenu: () -> NSMenu?

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.configure(onClick: onClick, onDoubleClick: onDoubleClick,
                       dragItems: dragItems, makeMenu: makeMenu)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.configure(onClick: onClick, onDoubleClick: onDoubleClick,
                         dragItems: dragItems, makeMenu: makeMenu)
    }

    final class InteractionView: NSView, NSDraggingSource {
        private var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
        private var onDoubleClick: () -> Void = {}
        private var dragItemsProvider: () -> [NSPasteboardWriting] = { [] }
        private var menuProvider: () -> NSMenu? = { nil }
        private var mouseDownEvent: NSEvent?
        private var didDrag = false

        func configure(onClick: @escaping (NSEvent.ModifierFlags) -> Void,
                       onDoubleClick: @escaping () -> Void,
                       dragItems: @escaping () -> [NSPasteboardWriting],
                       makeMenu: @escaping () -> NSMenu?) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
            self.dragItemsProvider = dragItems
            self.menuProvider = makeMenu
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            mouseDownEvent = event
            didDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard let down = mouseDownEvent, !didDrag else { return }
            let dx = event.locationInWindow.x - down.locationInWindow.x
            let dy = event.locationInWindow.y - down.locationInWindow.y
            guard (dx * dx + dy * dy) > 12 else { return }   // ~3.5px threshold
            let writers = dragItemsProvider()
            guard !writers.isEmpty else { return }
            didDrag = true
            let start = convert(down.locationInWindow, from: nil)
            let size = NSSize(width: 48, height: 48)
            let items: [NSDraggingItem] = writers.enumerated().map { i, writer in
                let item = NSDraggingItem(pasteboardWriter: writer)
                let origin = NSPoint(x: start.x - size.width / 2 + CGFloat(i) * 6,
                                     y: start.y - size.height / 2 - CGFloat(i) * 6)
                item.setDraggingFrame(NSRect(origin: origin, size: size),
                                      contents: Self.dragIcon(for: writer))
                return item
            }
            beginDraggingSession(with: items, event: down, source: self)
        }

        override func mouseUp(with event: NSEvent) {
            defer { mouseDownEvent = nil }
            guard !didDrag else { return }
            if event.clickCount >= 2 { onDoubleClick() }
            else { onClick(event.modifierFlags) }
        }

        override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            .copy
        }

        private static func dragIcon(for writer: NSPasteboardWriting) -> NSImage {
            if let url = writer as? NSURL {
                if url.isFileURL, let path = url.path {
                    return NSWorkspace.shared.icon(forFile: path)
                }
                return NSImage(systemSymbolName: "globe", accessibilityDescription: nil) ?? NSImage()
            }
            return NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage()
        }
    }
}
