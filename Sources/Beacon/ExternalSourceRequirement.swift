import AppKit
import Foundation

enum ExternalSourceState: Equatable {
    case ready
    case notInstalled
    case needsSignIn
}

struct ExternalSourceRequirement {
    let appName: String
    let bundleIdentifier: String
    let installURL: URL
    let cloudFolderPrefixes: [String]
    let legacyPaths: [String]

    var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }

    var state: ExternalSourceState {
        if hasConfiguredAccount { return .ready }
        return applicationURL == nil ? .notInstalled : .needsSignIn
    }

    var hasConfiguredAccount: Bool {
        let fm = FileManager.default
        if legacyPaths.contains(where: fm.fileExists) { return true }

        let cloudStorage = NSHomeDirectory() + "/Library/CloudStorage"
        guard let names = try? fm.contentsOfDirectory(atPath: cloudStorage) else { return false }
        return names.contains { name in
            cloudFolderPrefixes.contains(where: name.hasPrefix)
        }
    }

    func install() {
        NSWorkspace.shared.open(installURL)
    }

    func openApplication() {
        if let applicationURL {
            NSWorkspace.shared.openApplication(
                at: applicationURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }
    }
}

extension FileType {
    var externalSourceRequirement: ExternalSourceRequirement? {
        let home = NSHomeDirectory()
        switch self {
        case .googleDrive:
            return ExternalSourceRequirement(
                appName: "Google Drive",
                bundleIdentifier: "com.google.drivefs",
                installURL: URL(string: "https://www.google.com/drive/download/")!,
                cloudFolderPrefixes: ["GoogleDrive-"],
                legacyPaths: [home + "/Google Drive"]
            )
        case .oneDrive:
            return ExternalSourceRequirement(
                appName: "OneDrive",
                bundleIdentifier: "com.microsoft.OneDrive",
                installURL: URL(string: "https://www.microsoft.com/microsoft-365/onedrive/download")!,
                cloudFolderPrefixes: ["OneDrive-"],
                legacyPaths: [home + "/OneDrive"]
            )
        case .dropbox:
            return ExternalSourceRequirement(
                appName: "Dropbox",
                bundleIdentifier: "com.getdropbox.dropbox",
                installURL: URL(string: "https://www.dropbox.com/install")!,
                cloudFolderPrefixes: ["Dropbox"],
                legacyPaths: [home + "/Dropbox"]
            )
        default:
            return nil
        }
    }
}
