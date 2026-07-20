import Darwin
import CryptoKit
import Foundation
import XCTest
@testable import Seal_Note

@MainActor
final class CLISettingsTests: XCTestCase {
    func testCLIAccessDefaultsOffAndDisablingRevokesEncryptedAccess() {
        let suiteName = "CLISettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.cliAccessEnabled)
        XCTAssertFalse(settings.cliEncryptedAccessEnabled)

        settings.setCLIAccessEnabled(true)
        settings.setCLIEncryptedAccessEnabled(true)
        XCTAssertTrue(settings.cliEncryptedAccessEnabled)

        let enabledReload = SettingsStore(defaults: defaults)
        XCTAssertTrue(enabledReload.cliAccessEnabled)
        XCTAssertTrue(enabledReload.cliEncryptedAccessEnabled)

        settings.setCLIAccessEnabled(false)
        XCTAssertFalse(settings.cliAccessEnabled)
        XCTAssertFalse(settings.cliEncryptedAccessEnabled)

        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertFalse(reloaded.cliAccessEnabled)
        XCTAssertFalse(reloaded.cliEncryptedAccessEnabled)
    }

    func testRestoreDefaultsDisablesCLIAndRevokesEncryptedAccess() throws {
        let suiteName = "CLISettingsRestoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsStore(defaults: defaults)
        settings.setCLIAccessEnabled(true)
        settings.setCLIEncryptedAccessEnabled(true)
        try settings.restoreAllDefaults()

        XCTAssertFalse(settings.cliAccessEnabled)
        XCTAssertFalse(settings.cliEncryptedAccessEnabled)
    }

    func testSessionTokensRotateAndContain256BitsOfRandomMaterial() throws {
        let first = try CLIAuthentication.makeSessionToken()
        let second = try CLIAuthentication.makeSessionToken()

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.count, 43)
        XCTAssertEqual(second.count, 43)
    }
}

