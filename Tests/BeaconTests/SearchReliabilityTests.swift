import Foundation
import XCTest
@testable import Beacon

final class AppRankingTests: XCTestCase {
    func testExactAndPrefixMatchesBeatIncidentalHelpers() {
        let tokens = SearchText.tokens("beacon")
        let beacon = AppRanking.rank(name: "Beacon", path: "/Applications/Beacon.app",
                                     tokens: tokens)
        let helper = AppRanking.rank(name: "Beacon Update Helper",
                                     path: "/Applications/Utilities/Beacon Update Helper.app",
                                     bundleIdentifier: "com.example.beacon.helper",
                                     tokens: tokens)

        XCTAssertNotNil(beacon)
        XCTAssertNotNil(helper)
        XCTAssertTrue(beacon! < helper!)
    }

    func testNonMatchingAppsAreRejected() {
        let rank = AppRanking.rank(name: "Adobe Content Synchronizer",
                                   path: "/Applications/Utilities/Adobe Sync/CoreSync.app",
                                   tokens: SearchText.tokens("beac"))
        XCTAssertNil(rank)
    }

    func testUserFacingAppWinsEqualMatchTier() {
        let tokens = SearchText.tokens("bea")
        let normal = AppRanking.rank(name: "Beacon Tools",
                                     path: "/Applications/Beacon Tools.app",
                                     tokens: tokens)
        let helper = AppRanking.rank(name: "Beacon Helper",
                                     path: "/Applications/Utilities/Beacon Helper.app",
                                     bundleIdentifier: "com.example.beacon.helper",
                                     tokens: tokens)

        XCTAssertTrue(normal! < helper!)
    }
}

final class AppStoreCancellationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCancellationIsDistinctFromAnEmptyCatalog() {
        let store = AppStore(roots: [root])

        XCTAssertNil(store.search(tokens: [], isCancelled: { true }))
        XCTAssertEqual(store.search(tokens: [])?.count, 0)
    }

    func testCancelledRefreshDoesNotPoisonNextSearch() throws {
        try createApp(named: "Beacon")
        let store = AppStore(roots: [root])
        XCTAssertEqual(store.search(tokens: SearchText.tokens("beac"))?.map(\.name),
                       ["Beacon"])

        try createApp(named: "Beacon Beta")
        store.refresh()
        XCTAssertNil(store.search(tokens: SearchText.tokens("beac"),
                                  isCancelled: { true }))
        XCTAssertEqual(store.search(tokens: SearchText.tokens("beac"))?.map(\.name),
                       ["Beacon", "Beacon Beta"])
    }

    private func createApp(named name: String) throws {
        let contents = root
            .appendingPathComponent("\(name).app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents,
                                                withIntermediateDirectories: true)
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
}

final class SearchStateTests: XCTestCase {
    func testStaleGenerationIsRejected() {
        let generation = SearchGeneration()
        generation.set(41)
        XCTAssertTrue(generation.isCurrent(41))
        generation.set(42)
        XCTAssertFalse(generation.isCurrent(41))
        XCTAssertTrue(generation.isCurrent(42))
    }

    func testGrowingPageKeepsExistingPrefixStable() {
        let rows = Array(0..<200)
        let first = PageWindow.slice(rows, limit: 80)
        let second = PageWindow.slice(rows, limit: 160)

        XCTAssertTrue(first.hasMore)
        XCTAssertTrue(second.hasMore)
        XCTAssertEqual(Array(second.rows.prefix(first.rows.count)), first.rows)
        XCTAssertEqual(first.rows.count, 80)
        XCTAssertEqual(second.rows.count, 160)
    }
}

final class SearchRefinementTests: XCTestCase {
    func testEveryTopLevelFilterHasThreeDimensions() {
        for type in FileType.allCases {
            XCTAssertEqual(RefinementCatalog.dimensions(for: type).count, 3,
                           "\(type) should expose its top three dimensions")
        }
    }

