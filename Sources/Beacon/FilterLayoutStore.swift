import Foundation

/// Persists the user's visible filter order. `All` is always pinned first and
/// cannot be hidden; removing any other filter also removes it from All.
final class FilterLayoutStore: ObservableObject {
    static let shared = FilterLayoutStore()

    @Published private(set) var visibleFilters: [FileType]
    @Published var isEditing = false

    private let defaultsKey = "filterLayout.v1"
    private var orderBeforeDrag: [FileType]?
    private static let defaultVisibleFilters = FileType.allCases.filter { !$0.isOptionalSource }

    private init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let decoded = saved.compactMap(FileType.init(rawValue:))
        visibleFilters = Self.normalized(decoded.isEmpty ? Self.defaultVisibleFilters : decoded)
    }

    var hiddenFilters: [FileType] {
        FileType.allCases.filter { !visibleFilters.contains($0) && $0 != .all }
    }

    var includedInAll: Set<FileType> {
        Set(visibleFilters.filter(\.includedInAll))
    }

    func hide(_ type: FileType) {
        guard type != .all else { return }
        cancelMove()
        visibleFilters.removeAll { $0 == type }
        save()
    }

    func add(_ type: FileType) {
        guard !visibleFilters.contains(type) else { return }
        cancelMove()
        visibleFilters.append(type)
        visibleFilters = Self.normalized(visibleFilters)
        save()
    }

    func move(_ type: FileType, before destination: FileType) {
        guard type != .all, type != destination,
              let sourceIndex = visibleFilters.firstIndex(of: type) else { return }
        let item = visibleFilters.remove(at: sourceIndex)
        if destination == .all {
            visibleFilters.insert(item, at: min(1, visibleFilters.count))
            return
        }
        guard let destinationIndex = visibleFilters.firstIndex(of: destination) else { return }
        visibleFilters.insert(item, at: max(1, destinationIndex))
    }

    func moveToEnd(_ type: FileType) {
        guard type != .all, let index = visibleFilters.firstIndex(of: type),
              index != visibleFilters.index(before: visibleFilters.endIndex) else { return }
        let item = visibleFilters.remove(at: index)
        visibleFilters.append(item)
    }

    func previewOrder(_ order: [FileType]) {
        guard orderBeforeDrag != nil else { return }
        let normalized = Self.normalized(order)
        if normalized != visibleFilters { visibleFilters = normalized }
    }

    func beginMove() {
        cancelMove()
        orderBeforeDrag = visibleFilters
    }

    func commitMove() {
        orderBeforeDrag = nil
        save()
    }

    func cancelMove() {
        guard let orderBeforeDrag else { return }
        visibleFilters = orderBeforeDrag
        self.orderBeforeDrag = nil
    }

    func reset() {
        cancelMove()
        visibleFilters = Self.defaultVisibleFilters
        save()
    }

    private func save() {
        UserDefaults.standard.set(visibleFilters.map(\.rawValue), forKey: defaultsKey)
    }

    private static func normalized(_ input: [FileType]) -> [FileType] {
        var seen = Set<FileType>()
        let unique = input.filter { seen.insert($0).inserted && $0 != .all }
        return [.all] + unique
    }
}
