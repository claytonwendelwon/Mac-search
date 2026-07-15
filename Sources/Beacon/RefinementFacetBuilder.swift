import Foundation

enum RefinementFacetBuilder {
    private static let lock = NSLock()
    private static var projectCache: [String: String] = [:]
    private static var nonProjectPaths = Set<String>()

    static func projectCategory(at path: String) -> String? {
        lock.lock()
        if let cached = projectCache[path] {
            lock.unlock()
            return cached
        }
        if nonProjectPaths.contains(path) {
            lock.unlock()
            return nil
        }
        lock.unlock()

        let manager = FileManager.default
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let category: String?
        if manager.fileExists(atPath: url.appendingPathComponent(".git").path) {
            category = "git"
        } else if manager.fileExists(
            atPath: url.appendingPathComponent("Package.swift").path
        ) || manager.fileExists(
            atPath: url.appendingPathComponent("package.json").path
        ) {
            category = "package"
        } else if (try? manager.contentsOfDirectory(atPath: path))?
            .contains(where: { $0.hasSuffix(".xcodeproj") }) == true {
            category = "xcode"
        } else {
            category = nil
        }

        lock.lock()
        if let category {
            projectCache[path] = category
        } else {
            nonProjectPaths.insert(path)
        }
        lock.unlock()
        return category
    }

    static func cloudAccount(for path: String) -> String {
        let home = NSHomeDirectory()
        if path.hasPrefix(home + "/Library/Mobile Documents/")
            || path.hasPrefix(home + "/Library/CloudStorage/iCloud Drive") {
            return "iCloud"
        }
        let legacy: [(String, String)] = [
            (home + "/Google Drive", "Google Drive"),
            (home + "/OneDrive", "OneDrive"),
            (home + "/Dropbox", "Dropbox")
        ]
        if let match = legacy.first(where: { path.hasPrefix($0.0) }) {
            return match.1
        }
        guard let range = path.range(of: "/CloudStorage/") else { return "" }
        let root = path[range.upperBound...].split(separator: "/").first.map(String.init) ?? ""
        for prefix in ["GoogleDrive-", "OneDrive-", "Dropbox-"] where root.hasPrefix(prefix) {
            return String(root.dropFirst(prefix.count))
        }
        return root == "Dropbox" ? "Dropbox" : root
    }

    static func cloudContainer(for path: String) -> String {
        let home = NSHomeDirectory()
        let legacyRoots = [
            home + "/Google Drive", home + "/OneDrive", home + "/Dropbox",
            home + "/Library/CloudStorage/iCloud Drive"
        ]
        if let root = legacyRoots.first(where: { path.hasPrefix($0 + "/") }) {
            let suffix = path.dropFirst(root.count + 1)
            return suffix.split(separator: "/").first.map(String.init) ?? ""
        }

        let markers = ["/CloudStorage/", "/com~apple~CloudDocs/"]
        guard let marker = markers.first(where: path.contains),
              let range = path.range(of: marker) else { return "" }
        let parts = path[range.upperBound...].split(separator: "/")
        if marker == "/CloudStorage/", parts.count > 1 {
            if parts[0].lowercased().hasPrefix("googledrive"),
               parts.count > 2, String(parts[1]).searchFolded == "my drive" {
                return String(parts[2])
            }
            return String(parts[1])
        }
        return parts.first.map(String.init) ?? ""
    }
}