    func testSidebarUsesGlobalSortInsteadOfTimeRangeDimensions() {
        let hidden = Set(["time", "photo-date", "recent-use", "recent-open"])
        for type in FileType.allCases {
            XCTAssertTrue(
                Set(RefinementCatalog.sidebarDimensions(for: type).map(\.id))
                    .isDisjoint(with: hidden)
            )
        }
    }

    func testLocationRefinementUsesPathBoundaries() {
        let home = NSHomeDirectory()
        let selection = RefinementSelection(choices: ["location": "downloads"])
        XCTAssertTrue(RefinementMatcher.matches(
            fileResult(path: home + "/Downloads/photo.png"),
            type: .recents, selection: selection
        ))
        XCTAssertFalse(RefinementMatcher.matches(
            fileResult(path: home + "/Downloads Archive/photo.png"),
            type: .recents, selection: selection
        ))
    }

    func testScreenshotRefinementUsesNameAndKnownFolder() {
        let selection = RefinementSelection(choices: ["location": "screenshots"])
        XCTAssertTrue(RefinementMatcher.matches(
            fileResult(path: "/tmp/Screenshot 2026-07-12.png"),
            type: .recents, selection: selection
        ))
        XCTAssertTrue(RefinementMatcher.matches(
            fileResult(path: NSHomeDirectory() + "/Pictures/Screenshots/capture.png"),
            type: .recents, selection: selection
        ))
        XCTAssertFalse(RefinementMatcher.matches(
            fileResult(path: NSHomeDirectory() + "/Pictures/photo.png"),
            type: .recents, selection: selection
        ))
    }

    func testSelectionsAcrossDimensionsUseAndSemantics() {
        let now = Date()
        let selection = RefinementSelection(choices: [
            "location": "downloads",
            "time": "today"
        ])
        XCTAssertTrue(RefinementMatcher.matches(
            fileResult(path: NSHomeDirectory() + "/Downloads/today.pdf", modified: now),
            type: .all, selection: selection, now: now
        ))
        XCTAssertFalse(RefinementMatcher.matches(
            fileResult(path: NSHomeDirectory() + "/Desktop/today.pdf", modified: now),
            type: .all, selection: selection, now: now
        ))
    }

    func testSanitizationDropsDimensionsFromAnotherFilter() {
        let selection = RefinementSelection(choices: [
            "conversation": "group",
            "location": "downloads"
        ])
        XCTAssertEqual(
            RefinementCatalog.sanitized(selection, for: .messages),
            RefinementSelection(choices: ["conversation": "group"])
        )
    }

    func testSelectionRoundTripsForPerFilterPersistence() throws {
        let selection = RefinementSelection(choices: [
            "location": "downloads",
            "time": "week"
        ])
        let encoded = try JSONEncoder().encode(selection)
        XCTAssertEqual(try JSONDecoder().decode(RefinementSelection.self, from: encoded),
                       selection)
    }

    func testPhotosLibraryFallsBackWhenAssetsAreNotIndexed() {
        let dimensions = RefinementCatalog.enriched(
            RefinementCatalog.dimensions(for: .photos),
            with: []
        )
        let source = dimensions.first { $0.id == "photo-source" }
        XCTAssertEqual(source?.options.first { $0.id == "photos-library" }?.isEnabled,
                       false)
        XCTAssertNotNil(source?.unavailableReason)
    }

    func testPSDCanBeAddedAndMatchedAsAnImageFormat() {
        let selection = RefinementSelection(choices: ["format": "psd"])
        XCTAssertTrue(RefinementMatcher.matches(
            fileResult(path: "/tmp/design.psd"),
            type: .photos, selection: selection
        ))
        XCTAssertTrue(FileType.photos.filenameExtensions.contains("psd"))
    }

    func testProjectOptionsOnlyIncludeDetectedTypes() {
        var facets = RefinementFacets()
        facets.isProject = true
        facets.category = "git"
        let dimensions = RefinementCatalog.enriched(
            RefinementCatalog.catalogDimensions(for: .folders),
            with: [fileResult(path: "/tmp/repository", isFolder: true, facets: facets)]
        )
        XCTAssertEqual(
            dimensions.first(where: { $0.id == "project" })?.options.map(\.id),
            ["git"]
        )
    }

