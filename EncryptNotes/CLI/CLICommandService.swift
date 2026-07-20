#if os(macOS)
import CryptoKit
import Foundation

@MainActor
final class CLICommandService {
    static let shared = CLICommandService()

    private let vaultStore: VaultStore
    private let settings: SettingsStore
    private let windowStore: MacNoteWindowStore

    init(
        vaultStore: VaultStore? = nil,
        settings: SettingsStore? = nil,
        windowStore: MacNoteWindowStore? = nil
    ) {
        self.vaultStore = vaultStore ?? .shared
        self.settings = settings ?? .shared
        self.windowStore = windowStore ?? .shared
    }

    func handle(_ request: CLIRequest) async -> CLIResponse {
        guard request.apiVersion == CLIProtocolConstants.apiVersion else {
            return .failure(
                requestId: request.requestId,
                code: .unsupportedVersion,
                message: "Unsupported CLI protocol version."
            )
        }

        do {
            let result: CLIResponseResult
            switch request.command {
            case "status":
                result = status()
            case "list":
                result = try await list(arguments: request.arguments)
            case "search":
                result = try await search(arguments: request.arguments)
            case "get":
                result = try await get(arguments: request.arguments)
            case "create":
                result = try await create(arguments: request.arguments)
            case "update":
                result = try await update(arguments: request.arguments)
            case "trash":
                result = try await trash(arguments: request.arguments)
            default:
                throw CLICommandFailure(.invalidArguments, "Unknown command: \(request.command)")
            }
            return .success(requestId: request.requestId, result: result)
        } catch let failure as CLICommandFailure {
            return .failure(
                requestId: request.requestId,
                code: failure.code,
                message: failure.message
            )
        } catch {
            return .failure(
                requestId: request.requestId,
                code: .internalError,
                message: error.localizedDescription
            )
        }
    }

    private func status() -> CLIResponseResult {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        return CLIResponseResult(status: CLIStatusPayload(
            service: "ready",
            appVersion: version,
            storage: vaultStore.isUsingICloudStorage ? "icloud" : "local",
            encryptedAccessEnabled: settings.cliEncryptedAccessEnabled,
            encryptionKeyAvailable: vaultStore.isKeyLoaded
        ))
    }

    private func list(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        let page = try pagination(arguments)
        return paginatedResult(notes: try await visibleNotes(), offset: page.offset, limit: page.limit)
    }

    private func search(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        guard let rawQuery = arguments.query else {
            throw CLICommandFailure(.invalidArguments, "search requires a query.")
        }
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw CLICommandFailure(.invalidArguments, "search query must not be empty.")
        }

        let requestedTag = arguments.tag?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTag = requestedTag.flatMap { value -> String? in
            guard !value.isEmpty else { return nil }
            return value.hasPrefix("#") ? value : "#\(value)"
        }

        let matches = try await visibleNotes().filter { note in
            let titleMatches = vaultStore.displayTitle(for: note, emptyTitle: "")
                .localizedCaseInsensitiveContains(query)
            let bodyMatches = note.body.localizedCaseInsensitiveContains(query)
            let queryMatches = titleMatches || bodyMatches
            guard queryMatches else { return false }

            guard let normalizedTag else { return true }
            return TagParser.tags(
                in: note.body,
                excludingHexColors: settings.excludeHexColorsFromTags
            ).contains { $0.localizedCaseInsensitiveCompare(normalizedTag) == .orderedSame }
        }

