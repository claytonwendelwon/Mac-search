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
