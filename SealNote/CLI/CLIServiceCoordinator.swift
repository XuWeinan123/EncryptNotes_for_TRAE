#if os(macOS)
import Combine
import Foundation
import Network
import Security

nonisolated enum CLIServiceState: Equatable {
    case disabled
    case starting
    case listening(port: UInt16)
    case failed(message: String)
}

@MainActor
final class CLIServiceCoordinator: ObservableObject {
    static let shared = CLIServiceCoordinator()

    @Published private(set) var state: CLIServiceState = .disabled

    private let settings: SettingsStore
    private let commandService: CLICommandService
    private let endpointDirectoryOverride: URL?
    nonisolated private let listenerQueue = DispatchQueue(
        label: "com.xuweinan.sealnote.cli-listener",
        qos: .userInitiated
    )
    private var listener: NWListener?
    private var listenerSessionID: UUID?
    private var sessionToken: String?
    private var isVaultReady = false
    private var settingsSubscriptions = Set<AnyCancellable>()

    init(
        settings: SettingsStore? = nil,
        commandService: CLICommandService? = nil,
        endpointDirectoryOverride: URL? = nil
    ) {
        let resolvedSettings = settings ?? .shared
        self.settings = resolvedSettings
        self.commandService = commandService ?? .shared
        self.endpointDirectoryOverride = endpointDirectoryOverride
        resolvedSettings.$cliAccessEnabled
            .combineLatest(resolvedSettings.$cliEncryptedAccessEnabled)
            .dropFirst()
            .sink { [weak self] cliAccessEnabled, _ in
                guard let self else { return }
                if cliAccessEnabled, self.isVaultReady {
                    self.startIfNeeded()
                } else {
                    self.stop()
                }
            }
            .store(in: &settingsSubscriptions)
    }

    func vaultDidBecomeReady() {
        isVaultReady = true
        applySettings()
    }

    func applySettings() {
        guard settings.cliAccessEnabled, isVaultReady else {
            stop()
            return
        }
        startIfNeeded()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        listenerSessionID = nil
        sessionToken = nil
        removeEndpointDescriptor()
        state = .disabled
    }

    private func startIfNeeded() {
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: .any
            )
            let listener = try NWListener(using: parameters)
            let token = try CLIAuthentication.makeSessionToken()
            let sessionID = UUID()
            self.listener = listener
            self.listenerSessionID = sessionID
            self.sessionToken = token
            state = .starting
            let weakCoordinator = WeakCLIServiceCoordinator(self)

