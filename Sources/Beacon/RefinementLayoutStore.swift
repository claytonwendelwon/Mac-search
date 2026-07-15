import Foundation

struct RefinementLayout: Codable, Equatable {
    var dimensionIDs: [String]
    var optionIDs: [String: [String]]
}

final class RefinementLayoutStore: ObservableObject {
    static let shared = RefinementLayoutStore()

    @Published private(set) var layouts: [String: RefinementLayout]

    private let defaults: UserDefaults
    private let defaultsKey: String

    init(defaults: UserDefaults = .standard,
         defaultsKey: String = "refinementLayouts.v1") {
        self.defaults = defaults
        self.defaultsKey = defaultsKey
        if let data = defaults.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(
               [String: RefinementLayout].self, from: data
           ) {
            layouts = decoded
        } else {
            layouts = [:]
        }
        normalizeAll()
    }

    func layout(for type: FileType) -> RefinementLayout {
        layouts[type.rawValue] ?? Self.defaultLayout(for: type)
    }

    func resolvedDimensions(for type: FileType) -> [RefinementDimension] {
        let catalog = RefinementCatalog.catalogDimensions(for: type)
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let profile = layout(for: type)
        return profile.dimensionIDs.compactMap { dimensionID in
            guard let dimension = byID[dimensionID] else { return nil }
            let visible = Set(profile.optionIDs[dimensionID] ?? [])
            let options = dimension.options.filter { visible.contains($0.id) }
            return RefinementDimension(
                dimension.id, dimension.title, options: options,
                unavailableReason: dimension.unavailableReason
            )
        }
    }

    func hiddenDimensions(for type: FileType) -> [RefinementDimension] {
        let visible = Set(layout(for: type).dimensionIDs)
        return RefinementCatalog.catalogDimensions(for: type).filter {
            !visible.contains($0.id)
        }
    }

    func hiddenOptions(for type: FileType,
                       dimensionID: String) -> [RefinementOption] {
        let visible = Set(layout(for: type).optionIDs[dimensionID] ?? [])
        return RefinementCatalog.catalogDimensions(for: type)
            .first(where: { $0.id == dimensionID })?
            .options.filter { !visible.contains($0.id) } ?? []
    }

    func addDimension(_ dimensionID: String, for type: FileType) {
        guard let dimension = RefinementCatalog.catalogDimensions(for: type)
            .first(where: { $0.id == dimensionID }) else { return }
        var profile = layout(for: type)
        guard !profile.dimensionIDs.contains(dimensionID) else { return }
        profile.dimensionIDs.append(dimensionID)
        profile.optionIDs[dimensionID] = RefinementCatalog.defaultOptionIDs(
            for: type, dimension: dimension
        )
        set(profile, for: type)
    }

    func hideDimension(_ dimensionID: String, for type: FileType) {
        var profile = layout(for: type)
        profile.dimensionIDs.removeAll { $0 == dimensionID }
        set(profile, for: type)
    }

    func addOption(_ optionID: String, dimensionID: String,
                   for type: FileType) {
        guard let dimension = RefinementCatalog.catalogDimensions(for: type)
            .first(where: { $0.id == dimensionID }),
              dimension.options.contains(where: { $0.id == optionID }) else { return }
        var profile = layout(for: type)
        if !profile.dimensionIDs.contains(dimensionID) {
            profile.dimensionIDs.append(dimensionID)
        }
        var options = profile.optionIDs[dimensionID] ?? []
        guard !options.contains(optionID) else { return }
        options.append(optionID)
        profile.optionIDs[dimensionID] = options
        set(profile, for: type)
    }

    func hideOption(_ optionID: String, dimensionID: String,
                    for type: FileType) {
        var profile = layout(for: type)
        profile.optionIDs[dimensionID]?.removeAll { $0 == optionID }
        set(profile, for: type)
    }

    func moveDimension(_ dimensionID: String, before destinationID: String,
                       for type: FileType) {
        var profile = layout(for: type)
        guard dimensionID != destinationID,
              let source = profile.dimensionIDs.firstIndex(of: dimensionID),
              let destination = profile.dimensionIDs.firstIndex(of: destinationID)
        else { return }
        let value = profile.dimensionIDs.remove(at: source)
        let target = destination
        profile.dimensionIDs.insert(value, at: target)
        set(profile, for: type)
    }

    func reset(_ type: FileType) {
        var updated = layouts
        updated.removeValue(forKey: type.rawValue)
        layouts = updated
        save()
    }

    private func set(_ profile: RefinementLayout, for type: FileType) {
        var updated = layouts
        updated[type.rawValue] = Self.normalized(profile, for: type)
        layouts = updated
        save()
    }

    private func normalizeAll() {
        var normalized: [String: RefinementLayout] = [:]
        for (key, profile) in layouts {
            guard let type = FileType(rawValue: key) else { continue }
            normalized[key] = Self.normalized(profile, for: type)
        }
        if normalized != layouts {
            layouts = normalized
            save()
        }
    }

    private static func defaultLayout(for type: FileType) -> RefinementLayout {
        let catalog = RefinementCatalog.catalogDimensions(for: type)
        let defaults = Set(RefinementCatalog.defaultDimensionIDs(for: type))
        let dimensions = catalog.filter { defaults.contains($0.id) }
        return RefinementLayout(
            dimensionIDs: dimensions.map(\.id),
            optionIDs: Dictionary(uniqueKeysWithValues: dimensions.map {
                ($0.id, RefinementCatalog.defaultOptionIDs(for: type, dimension: $0))
            })
        )
    }

    private static func normalized(_ profile: RefinementLayout,
                                   for type: FileType) -> RefinementLayout {
        let catalog = RefinementCatalog.catalogDimensions(for: type)
        let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        var seen = Set<String>()
        let dimensions = profile.dimensionIDs.filter {
            byID[$0] != nil && seen.insert($0).inserted
        }
        var options: [String: [String]] = [:]
        for dimensionID in dimensions {
            guard let dimension = byID[dimensionID] else { continue }
            let valid = Set(dimension.options.map(\.id))
            var optionSeen = Set<String>()
            options[dimensionID] = (profile.optionIDs[dimensionID] ?? []).filter {
                valid.contains($0) && optionSeen.insert($0).inserted
            }
        }
        return RefinementLayout(dimensionIDs: dimensions, optionIDs: options)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(layouts) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}
