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
    @State private var activePreview: ActivePreview?
    @State private var isLoadingPreview = false
    @State private var copiedResultID: String?
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
            if activePreview == nil {
                filterChips
                glassDivider
            }
            if let activePreview {
                previewContent(activePreview)
            } else if filterLayout.isEditing {
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
        .onExitCommand {
            if activePreview != nil {
                closePreview()
            } else if filterLayout.isEditing {
                finishEditing()
            } else {
                onClose()
            }
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
            if let activePreview {
                Image(systemName: activePreview.symbol)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(activePreview.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button {
                    closePreview()
                } label: {
                    Label("Back to search", systemImage: "chevron.backward")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            } else {
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
                    onCopy: { copySelectedItem() },
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

                if engine.isSearching || isLoadingPreview {
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
                    .popover(isPresented: $showAddFilters, arrowEdge: .bottom) {
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
        HStack(spacing: 5) {
            filterIcon(type, size: 13)
            Text(type.title)
        }
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
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(filterLayout.hiddenFilters) { type in
                            Button {
                                filterLayout.add(type)
                                engine.selectedType = type
                                if filterLayout.hiddenFilters.isEmpty { showAddFilters = false }
                            } label: {
                                HStack {
                                    filterIcon(type, size: 14)
                                    Text(type.title)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(height: min(CGFloat(filterLayout.hiddenFilters.count) * 34, 240))
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

    @ViewBuilder
    private func filterIcon(_ type: FileType, size: CGFloat) -> some View {
        switch type {
        case .word:
            OfficeSourceMark(letter: "W", color: Color(red: 0.10, green: 0.42, blue: 0.78))
                .frame(width: size, height: size)
        case .excel:
            OfficeSourceMark(letter: "X", color: Color(red: 0.06, green: 0.47, blue: 0.25))
                .frame(width: size, height: size)
        case .powerPoint:
            OfficeSourceMark(letter: "P", color: Color(red: 0.82, green: 0.27, blue: 0.13))
                .frame(width: size, height: size)
        case .mail:
            Image(nsImage: NSWorkspace.shared.icon(
                forFile: "/System/Applications/Mail.app"
            ))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        case .calendar:
            Image(nsImage: NSWorkspace.shared.icon(
                forFile: "/System/Applications/Calendar.app"
            ))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
        case .gmail:
            GmailMark()
                .frame(width: size, height: size * 0.8)
        case .googleDrive:
            GoogleDriveMark()
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        case .oneDrive:
            Image(systemName: "cloud.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(red: 0.00, green: 0.47, blue: 0.84))
                .frame(width: size, height: size)
        case .dropbox:
            DropboxMark()
                .frame(width: size, height: size)
        case .iCloudDrive:
            Image(systemName: "icloud.fill")
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(Color(red: 0.12, green: 0.55, blue: 0.96))
                .frame(width: size, height: size)
        default:
            Image(systemName: type.symbol)
                .frame(width: size, height: size)
        }
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

    @ViewBuilder
    private func previewContent(_ preview: ActivePreview) -> some View {
        switch preview {
        case .message(let thread):
            messageThreadView(thread)
        case .note(let result):
            notePreview(result)
        case .mail(let result):
            mailPreview(result)
        case .calendar(let result):
            calendarPreview(result)
        case .clipboard(let result):
            textPreview(title: result.name,
                        body: result.messageBody ?? "",
                        date: result.modified)
        }
    }

    private func messageThreadView(_ thread: MessageThreadPreview) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(thread.items) { item in
                        HStack {
                            if item.isFromMe { Spacer(minLength: 90) }
                            VStack(alignment: item.isFromMe ? .trailing : .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(item.sender)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    if item.isMatch {
                                        Text("Match")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                Text(Highlight.attributed(item.body, tokens: highlightTokens,
                                                          base: .system(size: 13),
                                                          strong: .system(size: 13, weight: .bold)))
                                    .textSelection(.enabled)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        item.isFromMe
                                            ? Color.accentColor.opacity(0.16)
                                            : Color.primary.opacity(0.07),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(item.isMatch ? Color.accentColor : .clear,
                                                    lineWidth: item.isMatch ? 1.5 : 0)
                                    )
                                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: 480, alignment: item.isFromMe ? .trailing : .leading)
                            if !item.isFromMe { Spacer(minLength: 90) }
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .onAppear {
                if let match = thread.items.first(where: \.isMatch) {
                    DispatchQueue.main.async {
                        proxy.scrollTo(match.id, anchor: .center)
                    }
                }
            }
        }
    }

    private func notePreview(_ result: SearchResult) -> some View {
        textPreview(title: result.name,
                    body: result.messageBody ?? "",
                    date: result.modified)
    }

    private func mailPreview(_ result: SearchResult) -> some View {
        let sender = result.kind.isEmpty ? "Unknown Sender" : result.kind
        let body = "From: \(sender)\n\n\(result.messageBody ?? "No message summary is available.")"
        return textPreview(title: result.name, body: body, date: result.modified)
    }

    private func calendarPreview(_ result: SearchResult) -> some View {
        let start = result.modified?.formatted(date: .long, time: .shortened) ?? "Unknown date"
        let end = result.dateAdded?.formatted(date: .long, time: .shortened) ?? ""
        let calendar = result.kind.isEmpty ? "Calendar" : result.kind
        let dateRange = end.isEmpty ? start : "\(start) – \(end)"
        let body = """
        Calendar: \(calendar)
        When: \(dateRange)

        \(result.messageBody ?? "No additional event details.")
        """
        return textPreview(title: result.name, body: body, date: nil)
    }

    private func textPreview(title: String, body: String, date: Date?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .textSelection(.enabled)
                if let date {
                    Text(date.formatted(date: .long, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Divider()
                Text(Highlight.attributed(body, tokens: highlightTokens,
                                          base: .system(size: 14),
                                          strong: .system(size: 14, weight: .bold)))
                    .textSelection(.enabled)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(24)
        }
    }

    private func showPreview(for result: SearchResult) {
        switch result.source {
        case .message:
            isLoadingPreview = true
            engine.messageThreadPreview(for: result) { preview in
                isLoadingPreview = false
                if let preview { activePreview = .message(preview) }
            }
        case .note:
            activePreview = .note(result)
        case .mail:
            activePreview = .mail(result)
        case .calendar:
            activePreview = .calendar(result)
        case .clipboard:
            activePreview = .clipboard(result)
        default:
            break
        }
    }

    private func closePreview() {
        activePreview = nil
        isLoadingPreview = false
        engine.focusRequestToken &+= 1
    }

    // MARK: - Results

    private var resultsArea: some View {
        Group {
            if let requirement = engine.selectedType.externalSourceRequirement,
               requirement.state != .ready {
                externalSourcePrompt(requirement)
            } else if engine.selectedType == .iCloudDrive && !iCloudDriveReady {
                iCloudDriveSetupPrompt
            } else if engine.selectedType.needsFullDiskAccess && engine.needsFullDiskAccess {
                fullDiskAccessPrompt
            } else if engine.selectedType.isMail && engine.mailNeedsSetup {
                mailSetupPrompt
            } else if engine.selectedType.isGmail && engine.gmailNeedsSetup {
                gmailSetupPrompt
            } else if engine.selectedType.isCalendar && engine.calendarPermission != .granted {
                calendarPermissionPrompt
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

    private func externalSourcePrompt(_ requirement: ExternalSourceRequirement) -> some View {
        VStack(spacing: 11) {
            filterIcon(engine.selectedType, size: 38)
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            if requirement.state == .notInstalled {
                Text("\(requirement.appName) isn’t installed")
                    .font(.system(size: 15, weight: .medium))
                Text("Install \(requirement.appName) and sign in to search your files with Beacon.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Install \(requirement.appName)") {
                        requirement.install()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check Again") {
                        engine.refreshForPanelShow()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            } else {
                Text("Finish setting up \(requirement.appName)")
                    .font(.system(size: 15, weight: .medium))
                Text("Open \(requirement.appName), sign in, and wait for it to appear in Finder.\nBeacon will search the account currently connected there.")
                    .font(.system(size: 12))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Open \(requirement.appName)") {
                        requirement.openApplication()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check Again") {
                        engine.refreshForPanelShow()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var iCloudDriveReady: Bool {
        FileType.iCloudDrive.pathPrefixes.contains {
            FileManager.default.fileExists(atPath: $0)
        }
    }

    private var iCloudDriveSetupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "icloud.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color(red: 0.12, green: 0.55, blue: 0.96))
            Text("Turn on iCloud Drive")
                .font(.system(size: 15, weight: .medium))
            Text("Enable iCloud Drive in System Settings and let it appear in Finder.\nBeacon will search the Apple Account currently connected to this Mac.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open iCloud Settings") {
                    if let url = URL(
                        string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    engine.refreshForPanelShow()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var mailSetupPrompt: some View {
        VStack(spacing: 10) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Set up Apple Mail")
                .font(.system(size: 15, weight: .medium))
            Text("Add or sign into an account in Mail, then return to Beacon.\nBeacon searches every account currently connected there.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open Mail") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Mail.app")
                    )
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    engine.retryMessageAccess()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var gmailSetupPrompt: some View {
        VStack(spacing: 10) {
            GmailMark()
                .frame(width: 34, height: 27)
            Text("Connect Gmail to Apple Mail")
                .font(.system(size: 15, weight: .medium))
            Text("Add your Gmail or Google Workspace account in Mail first.\nBeacon will then search that account locally—no Google API login required.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Open Mail") {
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Mail.app")
                    )
                }
                .buttonStyle(.borderedProminent)
                Button("Check Again") {
                    engine.retryMessageAccess()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private var calendarPermissionPrompt: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(
                forFile: "/System/Applications/Calendar.app"
            ))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 36)
            Text(engine.calendarPermission == .notDetermined
                 ? "Allow Calendar access"
                 : "Calendar access is off")
                .font(.system(size: 15, weight: .medium))
            Text("Beacon reads event titles, dates, locations, and notes locally.\nYour calendar data never leaves this Mac.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if engine.calendarPermission == .notDetermined {
                Button("Allow Calendar Access") {
                    engine.requestCalendarAccess()
                }
                .buttonStyle(.borderedProminent)
            } else {
                HStack(spacing: 8) {
                    Button("Open Settings") {
                        if let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Check Again") {
                        engine.refreshCalendarAccess()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
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
        case .mail: return "Search your mail"
        case .gmail: return "Search Gmail"
        case .calendar: return "Search your calendar"
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
        case .mail: return "Search subjects, senders, and message summaries across every account in Apple Mail."
        case .gmail: return "Search the Gmail and Google Workspace accounts connected to Apple Mail."
        case .calendar: return "Search event titles, locations, notes, and calendar names."
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
        case .mail: return "Apple Mail"
        case .gmail: return "Gmail"
        case .calendar: return "Calendar"
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
                                if result.source == .message
                                    || result.source == .note
                                    || result.source == .mail
                                    || result.source == .calendar
                                    || result.source == .clipboard {
                                    showPreview(for: result)
                                } else if result.source == .file
                                            && !result.isFolder && !result.isApp {
                                    QuickLookController.shared.preview(result.url)
                                } else {
                                    openSelected()
                                }
                            }
                            .onTapGesture {
                                selectedIndex = index
                            }
                    }
                    if engine.canLoadMore || engine.isLoadingMore {
                        HStack {
                            Spacer()
                            if engine.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Loading more…")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .frame(height: 36)
                        .id("load-more-\(engine.results.count)-\(engine.isLoadingMore)")
                        .onAppear {
                            engine.loadMore()
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
        case .mail: return "Mail"
        case .calendar: return "Calendar"
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
        Group {
            if let activePreview {
                previewFooter(activePreview)
            } else {
                VStack(spacing: 0) {
                    if engine.selectedType == .history && engine.historySafariDenied {
                        safariAccessBanner
                    }
                    hintsRow
                }
            }
        }
    }

    private func previewFooter(_ preview: ActivePreview) -> some View {
        HStack(spacing: 12) {
            Button {
                closePreview()
            } label: {
                Label("Back", systemImage: "chevron.backward")
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                let body: String
                switch preview {
                case .message(let thread): body = thread.result.messageBody ?? ""
                case .note(let result), .mail(let result),
                     .calendar(let result), .clipboard(let result):
                    body = result.messageBody ?? ""
                }
                ClipboardStore.shared.copyToPasteboard(body)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.plain)

            switch preview {
            case .message(let thread):
                Button {
                    openMessage(thread.result)
                    onClose()
                } label: {
                    Label("Open Conversation", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            case .note(let result):
                Button {
                    openNote(result)
                    onClose()
                } label: {
                    Label("Open in Notes", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            case .mail(let result):
                Button {
                    openMail(result)
                    onClose()
                } label: {
                    Label("Open in Mail", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            case .calendar(let result):
                Button {
                    openCalendar(result)
                    onClose()
                } label: {
                    Label("Open Calendar", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            case .clipboard:
                EmptyView()
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .overlay(glassDivider, alignment: .top)
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
                    hint("double-click", "Preview thread")
                    hint("⌘C", "Copy text")
                case .note:
                    hint("return", "Open in Notes")
                    hint("double-click", "Preview note")
                    hint("⌘C", "Copy text")
                case .mail:
                    hint("return", "Open in Mail")
                    hint("double-click", "Open message")
                    hint("⌘C", "Copy summary")
                case .calendar:
                    hint("return", "Open Calendar")
                    hint("double-click", "Preview event")
                    hint("⌘C", "Copy details")
                case .clipboard:
                    hint("return", "Copy to clipboard")
                    hint("double-click", "Preview text")
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
                    hint("⌘C", copiedResultID == selectedResult?.id ? "Copied" : "Copy file")
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
        case .mail:
            openMail(result)
            onClose()
            return
        case .calendar:
            openCalendar(result)
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

    private func openMail(_ result: SearchResult) {
        if let rawID = result.mailMessageID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawID.isEmpty {
            let bareID = rawID.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            var components = URLComponents()
            components.scheme = "message"
            components.host = "<\(bareID)>"
            if let url = components.url {
                NSWorkspace.shared.open(url)
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
    }

    private func openCalendar(_ result: SearchResult) {
        NSWorkspace.shared.open(
            URL(fileURLWithPath: "/System/Applications/Calendar.app")
        )
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

    private func copySelectedItem() {
        guard let result = selectedResult else { return }
        if result.source == .clipboard {
            ClipboardStore.shared.copyToPasteboard(result.messageBody ?? result.name)
            showCopyFeedback(for: result.id)
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        let copied: Bool
        if result.source == .file {
            let item = NSPasteboardItem()
            item.setString(result.url.absoluteString, forType: .fileURL)
            item.setString(result.path, forType: .string)
            copied = pb.writeObjects([item])
        } else {
            let value: String
            switch result.source {
            case .history, .settings: value = result.path
            default: value = result.messageBody ?? ""
            }
            copied = pb.setString(value, forType: .string)
        }
        if copied {
            showCopyFeedback(for: result.id)
        }
    }

    private func showCopyFeedback(for resultID: String) {
        copiedResultID = resultID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if copiedResultID == resultID {
                copiedResultID = nil
            }
        }
    }
}

private struct OfficeSourceMark: View {
    let letter: String
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: geometry.size.width * 0.16, style: .continuous)
                    .fill(color.opacity(0.82))
                    .frame(width: geometry.size.width * 0.78,
                           height: geometry.size.height * 0.78)
                    .offset(x: geometry.size.width * 0.22,
                            y: geometry.size.height * 0.11)
                RoundedRectangle(cornerRadius: geometry.size.width * 0.13, style: .continuous)
                    .fill(color)
                    .frame(width: geometry.size.width * 0.68,
                           height: geometry.size.height)
                Text(letter)
                    .font(.system(size: geometry.size.width * 0.55, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: geometry.size.width * 0.68,
                           height: geometry.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct GmailMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let line = max(1.5, width * 0.16)
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.08, y: height * 0.92))
                    path.addLine(to: CGPoint(x: width * 0.08, y: height * 0.20))
                }
                .stroke(Color(red: 0.26, green: 0.52, blue: 0.96),
                        style: StrokeStyle(lineWidth: line, lineCap: .square))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.08, y: height * 0.20))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.58))
                    path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.20))
                }
                .stroke(Color(red: 0.92, green: 0.26, blue: 0.21),
                        style: StrokeStyle(lineWidth: line, lineJoin: .round))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.92, y: height * 0.20))
                    path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.92))
                }
                .stroke(Color(red: 0.20, green: 0.66, blue: 0.33),
                        style: StrokeStyle(lineWidth: line, lineCap: .square))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.08, y: height * 0.58))
                    path.addLine(to: CGPoint(x: width * 0.08, y: height * 0.92))
                }
                .stroke(Color(red: 0.98, green: 0.74, blue: 0.02),
                        style: StrokeStyle(lineWidth: line, lineCap: .square))
            }
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct DropboxMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            Path { path in
                func diamond(centerX: CGFloat, centerY: CGFloat) {
                    let halfWidth = width * 0.22
                    let halfHeight = height * 0.18
                    path.move(to: CGPoint(x: centerX, y: centerY - halfHeight))
                    path.addLine(to: CGPoint(x: centerX + halfWidth, y: centerY))
                    path.addLine(to: CGPoint(x: centerX, y: centerY + halfHeight))
                    path.addLine(to: CGPoint(x: centerX - halfWidth, y: centerY))
                    path.closeSubpath()
                }
                diamond(centerX: width * 0.27, centerY: height * 0.25)
                diamond(centerX: width * 0.73, centerY: height * 0.25)
                diamond(centerX: width * 0.27, centerY: height * 0.62)
                diamond(centerX: width * 0.73, centerY: height * 0.62)
                diamond(centerX: width * 0.50, centerY: height * 0.88)
            }
            .fill(Color(red: 0.00, green: 0.38, blue: 0.95))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct GoogleDriveMark: View {
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.36, y: height * 0.05))
                    path.addLine(to: CGPoint(x: width * 0.59, y: height * 0.05))
                    path.addLine(to: CGPoint(x: width * 0.23, y: height * 0.75))
                    path.addLine(to: CGPoint(x: 0, y: height * 0.75))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.98, green: 0.74, blue: 0.02))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.59, y: height * 0.05))
                    path.addLine(to: CGPoint(x: width, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.77, y: height * 0.80))
                    path.addLine(to: CGPoint(x: width * 0.48, y: height * 0.28))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.26, green: 0.52, blue: 0.96))

                Path { path in
                    path.move(to: CGPoint(x: width * 0.23, y: height * 0.75))
                    path.addLine(to: CGPoint(x: width, y: height * 0.75))
                    path.addLine(to: CGPoint(x: width * 0.86, y: height))
                    path.addLine(to: CGPoint(x: width * 0.09, y: height))
                    path.closeSubpath()
                }
                .fill(Color(red: 0.20, green: 0.66, blue: 0.33))
            }
        }
        .aspectRatio(1.1, contentMode: .fit)
    }
}

private enum ActivePreview {
    case message(MessageThreadPreview)
    case note(SearchResult)
    case mail(SearchResult)
    case calendar(SearchResult)
    case clipboard(SearchResult)

    var title: String {
        switch self {
        case .message(let thread): return thread.title
        case .note(let result), .mail(let result),
             .calendar(let result), .clipboard(let result): return result.name
        }
    }

    var symbol: String {
        switch self {
        case .message: return "message"
        case .note: return "note.text"
        case .mail: return "envelope.fill"
        case .calendar: return "calendar"
        case .clipboard: return "doc.on.clipboard"
        }
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
