import SwiftUI
import AppKit

/// AppKit mouse handling for a result row, sitting behind the (hit-testing
/// disabled) SwiftUI row. It owns click, double-click, right-click (opens the
/// custom cascade menu), and drag — the last of which SwiftUI's `.onDrag` can't
/// do for *multiple* items, which is the whole point: dragging a multi-selection
/// drags every file.
struct ResultInteractionView: NSViewRepresentable {
    var onClick: (NSEvent.ModifierFlags) -> Void
    var onDoubleClick: () -> Void
    var dragItems: () -> [NSPasteboardWriting]
    /// Open the context menu at the given screen point (right- or control-click).
    var onRightClick: (NSPoint) -> Void
    /// Whether this row can receive a drop (true for folders).
    var dropAccepts: () -> Bool = { false }
    /// Perform the drop of the given file URLs; `copy` is true when ⌥ is held.
    var performDrop: ([URL], Bool) -> Bool = { _, _ in false }
    /// Called as a valid drag enters/leaves, to drive the row's drop highlight.
    var dropHighlightChanged: (Bool) -> Void = { _ in }

    func makeNSView(context: Context) -> InteractionView {
        let view = InteractionView()
        view.registerForDraggedTypes([.fileURL])
        view.configure(onClick: onClick, onDoubleClick: onDoubleClick,
                       dragItems: dragItems, onRightClick: onRightClick,
                       dropAccepts: dropAccepts, performDrop: performDrop,
                       dropHighlightChanged: dropHighlightChanged)
        return view
    }

    func updateNSView(_ nsView: InteractionView, context: Context) {
        nsView.configure(onClick: onClick, onDoubleClick: onDoubleClick,
                         dragItems: dragItems, onRightClick: onRightClick,
                         dropAccepts: dropAccepts, performDrop: performDrop,
                         dropHighlightChanged: dropHighlightChanged)
    }

    final class InteractionView: NSView, NSDraggingSource {
        private var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
        private var onDoubleClick: () -> Void = {}
        private var dragItemsProvider: () -> [NSPasteboardWriting] = { [] }
        private var onRightClick: (NSPoint) -> Void = { _ in }
        private var dropAccepts: () -> Bool = { false }
        private var performDropHandler: ([URL], Bool) -> Bool = { _, _ in false }
        private var dropHighlightChanged: (Bool) -> Void = { _ in }
        private var mouseDownEvent: NSEvent?
        private var didDrag = false

        func configure(onClick: @escaping (NSEvent.ModifierFlags) -> Void,
                       onDoubleClick: @escaping () -> Void,
                       dragItems: @escaping () -> [NSPasteboardWriting],
                       onRightClick: @escaping (NSPoint) -> Void,
                       dropAccepts: @escaping () -> Bool,
                       performDrop: @escaping ([URL], Bool) -> Bool,
                       dropHighlightChanged: @escaping (Bool) -> Void) {
            self.onClick = onClick
            self.onDoubleClick = onDoubleClick
            self.dragItemsProvider = dragItems
            self.onRightClick = onRightClick
            self.dropAccepts = dropAccepts
            self.performDropHandler = performDrop
            self.dropHighlightChanged = dropHighlightChanged
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            // Control-click is a secondary click → open the context menu.
            if event.modifierFlags.contains(.control) {
                onRightClick(NSEvent.mouseLocation)
                return
            }
            mouseDownEvent = event
            didDrag = false
        }

        override func rightMouseDown(with event: NSEvent) {
            onRightClick(NSEvent.mouseLocation)
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

        func draggingSession(_ session: NSDraggingSession,
                             sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            switch context {
            case .withinApplication: return [.move, .copy]  // drop onto a folder moves (⌥ = copy)
            case .outsideApplication: return .copy           // drag out to Finder/Mail always copies
            @unknown default: return .copy
            }
        }

        // MARK: Drop destination (files dropped ONTO this row's folder)

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard dropAccepts(), hasFileURLs(sender) else { return [] }
            dropHighlightChanged(true)
            return dropOperation(sender)
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            guard dropAccepts(), hasFileURLs(sender) else { return [] }
            return dropOperation(sender)
        }

        override func draggingExited(_ sender: NSDraggingInfo?) { dropHighlightChanged(false) }
        override func draggingEnded(_ sender: NSDraggingInfo) { dropHighlightChanged(false) }

        override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
            dropAccepts() && hasFileURLs(sender)
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            dropHighlightChanged(false)
            guard let urls = fileURLs(sender), !urls.isEmpty else { return false }
            return performDropHandler(urls, NSEvent.modifierFlags.contains(.option))
        }

        private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
            sender.draggingPasteboard.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        }

        private func fileURLs(_ sender: NSDraggingInfo) -> [URL]? {
            sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        }

        private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
            if NSEvent.modifierFlags.contains(.option) { return .copy }
            return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
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