@MainActor
final class CLICommandServiceTests: XCTestCase {
    private var temporaryURL: URL!
    private var settingsDefaults: UserDefaults!
    private var settingsSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sealnote-cli-tests-\(UUID().uuidString)")
        settingsSuiteName = "CLICommandServiceTests-\(UUID().uuidString)"
        settingsDefaults = UserDefaults(suiteName: settingsSuiteName)!
        settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
    }

    override func tearDownWithError() throws {
        MacNoteWindowStore.shared.closeAllWindows()
        if let temporaryURL {
            try? FileManager.default.removeItem(at: temporaryURL)
        }
        if let settingsSuiteName {
            settingsDefaults.removePersistentDomain(forName: settingsSuiteName)
        }
        temporaryURL = nil
        settingsDefaults = nil
        settingsSuiteName = nil
        try super.tearDownWithError()
    }

    func testPlainCRUDSearchRevisionConflictAndTrash() async throws {
        let context = try makeContext()
        let created = await context.service.handle(request(
            command: "create",
            arguments: CLIRequestArguments(body: "项目记录\n\n#工作")
        ))
        XCTAssertTrue(created.ok)
        let note = try XCTUnwrap(created.result?.note)
        XCTAssertEqual(note.body, "项目记录\n\n#工作")

        let search = await context.service.handle(request(
            command: "search",
            arguments: CLIRequestArguments(query: "项目", tag: "工作")
        ))
        XCTAssertEqual(search.result?.notes?.map(\.id), [note.id])

        let updated = await context.service.handle(request(
            command: "update",
            arguments: CLIRequestArguments(
                noteId: note.id,
                body: "项目记录已更新\n\n#工作",
                revision: note.revision
            )
        ))
        XCTAssertTrue(updated.ok)
        let updatedNote = try XCTUnwrap(updated.result?.note)
        XCTAssertNotEqual(updatedNote.revision, note.revision)

        let staleUpdate = await context.service.handle(request(
            command: "update",
            arguments: CLIRequestArguments(
                noteId: note.id,
                body: "不应覆盖",
                revision: note.revision
            )
        ))
        XCTAssertEqual(staleUpdate.error?.code, CLIErrorCode.revisionConflict.rawValue)

        let trashed = await context.service.handle(request(
            command: "trash",
            arguments: CLIRequestArguments(noteId: note.id, revision: updatedNote.revision)
        ))
        XCTAssertTrue(trashed.ok)
        XCTAssertTrue(context.store.plainNotes.isEmpty)
        XCTAssertEqual(context.store.trashNotes.first?.id, note.id)
    }

    func testEncryptedNotesAreHiddenUntilSeparateAuthorization() async throws {
        let key = SymmetricKey(size: .bits256)
        let context = try makeContext(key: key)
        _ = try await context.store.createNote(body: "普通内容", isEncrypted: false)
        let encrypted = try await context.store.createNote(body: "机密代号 北极星 #秘密", isEncrypted: true)

        let hiddenList = await context.service.handle(request(command: "list"))
        XCTAssertEqual(hiddenList.result?.notes?.count, 1)
        XCTAssertFalse(hiddenList.result?.notes?.contains(where: { $0.id == encrypted.id }) ?? true)

        let hiddenGet = await context.service.handle(request(
            command: "get",
            arguments: CLIRequestArguments(noteId: encrypted.id)
        ))
        XCTAssertEqual(hiddenGet.error?.code, CLIErrorCode.notFound.rawValue)

        context.settings.setCLIEncryptedAccessEnabled(true)
        let search = await context.service.handle(request(
            command: "search",
            arguments: CLIRequestArguments(query: "北极星", tag: "#秘密")
        ))
        XCTAssertEqual(search.result?.notes?.map(\.id), [encrypted.id])
    }

    func testEmptyBodiesRequireExplicitOverride() async throws {
        let context = try makeContext()
        let rejected = await context.service.handle(request(
            command: "create",
            arguments: CLIRequestArguments(body: "  \n")
        ))
        XCTAssertEqual(rejected.error?.code, CLIErrorCode.emptyBody.rawValue)

        let allowed = await context.service.handle(request(
            command: "create",
            arguments: CLIRequestArguments(body: "", allowEmpty: true)
        ))
        XCTAssertTrue(allowed.ok)
    }

    func testEncryptedCreateRequiresAuthorizationAndAvailableKey() async throws {
        let context = try makeContext()
        let withoutAuthorization = await context.service.handle(request(
            command: "create",
            arguments: CLIRequestArguments(body: "机密", encrypted: true)
        ))
        XCTAssertEqual(withoutAuthorization.error?.code, CLIErrorCode.permissionDenied.rawValue)

        context.settings.setCLIEncryptedAccessEnabled(true)
        let withoutKey = await context.service.handle(request(
            command: "create",
            arguments: CLIRequestArguments(body: "机密", encrypted: true)
        ))
        XCTAssertEqual(withoutKey.error?.code, CLIErrorCode.keyUnavailable.rawValue)
    }

    func testPaginationUsesStableLimitsAndHasMore() async throws {
        let context = try makeContext()
        for index in 0..<3 {
            _ = try await context.store.createNote(body: "笔记 \(index)", isEncrypted: false)
        }

        let firstPage = await context.service.handle(request(
            command: "list",
            arguments: CLIRequestArguments(limit: 2, offset: 0)
        ))
        XCTAssertEqual(firstPage.result?.notes?.count, 2)
        XCTAssertEqual(firstPage.result?.pagination?.hasMore, true)

        let secondPage = await context.service.handle(request(
            command: "list",
            arguments: CLIRequestArguments(limit: 2, offset: 2)
        ))
        XCTAssertEqual(secondPage.result?.notes?.count, 1)
        XCTAssertEqual(secondPage.result?.pagination?.hasMore, false)
    }

    func testOpenNoteCannotBeUpdated() async throws {
        let context = try makeContext()
        let note = try await context.store.createNote(body: "正在编辑", isEncrypted: false)
        let get = await context.service.handle(request(
            command: "get",
            arguments: CLIRequestArguments(noteId: note.id)
        ))
        let revision = try XCTUnwrap(get.result?.note?.revision)

        MacNoteWindowStore.shared.openWindow(for: note.id)
        let response = await context.service.handle(request(
            command: "update",
            arguments: CLIRequestArguments(noteId: note.id, body: "外部修改", revision: revision)
        ))
        XCTAssertEqual(response.error?.code, CLIErrorCode.noteOpen.rawValue)
        MacNoteWindowStore.shared.closeWindow(for: note.id)
    }

    func testCoordinatorStartsStopsAndRotatesEndpointToken() async throws {
        let context = try makeContext()
        let endpointDirectory = temporaryURL.appendingPathComponent("endpoint")
        let coordinator = CLIServiceCoordinator(
            settings: context.settings,
            commandService: context.service,
            endpointDirectoryOverride: endpointDirectory
        )
        let endpointURL = endpointDirectory
            .appendingPathComponent(CLIProtocolConstants.endpointFileName)

        coordinator.vaultDidBecomeReady()
        try await waitUntilListening(coordinator)
        let first = try CLIJSON.makeDecoder().decode(
            CLIEndpointDescriptor.self,
            from: Data(contentsOf: endpointURL)
        )
        XCTAssertGreaterThan(first.port, 0)
        let permissions = try FileManager.default.attributesOfItem(atPath: endpointURL.path)[.posixPermissions]
            as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? 0, 0o600)

        let unauthenticatedRequest = CLIRequest(
            apiVersion: CLIProtocolConstants.apiVersion,
            requestId: "bad-token-request",
            token: "expired-token",
            command: "status",
            arguments: CLIRequestArguments()
        )
        let unauthenticatedResponse = try await Task.detached {
            try sendTestRequest(port: first.port, request: unauthenticatedRequest)
        }.value
        XCTAssertEqual(
            unauthenticatedResponse.error?.code,
            CLIErrorCode.authenticationFailed.rawValue
        )

        context.settings.setCLIAccessEnabled(false)
        XCTAssertEqual(coordinator.state, .disabled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: endpointURL.path))

        context.settings.setCLIAccessEnabled(true)
        try await waitUntilListening(coordinator)
        let second = try CLIJSON.makeDecoder().decode(
            CLIEndpointDescriptor.self,
            from: Data(contentsOf: endpointURL)
        )
        XCTAssertNotEqual(first.token, second.token)
        coordinator.stop()
    }

    private func makeContext(key: SymmetricKey? = nil) throws -> (
        service: CLICommandService,
        store: VaultStore,
        settings: SettingsStore
    ) {
        let storage = try CLITemporaryStorage(baseURL: temporaryURL)
        let settings = SettingsStore(defaults: settingsDefaults)
        settings.setCLIAccessEnabled(true)
        let store = VaultStore(storage: storage, settings: settings)
        store.configureForTesting(vaultId: "cli-test-vault", key: key)
        let service = CLICommandService(
            vaultStore: store,
            settings: settings,
            windowStore: .shared
        )
        return (service, store, settings)
    }

    private func request(
        command: String,
        arguments: CLIRequestArguments = CLIRequestArguments()
    ) -> CLIRequest {
        CLIRequest(
            apiVersion: CLIProtocolConstants.apiVersion,
            requestId: UUID().uuidString,
            token: "test-token",
            command: command,
            arguments: arguments
        )
    }

    private func waitUntilListening(_ coordinator: CLIServiceCoordinator) async throws {
        for _ in 0..<100 {
            switch coordinator.state {
            case .listening:
                return
            case .failed(let message):
                XCTFail("CLI service failed: \(message)")
                return
            default:
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        XCTFail("CLI service did not start in time")
    }
}

nonisolated private func sendTestRequest(port: UInt16, request: CLIRequest) throws -> CLIResponse {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw POSIXError(.ENOTCONN) }
    defer { Darwin.close(descriptor) }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(port).bigEndian
    guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
        throw POSIXError(.EINVAL)
    }
    let didConnect = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard didConnect == 0 else { throw POSIXError(.ENOTCONN) }

    var requestData = try CLIJSON.makeEncoder().encode(request)
    requestData.append(0x0A)
    try requestData.withUnsafeBytes { bytes in
        guard let baseAddress = bytes.baseAddress else { return }
        var sent = 0
        while sent < bytes.count {
            let count = Darwin.write(descriptor, baseAddress.advanced(by: sent), bytes.count - sent)
            guard count > 0 else { throw POSIXError(.EIO) }
            sent += count
        }
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while responseData.firstIndex(of: 0x0A) == nil {
        let count = Darwin.read(descriptor, &buffer, buffer.count)
        guard count > 0 else { throw POSIXError(.EIO) }
        responseData.append(buffer, count: count)
    }
    let newline = responseData.firstIndex(of: 0x0A)!
    return try CLIJSON.makeDecoder().decode(CLIResponse.self, from: responseData[..<newline])
}