    func testProjectAndCloudFacetsAreUserSpecific() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(
            RefinementFacetBuilder.projectCategory(at: root.path), "git"
        )

        let cloudPath = NSHomeDirectory()
            + "/Library/CloudStorage/GoogleDrive-person@example.com/My Drive/Design/file.psd"
        XCTAssertEqual(
            RefinementFacetBuilder.cloudAccount(for: cloudPath),
            "person@example.com"
        )
        XCTAssertEqual(
            RefinementFacetBuilder.cloudContainer(for: cloudPath),
            "Design"
        )
    }

    private func fileResult(path: String, modified: Date? = nil,
                            isFolder: Bool = false,
                            facets: RefinementFacets = .empty) -> SearchResult {
        SearchResult(
            id: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            path: path,
            kind: "File",
            size: nil,
            modified: modified,
            lastUsed: nil,
            dateAdded: nil,
            isFolder: isFolder,
            isApp: false,
            matchKind: .name,
            facets: facets
        )
    }
}

final class RefinementLayoutStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "RefinementLayoutStoreTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testOptionalPSDPersistsWithoutChangingOtherFilters() {
        let key = "layouts"
        let store = RefinementLayoutStore(defaults: defaults, defaultsKey: key)
        let originalVideos = store.layout(for: .videos)
        XCTAssertFalse(
            store.layout(for: .photos).optionIDs["format", default: []].contains("psd")
        )

        store.addOption("psd", dimensionID: "format", for: .photos)
        let reloaded = RefinementLayoutStore(defaults: defaults, defaultsKey: key)

        XCTAssertTrue(
            reloaded.layout(for: .photos).optionIDs["format", default: []].contains("psd")
        )
        XCTAssertEqual(
            reloaded.layout(for: .videos),
            originalVideos
        )
    }

    func testDimensionCanBeAddedHiddenReorderedAndReset() {
        let store = RefinementLayoutStore(defaults: defaults, defaultsKey: "layouts")
        XCTAssertFalse(store.layout(for: .videos).dimensionIDs.contains("format"))

        store.addDimension("format", for: .videos)
        XCTAssertTrue(store.layout(for: .videos).dimensionIDs.contains("format"))

        store.moveDimension("format", before: "location", for: .videos)
        XCTAssertEqual(store.layout(for: .videos).dimensionIDs.first, "format")

        store.hideDimension("format", for: .videos)
        XCTAssertFalse(store.layout(for: .videos).dimensionIDs.contains("format"))

        store.addDimension("format", for: .videos)
        store.reset(.videos)
        XCTAssertFalse(store.layout(for: .videos).dimensionIDs.contains("format"))
    }
}

final class MediaFilterTests: XCTestCase {
    func testUniversalFeedUsesSingleRecentsIdentity() {
        XCTAssertEqual(FileType.all.title, "Recents")
        XCTAssertEqual(FileType.all.symbol, "clock")
    }

    func testVideoExtensionsExcludeTypeScriptAmbiguity() {
        XCTAssertTrue(FileType.videos.filenameExtensions.contains("mp4"))
        XCTAssertTrue(FileType.videos.filenameExtensions.contains("mov"))
        XCTAssertFalse(FileType.videos.filenameExtensions.contains("ts"))
    }

    func testBrowsableFileFiltersHaveConcreteExtensionFallbacks() {
        XCTAssertTrue(FileType.docs.filenameExtensions.contains("docx"))
        XCTAssertTrue(FileType.docs.filenameExtensions.contains("md"))
        XCTAssertTrue(FileType.photos.filenameExtensions.contains("png"))
        XCTAssertTrue(FileType.photos.filenameExtensions.contains("heic"))
        XCTAssertTrue(FileType.audio.filenameExtensions.contains("mp3"))
        XCTAssertTrue(FileType.audio.filenameExtensions.contains("m4a"))
    }
}