        let page = try pagination(arguments)
        return paginatedResult(notes: matches, offset: page.offset, limit: page.limit)
    }

    private func get(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        let note = try await visibleNote(id: requiredNoteID(arguments))
        return CLIResponseResult(note: payload(for: note, includesBody: true))
    }

    private func create(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        let body = try validatedBody(arguments)
        let isEncrypted = arguments.encrypted ?? false
        if isEncrypted {
            guard settings.cliEncryptedAccessEnabled else {
                throw CLICommandFailure(.permissionDenied, "Encrypted-note CLI access is disabled.")
            }
            guard vaultStore.isKeyLoaded else {
                throw CLICommandFailure(.keyUnavailable, "The encryption key is unavailable.")
            }
        }

        let note = try await vaultStore.createNote(body: body, isEncrypted: isEncrypted)
        return CLIResponseResult(note: payload(for: note, includesBody: true))
    }

    private func update(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        let noteID = try requiredNoteID(arguments)
        let expectedRevision = try requiredRevision(arguments)
        let body = try validatedBody(arguments)

        guard !windowStore.isWindowOpen(for: noteID) else {
            throw CLICommandFailure(.noteOpen, "Close the note window before updating it from the CLI.")
        }

        await vaultStore.refreshFromStorage()
        let current = try await visibleNote(id: noteID)
        guard revision(for: current) == expectedRevision else {
            throw CLICommandFailure(.revisionConflict, "The note changed. Read it again before updating.")
        }

        try await vaultStore.updateNote(current, body: body)
        guard let updated = try await visibleNotes().first(where: { $0.id == noteID }) else {
            throw CLICommandFailure(.internalError, "The updated note could not be reloaded.")
        }
        return CLIResponseResult(note: payload(for: updated, includesBody: true))
    }

    private func trash(arguments: CLIRequestArguments) async throws -> CLIResponseResult {
        let noteID = try requiredNoteID(arguments)
        let expectedRevision = try requiredRevision(arguments)

        guard !windowStore.isWindowOpen(for: noteID) else {
            throw CLICommandFailure(.noteOpen, "Close the note window before moving it to trash.")
        }

        await vaultStore.refreshFromStorage()
        let current = try await visibleNote(id: noteID)
        guard revision(for: current) == expectedRevision else {
            throw CLICommandFailure(.revisionConflict, "The note changed. Read it again before moving it to trash.")
        }

        let deletedPayload = payload(for: current, includesBody: false)
        try await vaultStore.deleteNote(current)
        return CLIResponseResult(note: deletedPayload)
    }

    private func visibleNotes() async throws -> [Note] {
        var notes = vaultStore.plainNotes
        if settings.cliEncryptedAccessEnabled && vaultStore.isKeyLoaded {
            do {
                notes.append(contentsOf: try vaultStore.encryptedNotesForCLI())
            } catch {
                throw CLICommandFailure(
                    .keyUnavailable,
                    "Encrypted notes could not be opened with the configured key."
                )
            }
        }
        return notes.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt > $1.createdAt
            }
            return $0.id < $1.id
        }
    }

    private func visibleNote(id: String) async throws -> Note {
        guard let note = try await visibleNotes().first(where: { $0.id == id }) else {
            throw CLICommandFailure(.notFound, "Note not found.")
        }
        return note
    }

    private func requiredNoteID(_ arguments: CLIRequestArguments) throws -> String {
        guard let noteID = arguments.noteId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !noteID.isEmpty else {
            throw CLICommandFailure(.invalidArguments, "A note ID is required.")
        }
        return noteID
    }

    private func requiredRevision(_ arguments: CLIRequestArguments) throws -> String {
        guard let revision = arguments.revision?.trimmingCharacters(in: .whitespacesAndNewlines),
              !revision.isEmpty else {
            throw CLICommandFailure(.invalidArguments, "--if-revision is required.")
        }
        return revision
    }

    private func validatedBody(_ arguments: CLIRequestArguments) throws -> String {
        guard let body = arguments.body else {
            throw CLICommandFailure(.invalidArguments, "Note body must be provided on stdin.")
        }
        let bytes = body.lengthOfBytes(using: .utf8)
        guard bytes <= CLIProtocolConstants.maximumBodyBytes else {
            throw CLICommandFailure(.invalidArguments, "Note body is too large.")
        }
        if !(arguments.allowEmpty ?? false),
           body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLICommandFailure(.emptyBody, "Empty note bodies require --allow-empty.")
        }
        return body
    }

    private func pagination(_ arguments: CLIRequestArguments) throws -> (offset: Int, limit: Int) {
        let offset = arguments.offset ?? 0
        let limit = arguments.limit ?? CLIProtocolConstants.defaultPageLimit
        guard offset >= 0 else {
            throw CLICommandFailure(.invalidArguments, "offset must be zero or greater.")
        }
        guard (1...CLIProtocolConstants.maximumPageLimit).contains(limit) else {
            throw CLICommandFailure(
                .invalidArguments,
                "limit must be between 1 and \(CLIProtocolConstants.maximumPageLimit)."
            )
        }
        return (offset, limit)
    }

    private func paginatedResult(notes: [Note], offset: Int, limit: Int) -> CLIResponseResult {
        let start = min(offset, notes.count)
        let end = min(start + limit, notes.count)
        let page = notes[start..<end].map { payload(for: $0, includesBody: false) }
        return CLIResponseResult(
            notes: Array(page),
            pagination: CLIPaginationPayload(
                offset: offset,
                limit: limit,
                hasMore: end < notes.count
            )
        )
    }

    private func payload(for note: Note, includesBody: Bool) -> CLINotePayload {
        CLINotePayload(
            id: note.id,
            title: vaultStore.displayTitle(for: note),
            createdAt: Self.iso8601(note.createdAt),
            updatedAt: Self.iso8601(note.updatedAt),
            revision: revision(for: note),
            isEncrypted: note.isEncrypted,
            body: includesBody ? note.body : nil
        )
    }

    private func revision(for note: Note) -> String {
        var data = Data()
        data.append(Data(note.id.utf8))
        data.append(0)
        data.append(Data(Self.iso8601(note.updatedAt).utf8))
        data.append(0)
        data.append(note.isEncrypted ? 1 : 0)
        data.append(0)
        data.append(Data(note.body.utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private struct CLICommandFailure: Error {
    let code: CLIErrorCode
    let message: String

    init(_ code: CLIErrorCode, _ message: String) {
        self.code = code
        self.message = message
    }
}
#endif