nonisolated private final class CLITemporaryStorage: VaultStorage, @unchecked Sendable {
    let fileManager = FileManager.default
    let baseURL: URL

    var containerURL: URL? { baseURL }
    var isAvailable: Bool { true }

    init(baseURL: URL) throws {
        self.baseURL = baseURL
        try createDirectories()
    }

    func initializeVault() async throws {
        try createDirectories()
    }

    func loadIndex() throws -> NoteIndex? {
        let url = baseURL.appendingPathComponent("notes.json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Foundation.JSONDecoder().decode(NoteIndex.self, from: Data(contentsOf: url))
    }

    func saveIndex(_ index: NoteIndex) throws {
        let data = try Foundation.JSONEncoder().encode(index)
        try data.write(to: baseURL.appendingPathComponent("notes.json"), options: .atomic)
    }

    func loadMarkdownFile(at url: URL) throws -> MarkdownNoteFile {
        try MarkdownNoteFile.parse(from: Data(contentsOf: url))
    }

    func saveMarkdownFile(_ file: MarkdownNoteFile, at url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try file.render().write(to: url, options: .atomic)
    }

    private func createDirectories() throws {
        for directory in [
            baseURL,
            baseURL.appendingPathComponent("trash"),
            baseURL.appendingPathComponent("conflicts")
        ] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
