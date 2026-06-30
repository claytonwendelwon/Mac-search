import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var engine: SearchEngine
    let onClose: () -> Void

    @State private var selectedIndex: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            filterChips
            Divider()
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
                    Button {
                        engine.selectedType = type
                    } label: {
                        Label(type.title, systemImage: type.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule().fill(engine.selectedType == type
                                               ? Color.accentColor.opacity(0.25)
                                               : Color.primary.opacity(0.06))
                            )
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
            if engine.selectedType.isMessages && engine.needsFullDiskAccess {
                fullDiskAccessPrompt
            } else if engine.queryText.trimmingCharacters(in: .whitespaces).isEmpty {
                emptyState(text: emptyTitle, subtitle: emptySubtitle)
            } else if engine.results.isEmpty && !engine.isSearching {
                emptyState(text: "No results", subtitle: "Try a different name or filter.")
            } else {
                resultsList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        engine.selectedType.isMessages ? "Search your messages" : "Search your Mac"
    }

    private var emptySubtitle: String {
        engine.selectedType.isMessages
            ? "Type a word, phrase, or contact to search your iMessage & SMS history."
            : "Type a name. Use the filters to narrow by type."
    }

    private var fullDiskAccessPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Full Disk Access needed")
                .font(.system(size: 15, weight: .medium))
            Text("Click Open Settings, turn on the Beacon switch under\nFull Disk Access, then choose \u{201C}Quit & Reopen.\u{201D}")
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
                LazyVStack(spacing: 2) {
                    ForEach(Array(engine.results.enumerated()), id: \.element.id) { index, result in
                        ResultRow(result: result, isSelected: index == selectedIndex)
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
        HStack(spacing: 14) {
            if engine.selectedType.isMessages {
                hint("return", "Open in Messages")
                hint("⌘C", "Copy text")
            } else {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.03))
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
        if result.source == .message {
            openMessage(result)
            onClose()
            return
        }
        NSWorkspace.shared.open(result.url)
        onClose()
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

    private func revealSelected() {
        guard let result = selectedResult else { return }
        if result.source == .message {
            openMessage(result)
            onClose()
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
        let pb = NSPasteboard.general
        pb.clearContents()
        let value = result.source == .message ? (result.messageBody ?? "") : result.path
        pb.setString(value, forType: .string)
    }
}
