import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Optional best-effort navigation inside Messages. Apple exposes no public
/// exact-message URL, so Beacon opens the conversation first and, only after
/// the user invokes Jump to Match, uses Accessibility-authorized keystrokes to
/// search within Messages for a distinctive excerpt.
enum MessageJumpController {
    static func jumpToMatch(body: String, query: String) {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else {
            Log.write("Message jump: Accessibility permission requested; conversation opened only.")
            return
        }

        let searchText = bestSearchText(body: body, query: query)
        guard !searchText.isEmpty else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            searchWhenMessagesIsActive(searchText, attemptsRemaining: 12)
        }
    }

    private static func bestSearchText(body: String, query: String) -> String {
        let compactBody = body
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compactQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !compactBody.isEmpty else { return compactQuery }
        if !compactQuery.isEmpty,
           let range = compactBody.range(of: compactQuery, options: [.caseInsensitive, .diacriticInsensitive]) {
            let offset = compactBody.distance(from: compactBody.startIndex, to: range.lowerBound)
            let startOffset = max(0, offset - 18)
            let endOffset = min(compactBody.count, startOffset + 72)
            let start = compactBody.index(compactBody.startIndex, offsetBy: startOffset)
            let end = compactBody.index(compactBody.startIndex, offsetBy: endOffset)
            return String(compactBody[start..<end])
        }
        return String(compactBody.prefix(72))
    }

    private static func searchWhenMessagesIsActive(_ searchText: String, attemptsRemaining: Int) {
        guard let messages = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.apple.MobileSMS"
        ).first else {
            guard attemptsRemaining > 0 else {
                Log.write("Message jump: Messages did not launch; automation canceled.")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchWhenMessagesIsActive(searchText, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        if !messages.isActive {
            messages.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            guard attemptsRemaining > 0 else {
                Log.write("Message jump: Messages never became active; automation canceled.")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                searchWhenMessagesIsActive(searchText, attemptsRemaining: attemptsRemaining - 1)
            }
            return
        }

        postKey(UInt16(kVK_ANSI_F), flags: .maskCommand)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard messages.isActive else {
                Log.write("Message jump: focus changed before search; automation canceled.")
                return
            }
            type(searchText)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard messages.isActive else { return }
                postKey(UInt16(kVK_Return), flags: [])
                Log.write("Message jump: searched active conversation for \(searchText.count) characters.")
            }
        }
    }

    private static func postKey(_ keyCode: UInt16, flags: CGEventFlags) {
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(keyCode), keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private static func type(_ text: String) {
        let characters = Array(text.utf16)
        guard !characters.isEmpty,
              let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true) else { return }
        event.keyboardSetUnicodeString(stringLength: characters.count, unicodeString: characters)
        event.post(tap: .cghidEventTap)
    }
}
