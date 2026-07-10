import SwiftUI
import AppKit

struct SearchView: View {
    @ObservedObject var engine: SearchEngine
    @ObservedObject private var filterLayout = FilterLayoutStore.shared
    let onClose: () -> Void
    let onEditingChanged: (Bool) -> Void

    @State private var selectedIndex: Int = 0
    @State private var draggedFilter: FileType?
    @State private var dragPointer: CGPoint?
    @State private var dragGrabOffset: CGSize = .zero
    @State private var filterFrames: [FileType: CGRect] = [:]
    @State private var showAddFilters = false
    @Environment(\.colorScheme) private var colorScheme

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
            glassDivider
            filterChips
            glassDivider
            if filterLayout.isEditing {
                editModeGuidance
            } else {
                if !hasSeenWelcome { welcomeBanner }
                resultsArea
            }
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.thinMaterial)
        .background {
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.13 : 0.38),
                    Color.white.opacity(colorScheme == .dark ? 0.055 : 0.18),
                    Color.accentColor.opacity(colorScheme == .dark ? 0.035 : 0.025)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(panelShape)
        .overlay(
            panelShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.30 : 0.78),
                            Color.white.opacity(0.08),
                            Color.primary.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .overlay(alignment: .top) {
            panelShape
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.12 : 0.42), lineWidth: 0.5)
                .blur(radius: 0.2)
                .padding(1)
                .allowsHitTesting(false)
        }
        .onChange(of: engine.results) { _ in
            selectedIndex = engine.results.isEmpty ? 0 : min(selectedIndex, engine.results.count - 1)
            selectedIndex = max(0, selectedIndex)
        }
        .onAppear { syncFilterLayout() }
        .onChange(of: filterLayout.visibleFilters) { _ in syncFilterLayout() }
        .onChange(of: filterLayout.isEditing) { editing in
            if editing {
                engine.queryText = ""
                selectedIndex = 0
            } else {
                showAddFilters = false
                draggedFilter = nil
                dragPointer = nil
                dragGrabOffset = .zero
            }
            onEditingChanged(editing)
        }
    }

    private var panelShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private var glassDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.10), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
    }

    // MARK: - Search field

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: filterLayout.isEditing ? "slider.horizontal.3" : "magnifyingglass")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(Color.secondary.opacity(0.82))

            SearchField(
                text: $engine.queryText,
                focusToken: engine.focusRequestToken,
                placeholder: filterLayout.isEditing ? "Edit your experience…" : "Search your Mac…",
                isEnabled: !filterLayout.isEditing,
                onMoveDown: { moveSelection(1) },
                onMoveUp: { moveSelection(-1) },
                onSubmit: { openSelected() },
                onReveal: { revealSelected() },
                onPreview: { previewSelected() },
                onCopy: { copySelectedPath() },
                onJump: { jumpToSelectedMessage() },
                onCancel: {
                    if filterLayout.isEditing {
                        finishEditing()
                    } else {
                        onClose()
                    }
                },
                onCycleFilter: { forward in cycleFilter(forward: forward) }
            )
            .frame(height: 34)

            if engine.isSearching {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .transition(.opacity)
            }

            if filterLayout.isEditing {
                Button {
                    showAddFilters.toggle()
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(filterLayout.hiddenFilters.isEmpty)
                .popover(isPresented: $showAddFilters, arrowEdge: .top) {
                    addFiltersPopover
                }

                Button {
                    finishEditing()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Done editing")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.06 : 0.25),
                    Color.white.opacity(colorScheme == .dark ? 0.015 : 0.06)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    // MARK: - Filter chips

    private var filterChips: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filterLayout.visibleFilters) { type in
                        let isSelected = engine.selectedType == type
                        let showDot = engine.selectedType == .all && type.includedInAll
                        ZStack(alignment: .topTrailing) {
                            if filterLayout.isEditing {
                                filterChipLabel(type, isSelected: isSelected)
                                    .contentShape(Capsule())
                            } else {
                                Button {
                                    engine.selectedType = type
                                } label: {
                                    filterChipLabel(type, isSelected: isSelected)
                                }
                                .buttonStyle(.plain)
                            }

                            if filterLayout.isEditing && type != .all {
                                Button {
                                    filterLayout.hide(type)
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, Color.red)
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -5)
                            } else if showDot {
                                Circle()
                                    .fill(Color.accentColor)
                                    .frame(width: 6.5, height: 6.5)
                                    .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 1))
                                    .offset(x: 1.5, y: -1.5)
                            }
                        }
                        .modifier(
                            FilterJiggle(
                                active: filterLayout.isEditing && type != .all && draggedFilter != type,
                                phase: Double(type.rawValue.unicodeScalars.reduce(0) { $0 + Int($1.value) }) * 0.17
                            )
                        )
                        .opacity(draggedFilter == type ? 0.001 : 1)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: FilterFramePreferenceKey.self,
                                    value: [type: proxy.frame(in: .named("filterRow"))]
                                )
                            }
                        }
                        .highPriorityGesture(
                            reorderGesture(for: type),
                            including: filterLayout.isEditing && type != .all ? .all : .none
                        )
                    }
                }
                .padding(.leading, 18)
                .padding(.trailing, 18)
                .padding(.vertical, 11)
            }

            if let type = draggedFilter, let pointer = dragPointer {
                draggedFilterPreview(type)
                    .position(
                        x: pointer.x - dragGrabOffset.width,
                        y: pointer.y - dragGrabOffset.height - 5
                    )
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
        .coordinateSpace(name: "filterRow")
        .onPreferenceChange(FilterFramePreferenceKey.self) { filterFrames = $0 }
        .frame(height: 56)
    }

    private func filterChipLabel(_ type: FileType, isSelected: Bool) -> some View {
        Label(type.title, systemImage: type.symbol)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule().fill(
                    isSelected
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.96),
                                    Color.accentColor.opacity(0.78)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        : AnyShapeStyle(.thinMaterial)
                )
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected
                            ? Color.white.opacity(0.30)
                            : Color.white.opacity(colorScheme == .dark ? 0.12 : 0.58),
                        lineWidth: 0.7
                    )
            }
            .shadow(
                color: isSelected
                    ? Color.accentColor.opacity(0.24)
                    : Color.black.opacity(colorScheme == .dark ? 0.10 : 0.06),
                radius: isSelected ? 5 : 3,
                y: 2
            )
    }

    private func draggedFilterPreview(_ type: FileType) -> some View {
        ZStack(alignment: .topTrailing) {
            filterChipLabel(type, isSelected: engine.selectedType == type)
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.red)
                .offset(x: 4, y: -5)
        }
        .scaleEffect(1.06)
        .shadow(color: Color.black.opacity(0.20), radius: 10, y: 6)
    }

    private func reorderGesture(for type: FileType) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("filterRow"))
            .onChanged { value in
                guard filterLayout.isEditing, type != .all else { return }
                if draggedFilter == nil {
                    filterLayout.beginMove()
                    draggedFilter = type
                    if let frame = filterFrames[type] {
                        dragGrabOffset = CGSize(
                            width: value.startLocation.x - frame.midX,
                            height: value.startLocation.y - frame.midY
                        )
                    }
                }
                guard draggedFilter == type else { return }
                dragPointer = value.location
                previewAdjacentMove(for: type, at: value.location.x)
            }
            .onEnded { _ in
                guard draggedFilter == type else { return }
                filterLayout.commitMove()
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                    draggedFilter = nil
                    dragPointer = nil
                    dragGrabOffset = .zero
                }
            }
    }

    private func previewAdjacentMove(for type: FileType, at pointerX: CGFloat) {
        var order = filterLayout.visibleFilters
        guard let index = order.firstIndex(of: type) else { return }
        let threshold: CGFloat = 6

        if index + 1 < order.count {
            let right = order[index + 1]
            if let frame = filterFrames[right], pointerX > frame.midX + threshold {
                order.swapAt(index, index + 1)
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.84)) {
                    filterLayout.previewOrder(order)
                }
                return
            }
        }

        if index > 1 {
            let left = order[index - 1]
            if let frame = filterFrames[left], pointerX < frame.midX - threshold {
                order.swapAt(index, index - 1)
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.84)) {
                    filterLayout.previewOrder(order)
                }
            }
        }
    }

    private var addFiltersPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add filters")
                .font(.system(size: 15, weight: .semibold))
            if filterLayout.hiddenFilters.isEmpty {
                Text("Every available filter is already shown.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filterLayout.hiddenFilters) { type in
                    Button {
                        filterLayout.add(type)
                        if filterLayout.hiddenFilters.isEmpty { showAddFilters = false }
                    } label: {
                        HStack {
                            Label(type.title, systemImage: type.symbol)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            Button("Restore Defaults") {
                filterLayout.reset()
                showAddFilters = false
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .frame(width: 220)
        .padding(16)
    }

    private var editModeGuidance: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
            Text("Edit your search")
                .font(.system(size: 20, weight: .semibold))
            Text("Remove filters you don’t use, drag them into your preferred order,\nor use Add to restore something later.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { finishEditing() }
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
        .background(.thinMaterial)
        .background(Color.accentColor.opacity(0.055))
        .overlay(glassDivider, alignment: .bottom)
    }

    private var emptyTitle: String {
        switch engine.selectedType {
        case .recents: return "Recent files"
        case .messages: return "Search your messages"
        case .notes: return "Search your notes"
        case .clipboard: return "Clipboard history"
        case .history: return "Browser history"
        case .settings: return "System Settings"
        default: return "Search your Mac"
        }
    }

    private var emptySubtitle: String {
        switch engine.selectedType {
        case .recents: return "Files you've opened or added recently appear here. Type to filter them."
        case .messages: return "Type a word, phrase, or contact to search your iMessage & SMS history."
        case .notes: return "Type a word or phrase to search across all your Apple Notes."
        case .clipboard: return "Copied text will appear here. Anything you copy is searchable and ready to paste back."
        case .history: return "Search every page you've visited in Safari, Chrome, Brave, Edge, and Arc."
        case .settings: return "Jump straight to Wi-Fi, Privacy, Displays, Keyboard, Full Disk Access, and more."
        default: return "Type a name. Use the filters to narrow by type."
        }
    }

    private var fullDiskAccessFeature: String {
        switch engine.selectedType {
        case .history: return "Safari history"
        case .notes: return "Notes"
        case .messages: return "Messages"
        case .settings: return "System Settings"
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
                        ResultRow(result: result, isSelected: index == selectedIndex,
                                  tokens: highlightTokens,
                                  showRecency: engine.selectedType == .recents)
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
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        case .settings: return "System Settings"
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
        .background(.thinMaterial)
        .background(Color.accentColor.opacity(0.055))
        .overlay(glassDivider, alignment: .top)
    }

    private var hintsRow: some View {
        HStack(spacing: 14) {
            if filterLayout.isEditing {
                Text("Hold and drag a filter to move it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                switch selectedResult?.source ?? .file {
                case .message:
                    hint("return", "Open in Messages")
                    hint("⌘J", "Jump to match")
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
                case .settings:
                    hint("return", "Open Settings")
                    hint("⌘C", "Copy link")
                case .file:
                    hint("return", "Open")
                    hint("⌘return", "Reveal")
                    hint("⌘Y", "Preview")
                    hint("⌘C", "Copy path")
                }
            }
            Spacer()
            if !filterLayout.isEditing && !engine.results.isEmpty {
                Text("\(engine.results.count) results")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            if !filterLayout.isEditing {
                filterEditButton
            }
            quitButton
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .background(Color.white.opacity(colorScheme == .dark ? 0.015 : 0.08))
        .overlay(glassDivider, alignment: .top)
    }

    private var filterEditButton: some View {
        Button {
            filterLayout.isEditing = true
        } label: {
            footerControlLabel("Edit", systemImage: "slider.horizontal.3")
        }
        .buttonStyle(.plain)
    }

    private func footerControlLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 10, weight: .semibold))
            Text(title).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.45), lineWidth: 0.5)
        )
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
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.45), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("Quit Beacon completely (stops it running in the background)")
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 6).padding(.vertical, 2.5)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.48), lineWidth: 0.5)
                )
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
        guard !filterLayout.isEditing else { return }
        let all = filterLayout.visibleFilters
        guard let current = all.firstIndex(of: engine.selectedType) else { return }
        let next = (current + (forward ? 1 : -1) + all.count) % all.count
        engine.selectedType = all[next]
    }

    private func syncFilterLayout() {
        if !filterLayout.visibleFilters.contains(engine.selectedType) {
            engine.selectedType = .all
        }
        engine.updateAllIncludedTypes(filterLayout.includedInAll)
    }

    private func finishEditing() {
        filterLayout.cancelMove()
        draggedFilter = nil
        dragPointer = nil
        dragGrabOffset = .zero
        showAddFilters = false
        filterLayout.isEditing = false
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
        case .settings:
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

    private func jumpToSelectedMessage() {
        guard let result = selectedResult, result.source == .message else { return }
        openMessage(result)
        MessageJumpController.jumpToMatch(
            body: result.messageBody ?? "",
            query: engine.queryText
        )
        onClose()
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
        case .history, .settings: value = result.path   // URL/deep link
        default: value = result.messageBody ?? ""
        }
        pb.setString(value, forType: .string)
    }
}

private struct FilterFramePreferenceKey: PreferenceKey {
    static var defaultValue: [FileType: CGRect] = [:]

    static func reduce(value: inout [FileType: CGRect], nextValue: () -> [FileType: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct FilterJiggle: ViewModifier {
    let active: Bool
    let phase: Double

    func body(content: Content) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let angle = active ? sin(time * 19 + phase) * 1.2 : 0
            content
                .rotationEffect(.degrees(angle))
                .offset(y: active ? cos(time * 19 + phase) * 0.25 : 0)
        }
    }
}
