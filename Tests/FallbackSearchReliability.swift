import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
        exit(1)
    }
}

private func createApp(named name: String, in root: URL) throws {
    let contents = root
        .appendingPathComponent("\(name).app", isDirectory: true)
        .appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let plist: [String: Any] = [
        "CFBundleDisplayName": name,
        "CFBundleIdentifier": "com.example.\(name.replacingOccurrences(of: " ", with: ""))",
        "CFBundlePackageType": "APPL"
    ]
    let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                  format: .xml,
                                                  options: 0)
    try data.write(to: contents.appendingPathComponent("Info.plist"))
}

@main
private enum SearchReliabilityRunner {
    static func main() throws {
        let beacon = AppRanking.rank(name: "Beacon", path: "/Applications/Beacon.app",
                                     tokens: SearchText.tokens("beacon"))
        let helper = AppRanking.rank(name: "Beacon Update Helper",
                                     path: "/Applications/Utilities/Beacon Update Helper.app",
                                     bundleIdentifier: "com.example.beacon.helper",
                                     tokens: SearchText.tokens("beacon"))
        expect(beacon != nil && helper != nil && beacon! < helper!,
               "exact app match must outrank its helper")
        expect(AppRanking.rank(name: "Adobe Content Synchronizer",
                               path: "/Applications/Utilities/Adobe Sync/CoreSync.app",
                               tokens: SearchText.tokens("beac")) == nil,
               "unrelated helper must not match beac")

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try createApp(named: "Beacon", in: root)
        let store = AppStore(roots: [root])
        expect(store.search(tokens: SearchText.tokens("beac"))?.map(\.name) == ["Beacon"],
               "initial app scan must find Beacon")
        try createApp(named: "Beacon Beta", in: root)
        store.refresh()
        expect(store.search(tokens: SearchText.tokens("beac"), isCancelled: { true }) == nil,
               "cancelled scan must not become an empty catalog")
        expect(store.search(tokens: SearchText.tokens("beac"))?.map(\.name)
               == ["Beacon", "Beacon Beta"],
               "a cancelled refresh must not poison the next scan")

        let generation = SearchGeneration()
        generation.set(1)
        generation.set(2)
        expect(!generation.isCurrent(1) && generation.isCurrent(2),
               "stale generations must be rejected")

        let rows = Array(0..<400)
        let firstPage = PageWindow.slice(rows, limit: 160)
        let secondPage = PageWindow.slice(rows, limit: 320)
        expect(firstPage.hasMore && secondPage.hasMore,
               "pagination must report remaining rows")
        expect(Array(secondPage.rows.prefix(firstPage.rows.count)) == firstPage.rows,
               "larger pages must preserve the existing prefix")
        expect(SearchPerformancePolicy.pageSize == 160,
               "search pages must remain dense")
        expect(SearchPerformancePolicy.metadataReadLimit(
            pageLimit: 160, previousLimit: 0
        ) == 640, "initial metadata fetch must cover several pages")

        if ProcessInfo.processInfo.environment["VERIFY_INSTALLED_APPS"] == "1" {
            let installed = AppStore().search(tokens: SearchText.tokens("beac"), limit: 20)
            if installed?.contains(where: { $0.name == "Beacon" }) == true {
                expect(installed?.first?.name == "Beacon",
                       "installed Beacon must be the first beac app result")
            }
            expect(installed?.contains(where: { $0.name == "Adobe Content Synchronizer" })
                   != true,
                   "unrelated Adobe helper must not appear in beac results")
        }

        print("Search reliability checks passed")
    }
}
