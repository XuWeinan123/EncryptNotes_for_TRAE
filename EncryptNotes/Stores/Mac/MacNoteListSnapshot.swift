#if os(macOS)
import Foundation

nonisolated struct MacNoteListSnapshot: Equatable {
    let items: [NoteListItem]
    let tagCounts: [TagCount]
    let emptyReadableCount: Int
    let encryptedCount: Int
    let totalCount: Int

    var visibleTagCounts: [TagCount] {
        Array(tagCounts.prefix(8))
    }

    var overflowTagCounts: [TagCount] {
        Array(tagCounts.dropFirst(8))
    }

    func recentItems(limit: Int) -> [NoteListItem] {
        Array(items.prefix(max(0, limit)))
    }
}

nonisolated enum MacNoteListSnapshotBuilder {
    static func make(
        readableNotes: [Note],
        lockedEncryptedNotes: [EncryptedNoteInfo],
        query rawQuery: String = "",
        selectedTag: String? = nil,
        titleProvider: (Note) -> String
    ) -> MacNoteListSnapshot {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        var tagCountsByName: [String: Int] = [:]
        var emptyReadableCount = 0
        var readableItems: [NoteListItem] = []

        for note in readableNotes {
            let tags = TagParser.tags(in: note.body)
            for tag in tags {
                tagCountsByName[tag, default: 0] += 1
            }

            if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyReadableCount += 1
            }

            if let selectedTag, !tags.contains(selectedTag) {
                continue
            }

            if !query.isEmpty {
                let title = titleProvider(note)
                guard title.localizedCaseInsensitiveContains(query)
                    || (!note.isEncrypted && note.body.localizedCaseInsensitiveContains(query)) else {
                    continue
                }
            }

            readableItems.append(.readable(note))
        }

        var items = readableItems
        if selectedTag == nil {
            for info in lockedEncryptedNotes {
                if query.isEmpty || info.title.localizedCaseInsensitiveContains(query) {
                    items.append(.locked(info))
                }
            }
        }

        items.sort(by: NoteListOrdering.newestCreatedFirst)

        let tagCounts = tagCountsByName
            .map { TagCount(tag: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.tag < rhs.tag
            }

        let encryptedCount = items.reduce(0) { count, item in
            switch item {
            case .readable(let note):
                return count + (note.isEncrypted ? 1 : 0)
            case .locked:
                return count + 1
            }
        }

        return MacNoteListSnapshot(
            items: items,
            tagCounts: tagCounts,
            emptyReadableCount: emptyReadableCount,
            encryptedCount: encryptedCount,
            totalCount: items.count
        )
    }
}
#endif
