import SwiftUI
import AppKit

/// A focused, borderless text field that forwards launcher-style key commands
/// (arrows, return, escape, tab, and Cmd-shortcuts) up to SwiftUI.
struct SearchField: NSViewRepresentable {
    @Binding var text: String
    var focusToken: Int

    var onMoveDown: () -> Void
    var onMoveUp: () -> Void
    var onSubmit: () -> Void
    var onReveal: () -> Void
    var onPreview: () -> Void
    var onCopy: () -> Void
    var onCancel: () -> Void
    var onCycleFilter: (_ forward: Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> CommandTextField {
        let field = CommandTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: 22, weight: .light)
        field.placeholderString = "Search your Mac…"
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.commandHandler = context.coordinator
        return field
    }

    func updateNSView(_ field: CommandTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        // Re-focus whenever the panel asks us to (hotkey re-open).
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                guard let window = field.window else { return }
                window.makeKey()
                window.makeFirstResponder(field)
                if let editor = field.currentEditor() as? NSTextView {
                    // Visible, blinking insertion-point caret.
                    editor.insertionPointColor = .controlAccentColor
                    editor.selectedRange = NSRange(location: field.stringValue.count, length: 0)
                }
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate, CommandTextFieldHandler {
        private let parent: SearchField
        var lastFocusToken: Int = -1

        init(_ parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        // Standard key commands routed by the field editor.
        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                parent.onMoveDown(); return true
            case #selector(NSResponder.moveUp(_:)):
                parent.onMoveUp(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel(); return true
            case #selector(NSResponder.insertTab(_:)):
                parent.onCycleFilter(true); return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onCycleFilter(false); return true
            default:
                return false
            }
        }

        // Cmd-modified shortcuts caught directly in keyDown.
        func handleCommandKey(_ characters: String) -> Bool {
            switch characters.lowercased() {
            case "y": parent.onPreview(); return true
            case "c": parent.onCopy(); return true
            case "\r": parent.onReveal(); return true
            default: return false
            }
        }
    }
}

protocol CommandTextFieldHandler: AnyObject {
    /// Return true if the Cmd-shortcut was handled.
    func handleCommandKey(_ characters: String) -> Bool
}

/// NSTextField that intercepts Command-key shortcuts before normal editing.
final class CommandTextField: NSTextField {
    weak var commandHandler: CommandTextFieldHandler?

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           commandHandler?.handleCommandKey(chars) == true {
            return
        }
        super.keyDown(with: event)
    }
}
