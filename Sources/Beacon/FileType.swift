import Foundation

/// A user-facing filter category. Each maps to one or more Uniform Type
/// Identifiers that Spotlight records in `kMDItemContentTypeTree`, so matching
/// any descendant type (e.g. PNG, JPEG -> public.image) just works.
enum FileType: String, CaseIterable, Identifiable {
    case all
    case apps
    case messages
    case notes
    case clipboard
    case history
    case docs
    case pdfs
    case audio
    case folders
    case photos
    case videos

    var id: String { rawValue }

    /// Messages are searched from the Messages database, not the file index.
    var isMessages: Bool { self == .messages }

    /// Notes are searched from the Apple Notes database, not the file index.
    var isNotes: Bool { self == .notes }

    /// Clipboard history is searched from Beacon's own capture store.
    var isClipboard: Bool { self == .clipboard }

    /// Browser history is searched from Safari/Chromium history databases.
    var isHistory: Bool { self == .history }

    /// True for filters backed by the Spotlight file index (All and the file
    /// type chips). Database/store-backed filters (Messages, Notes, Clipboard,
    /// History) handle their own results and must ignore file-index updates.
    var usesFileIndex: Bool {
        !(isMessages || isNotes || isClipboard || isHistory)
    }

    /// Whether this source's content appears in the blended "All" view. Files,
    /// apps, messages, and notes do; Clipboard and History are opt-in via their
    /// own chips (and `all` itself isn't marked).
    var includedInAll: Bool {
        switch self {
        case .all, .clipboard, .history: return false
        default: return true
        }
    }

    /// Sources that fully require Full Disk Access (we block with a prompt until
    /// granted). History is intentionally excluded: Chromium browsers read
    /// without it, so History shows what it can and surfaces Safari's lock as a
    /// slim footer instead of blocking.
    var needsFullDiskAccess: Bool { self == .messages || self == .notes }

    var title: String {
        switch self {
        case .all: return "All"
        case .apps: return "Apps"
        case .photos: return "Photos"
        case .videos: return "Videos"
        case .docs: return "Docs"
        case .pdfs: return "PDFs"
        case .audio: return "Audio"
        case .folders: return "Folders"
        case .messages: return "Messages"
        case .notes: return "Notes"
        case .clipboard: return "Clipboard"
        case .history: return "History"
        }
    }

    /// SF Symbol used on the filter chip.
    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .apps: return "app.badge"
        case .photos: return "photo"
        case .videos: return "film"
        case .docs: return "doc.text"
        case .pdfs: return "doc.richtext"
        case .audio: return "music.note"
        case .folders: return "folder"
        case .messages: return "message"
        case .notes: return "note.text"
        case .clipboard: return "doc.on.clipboard"
        case .history: return "clock.arrow.circlepath"
        }
    }

    /// Content-type tree UTIs to match. Empty means "no type restriction".
    var contentTypeTrees: [String] {
        switch self {
        case .all:
            return []
        case .apps:
            return ["com.apple.application"]
        case .photos:
            return ["public.image"]
        case .videos:
            return ["public.movie"]
        case .docs:
            return [
                "public.text",
                "public.composite-content",
                "public.presentation",
                "public.spreadsheet",
                "com.microsoft.word.doc",
                "com.microsoft.excel.xls",
                "com.microsoft.powerpoint.ppt",
                "com.apple.iwork.pages.sffpages",
                "com.apple.iwork.numbers.sffnumbers",
                "com.apple.iwork.keynote.sffkey"
            ]
        case .pdfs:
            return ["com.adobe.pdf"]
        case .audio:
            return ["public.audio"]
        case .folders:
            return ["public.folder"]
        case .messages:
            return [] // handled by MessageStore, not the file index
        case .notes:
            return [] // handled by NotesStore, not the file index
        case .clipboard:
            return [] // handled by ClipboardStore, not the file index
        case .history:
            return [] // handled by BrowserHistoryStore, not the file index
        }
    }
}
