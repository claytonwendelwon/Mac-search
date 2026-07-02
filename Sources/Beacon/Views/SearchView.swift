import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var engine: SearchEngine
    let onClose: () -> Void

    @State private var selectedIndex: Int = 0

    /// One-time onboarding hint (the global hotkey) shown until dismissed.
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome = false

    private var highlightTokens: [String] {
        engine.queryText
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            filterChips
            Divider()
            if !hasSeenWelcome { welcomeBanner }
            resultsArea
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onChange(of: engine.results) { _ in
            selectedIndex = engine.results.isEmpty ? 0 : min(selectedIndex, engine.results.count - 1)
            selectedIndex = max(0, selectedIndex)
        }
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)

            SearchField(
                text: $engine.queryText,
                focusToken: engine.focusRequestToken,
                onMoveDown: { moveSelection(1) },
                onMoveUp: { moveSelection(-1) },
                onSubmit: { openSelected() },
                onReveal: { revealSelected() },
                onPreview: { previewSelected() },
                onCopy: { copySelectedPath() },
                onCancel: { onClose() },
                onCycleFilter: { forward in cycleFilter(forward: forward) }
            )
            .frame(height: 30)

            if engine.isSearching {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FileType.allCases) { type in
                    let isSelected = engine.selectedType == type
                    // When All is active, mark the sources actually included in
                    // the blended list with a small accent dot. Clipboard and
                    // History aren't in All, so they get no dot - a visual cue
                    // that you have to filter for them.
                    let showDot = engine.selectedType == .all && type.includedInAll
                    Button {
                        engine.selectedType = type
                    } label: {
                        Label(type.title, systemImage: type.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                            .background(
                                Capsule().fill(isSelected
                                               ? Color.accentColor
                                               : Color.primary.opacity(0.06))
                            )
                            .overlay(alignment: .topTrailing) {
                                if showDot {
                                    Circle()
                                        .fill(Color.accentColor)
                                        .frame(width: 6, height: 6)
                                        .offset(x: 1, y: -1)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
        }
    }

    // MARK: - Results

    private var resultsArea: some View {
        Group {
            if engine.selectedType.needsFullDiskAccess && engine.needsFullDiskAccess {
                fullDiskAccessPrompt
            } else if !engine.results.isEmpty {
                // Clipboard mode shows recent history even with an empty query.
                resultsList
            } else if engine.queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyState(text: emptyTitle, subtitle: emptySubtitle)
            } else if !engine.isSearching {
                emptyState(text: "No results", subtitle: "Try a different name or filter.")
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// First-launch onboarding strip: teaches the one thing a new user must
    /// know (the global hotkey), then gets out of the way forever.
    private var welcomeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12))
                .foregroundStyle(Color.accentColor)
            Text("Welcome to Beacon - press")
                .font(.system(size: 12))
            Text("⌥ S")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text("anywhere to open search. It lives in your menu bar.")
                .font(.system(size: 12))
            Spacer()
            Button {
                hasSeenWelcome = true
            } label: {
                Text("Got it")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .overlay(Divider(), alignment: .bottom)
    }

    private var emptyTitle: String {
        switch engine.selectedType {
        case .messages: return "Search your messages"
        case .notes: return "Search your notes"
        case .clipboard: return "Clipboard history"
        case .history: return "Browser history"
        default: return "Search your Mac"
        }
    }

    private var emptySubtitle: String {
        switch engine.selectedType {
        case .messages: return "Type a word, phrase, or contact to search your iMessage & SMS history."
        case .notes: return "Type a word or phrase to search across all your Apple Notes."
        case .clipboard: return "Copied text will appear here. Anything you copy is searchable and ready to paste back."
        case .history: return "Search every page you've visited in Safari, Chrome, Brave, Edge, and Arc."
        default: return "Type a name. Use the filters to narrow by type."
        }
    }

    private var fullDiskAccessFeature: String {
        switch engine.selectedType {
        case .history: return "Safari history"
        case .notes: return "Notes"
        case .messages: return "Messages"
        default: return "Messages and Notes"
        }
    }

    private var fullDiskAccessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Full Disk Access needed")
                .font(.system(size: 15, weight: .medium))
            Text("Searching \(fullDiskAccessFeature) needs access. Click Open Settings,\nturn on the Beacon switch, then choose \u{201C}Quit & Reopen.\u{201D}")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open Settings") { openFullDiskAccessSettings() }
                    .buttonStyle(.borderedProminent)
                Button("Try Again") { engine.retryMessageAccess() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                        if let header = sectionHeader(at: index) {
                            Text(header)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 14)
                                .padding(.top, index == 0 ? 2 : 10)
                                .padding(.bottom, 2)
                        }
                        ResultRow(result: result, isSelected: index == selectedIndex, tokens: highlightTokens)
                            .id(index)
                            .onTapGesture(count: 2) {
                                selectedIndex = index
                                openSelected()
                            }
                            .onTapGesture {
                                selectedIndex = index
                            }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: selectedIndex) { newValue in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// In the blended All view, show a small header at each source boundary.
    private func sectionHeader(at index: Int) -> String? {
        guard engine.selectedType == .all, index < engine.results.count else { return nil }
        let source = engine.results[index].source
        if index > 0 && engine.results[index - 1].source == source { return nil }
        switch source {
        case .file: return "Files & Apps"
        case .message: return "Messages"
        case .note: return "Notes"
        case .clipboard: return "Clipboard"
        case .history: return "History"
        }
    }

    private func emptyState(text: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text(text).font(.system(size: 15, weight: .medium))
            Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if engine.selectedType == .history && engine.historySafariDenied {
                safariAccessBanner
            }
            hintsRow
        }
    }

    /// Slim, non-blocking notice in the History tab when Safari's database is
    /// locked behind Full Disk Access. Chromium results still show above it.
    private var safariAccessBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Text("Safari history needs Full Disk Access")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Open Settings") { openFullDiskAccessSettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Button("Try Again") { engine.retryMessageAccess() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Color.accentColor.opacity(0.08))
        .overlay(Divider(), alignment: .top)
    }

    private var hintsRow: some View {
        HStack(spacing: 14) {
            switch selectedResult?.source ?? .file {
            case .message:
                hint("return", "Open in Messages")
                hint("⌘C", "Copy text")
            case .note:
                hint("return", "Open in Notes")
                hint("⌘C", "Copy text")
            case .clipboard:
                hint("return", "Copy to clipboard")
                hint("⌘C", "Copy")
            case .history:
                hint("return", "Open in browser")
                hint("⌘C", "Copy link")
            case .file:
                hint("return", "Open")
                hint("⌘return", "Reveal")
                hint("⌘Y", "Preview")
                hint("⌘C", "Copy path")
            }
            Spacer()
            if !engine.results.isEmpty {
                Text("\(engine.results.count) results")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            quitButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
    }

    /// Fully quits Beacon (stops the background menu-bar process) so it can be
    /// updated or deleted. Hiding the panel with Option+S only dismisses it.
    private var quitButton: some View {
        Button { NSApp.terminate(nil) } label: {
            HStack(spacing: 3) {
                Image(systemName: "power").font(.system(size: 10, weight: .semibold))
                Text("Quit").font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help("Quit Beacon completely (stops it running in the background)")
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    // MARK: - Selection + actions

    private func moveSelection(_ delta: Int) {
        guard !engine.results.isEmpty else { return }
        let count = engine.results.count
        selectedIndex = (selectedIndex + delta + count) % count
    }

    private func cycleFilter(forward: Bool) {
        let all = FileType.allCases
        guard let current = all.firstIndex(of: engine.selectedType) else { return }
        let next = (current + (forward ? 1 : -1) + all.count) % all.count
        engine.selectedType = all[next]
    }

    private var selectedResult: SearchResult? {
        guard engine.results.indices.contains(selectedIndex) else { return nil }
        return engine.results[selectedIndex]
    }

    private func openSelected() {
        guard let result = selectedResult else { return }
        switch result.source {
        case .message:
            openMessage(result)
            onClose()
            return
        case .note:
            openNote(result)
            onClose()
            return
        case .file:
            NSWorkspace.shared.open(result.url)
            onClose()
        case .clipboard:
            ClipboardStore.shared.copyToPasteboard(result.messageBody ?? result.name)
            onClose()
        case .history:
            if let url = URL(string: result.path) { NSWorkspace.shared.open(url) }
            onClose()
        }
    }

    /// Open the conversation in Messages. If we know the contact's handle we can
    /// deep-link straight to it; otherwise just bring Messages to the front.
    private func openMessage(_ result: SearchResult) {
        if let handle = result.messageHandle, !handle.isEmpty,
           let encoded = handle.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
           let url = URL(string: "imessage://\(encoded)") {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Messages.app"))
        }
    }

    /// Navigate to the exact note via AppleScript (Notes is scriptable). Prefer
    /// the Core Data id; fall back to matching the title; finally just open Notes.
    private func openNote(_ result: SearchResult) {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Notes.app"))

        let id = (result.noteID ?? "").replacingOccurrences(of: "\"", with: "")
        let title = result.name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        var clauses = ""
        if !id.isEmpty {
            clauses += "  try\n    show note id \"\(id)\"\n    return\n  end try\n"
        }
        clauses += """
          try
            set theMatches to notes whose name is "\(title)"
            if (count of theMatches) > 0 then show item 1 of theMatches
          end try
        """

        let source = """
        tell application "Notes"
          activate
        \(clauses)
        end tell
        """

        DispatchQueue.global(qos: .userInitiated).async {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            if let err { Log.write("openNote AppleScript error: \(err)") }
        }
    }

    private func revealSelected() {
        guard let result = selectedResult else { return }
        guard result.source == .file else {
            openSelected()  // messages/notes have no Finder location
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([result.url])
        onClose()
    }

    private func previewSelected() {
        guard let result = selectedResult, result.source == .file else { return }
        QuickLookController.shared.preview(result.url)
    }

    private func copySelectedPath() {
        guard let result = selectedResult else { return }
        if result.source == .clipboard {
            ClipboardStore.shared.copyToPasteboard(result.messageBody ?? result.name)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let value: String
        switch result.source {
        case .file: value = result.path
        case .history: value = result.path   // the URL
        default: value = result.messageBody ?? ""
        }
        pb.setString(value, forType: .string)
    }
}