            listener.stateUpdateHandler = { listenerState in
                Task { @MainActor in
                    guard let coordinator = weakCoordinator.value,
                          coordinator.listenerSessionID == sessionID,
                          let currentListener = coordinator.listener else { return }
                    coordinator.handleListenerState(listenerState, listener: currentListener, token: token)
                }
            }
            listener.newConnectionHandler = { connection in
                weakCoordinator.value?.receiveRequest(on: connection, expectedToken: token)
            }
            listener.start(queue: listenerQueue)
        } catch {
            listener = nil
            listenerSessionID = nil
            sessionToken = nil
            removeEndpointDescriptor()
            state = .failed(message: error.localizedDescription)
        }
    }

    private func handleListenerState(
        _ listenerState: NWListener.State,
        listener: NWListener,
        token: String
    ) {
        switch listenerState {
        case .ready:
            guard let port = listener.port?.rawValue else {
                failAndStop(message: "CLI listener did not receive a local port.")
                return
            }
            do {
                try writeEndpointDescriptor(port: port, token: token)
                state = .listening(port: port)
            } catch {
                failAndStop(message: error.localizedDescription)
            }
        case .failed(let error):
            failAndStop(message: error.localizedDescription)
        case .cancelled:
            if self.listener === listener {
                self.listener = nil
                listenerSessionID = nil
                sessionToken = nil
                removeEndpointDescriptor()
                state = .disabled
            }
        default:
            break
        }
    }

    private func failAndStop(message: String) {
        listener?.cancel()
        listener = nil
        listenerSessionID = nil
        sessionToken = nil
        removeEndpointDescriptor()
        state = .failed(message: message)
    }

    nonisolated private func receiveRequest(on connection: NWConnection, expectedToken: String) {
        let buffer = CLIConnectionBuffer()
        connection.start(queue: listenerQueue)
        receiveNextChunk(on: connection, buffer: buffer, expectedToken: expectedToken)
    }

    nonisolated private func receiveNextChunk(
        on connection: NWConnection,
        buffer: CLIConnectionBuffer,
        expectedToken: String
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            if let data, !data.isEmpty {
                buffer.data.append(data)
            }
            if buffer.data.count > CLIProtocolConstants.maximumMessageBytes {
                self.send(
                    .failure(requestId: "unknown", code: .invalidArguments, message: "CLI request is too large."),
                    on: connection
                )
                return
            }

            if let newline = buffer.data.firstIndex(of: 0x0A) {
                let message = buffer.data[..<newline]
                self.process(Data(message), on: connection, expectedToken: expectedToken)
                return
            }

            if let error {
                _ = error
                connection.cancel()
                return
            }
            if isComplete {
                connection.cancel()
                return
            }
            self.receiveNextChunk(on: connection, buffer: buffer, expectedToken: expectedToken)
        }
    }

    nonisolated private func process(
        _ data: Data,
        on connection: NWConnection,
        expectedToken: String
    ) {
        let request: CLIRequest
        do {
            request = try CLIJSON.makeDecoder().decode(CLIRequest.self, from: data)
        } catch {
            send(
                .failure(requestId: "unknown", code: .invalidArguments, message: "Invalid CLI request JSON."),
                on: connection
            )
            return
        }

        guard request.token == expectedToken else {
            send(
                .failure(
                    requestId: request.requestId,
                    code: .authenticationFailed,
                    message: "CLI authentication failed."
                ),
                on: connection
            )
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            let response = await commandService.handle(request)
            send(response, on: connection)
        }
    }

    nonisolated private func send(_ response: CLIResponse, on connection: NWConnection) {
        do {
            var data = try CLIJSON.makeEncoder().encode(response)
            data.append(0x0A)
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func writeEndpointDescriptor(port: UInt16, token: String) throws {
        guard let containerURL = endpointDirectoryOverride ?? CLIEndpointLocation.containerURL() else {
            throw CLIServiceError.appGroupUnavailable
        }
        let endpointURL = containerURL
            .appendingPathComponent(CLIProtocolConstants.endpointFileName, isDirectory: false)

        try FileManager.default.createDirectory(
            at: containerURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor = CLIEndpointDescriptor(
            apiVersion: CLIProtocolConstants.apiVersion,
            port: port,
            token: token,
            processId: ProcessInfo.processInfo.processIdentifier
        )
        let data = try CLIJSON.makeEncoder().encode(descriptor)
        try data.write(to: endpointURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: endpointURL.path
        )
    }

    private func removeEndpointDescriptor() {
        let endpointURL: URL?
        if let endpointDirectoryOverride {
            endpointURL = endpointDirectoryOverride
                .appendingPathComponent(CLIProtocolConstants.endpointFileName, isDirectory: false)
        } else {
            endpointURL = CLIEndpointLocation.descriptorURL()
        }
        guard let endpointURL else { return }
        try? FileManager.default.removeItem(at: endpointURL)
    }

}

nonisolated enum CLIAuthentication {
    static func makeSessionToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CLIServiceError.tokenGenerationFailed
        }
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

nonisolated private final class CLIConnectionBuffer: @unchecked Sendable {
    var data = Data()
}

nonisolated private final class WeakCLIServiceCoordinator: @unchecked Sendable {
    weak var value: CLIServiceCoordinator?

    init(_ value: CLIServiceCoordinator) {
        self.value = value
    }
}

nonisolated private enum CLIServiceError: Error, LocalizedError {
    case appGroupUnavailable
    case tokenGenerationFailed

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return "The CLI App Group container is unavailable."
        case .tokenGenerationFailed:
            return "Could not create a CLI session token."
        }
    }
}
#endif
