import CoreServices
import Foundation

struct BoundedMetadataRecord {
    let path: String
    let name: String
    let kind: String
    let size: Int64?
    let modified: Date?
    let lastUsed: Date?
    let dateAdded: Date?
    let contentTypes: [String]
    let dateTaken: Date?
    let duration: Double?
    let authors: [String]
    let tags: [String]
    let hasSearchableText: Bool?
}

final class BoundedMetadataStore {
    func search(queryString: String, scopes: [String], limit: Int,
                isCancelled: (() -> Bool)? = nil) -> [BoundedMetadataRecord] {
        guard isCancelled?() != true,
              let query = MDQueryCreate(
                kCFAllocatorDefault,
                queryString as CFString,
                nil,
                [
                    kMDItemLastUsedDate,
                    kMDItemFSContentChangeDate,
                    kMDItemDateAdded
                ] as CFArray
              ) else { return [] }

        MDQuerySetMaxCount(query, limit)
        for attribute in [
            kMDItemLastUsedDate,
            kMDItemFSContentChangeDate,
            kMDItemDateAdded
        ] {
            MDQuerySetSortOptionFlagsForAttribute(
                query, attribute, kMDQueryReverseSortOrderFlag.rawValue
            )
        }
        let searchScopes: [CFString] = scopes.isEmpty
            ? [kMDQueryScopeComputer]
            : scopes.map { $0 as CFString }
        MDQuerySetSearchScope(query, searchScopes as CFArray, 0)

        guard MDQueryExecute(query, CFOptionFlags(kMDQuerySynchronous.rawValue)),
              isCancelled?() != true else {
            MDQueryStop(query)
            return []
        }
        defer { MDQueryStop(query) }

        let count = min(MDQueryGetResultCount(query), limit)
        var rows: [BoundedMetadataRecord] = []
        rows.reserveCapacity(count)

        for index in 0..<count {
            if index & 0xFF == 0, isCancelled?() == true { return [] }
            guard let raw = MDQueryGetResultAtIndex(query, index) else { continue }
            let item = unsafeBitCast(raw, to: MDItem.self)
            guard let path = MDItemCopyAttribute(item, kMDItemPath) as? String else {
                continue
            }
            let displayName = MDItemCopyAttribute(item, kMDItemDisplayName) as? String
            let fileName = MDItemCopyAttribute(item, kMDItemFSName) as? String
            let name = displayName ?? fileName
                ?? URL(fileURLWithPath: path).lastPathComponent
            let kind = MDItemCopyAttribute(item, kMDItemKind) as? String ?? ""
            let size = (MDItemCopyAttribute(item, kMDItemFSSize) as? NSNumber)?
                .int64Value
            let modified = MDItemCopyAttribute(
                item, kMDItemFSContentChangeDate
            ) as? Date
            let lastUsed = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
            let dateAdded = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
            let contentTypes = MDItemCopyAttribute(
                item, kMDItemContentTypeTree
            ) as? [String] ?? []
            let dateTaken = MDItemCopyAttribute(
                item, kMDItemContentCreationDate
            ) as? Date
            let duration = (MDItemCopyAttribute(
                item, kMDItemDurationSeconds
            ) as? NSNumber)?.doubleValue
            let authors = MDItemCopyAttribute(item, kMDItemAuthors) as? [String] ?? []
            let tags = MDItemCopyAttribute(
                item, "kMDItemUserTags" as CFString
            ) as? [String] ?? []
            let hasSearchableText: Bool?
            if contentTypes.contains("com.adobe.pdf") {
                let text = MDItemCopyAttribute(item, kMDItemTextContent) as? String
                hasSearchableText = text.map {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            } else {
                hasSearchableText = nil
            }
            rows.append(BoundedMetadataRecord(
                path: path,
                name: name,
                kind: kind,
                size: size,
                modified: modified,
                lastUsed: lastUsed,
                dateAdded: dateAdded,
                contentTypes: contentTypes,
                dateTaken: dateTaken,
                duration: duration,
                authors: authors,
                tags: tags,
                hasSearchableText: hasSearchableText
            ))
        }
        return rows
    }
}
