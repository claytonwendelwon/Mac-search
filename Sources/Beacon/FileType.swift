import Foundation

/// A user-facing filter category. Each maps to one or more Uniform Type
/// Identifiers that Spotlight records in `kMDItemContentTypeTree`, so matching
/// any descendant type (e.g. PNG, JPEG -> public.image) just works.
enum FileType: String, CaseIterable, Identifiable {
    case all
    case apps
    case photos
    case videos
    case docs
    case pdfs
    case audio
    case folders

    var id: String { rawValue }

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
        }
    }
}
