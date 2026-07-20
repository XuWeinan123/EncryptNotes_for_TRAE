import Foundation

nonisolated enum CLIProtocolConstants {
    static let apiVersion = 1
    static let appGroupIdentifier = "group.com.xuweinan.sealnote"
    static let endpointFileName = "sealnote-cli-endpoint.json"
    static let maximumBodyBytes = 5 * 1024 * 1024
    static let maximumMessageBytes = 6 * 1024 * 1024
    static let defaultPageLimit = 50
    static let maximumPageLimit = 200
}

nonisolated struct CLIEndpointDescriptor: Codable, Equatable, Sendable {
    let apiVersion: Int
    let port: UInt16
    let token: String
    let processId: Int32
}

nonisolated struct CLIRequest: Codable, Equatable, Sendable {
    let apiVersion: Int
    let requestId: String
    let token: String
    let command: String
    let arguments: CLIRequestArguments
}

nonisolated struct CLIRequestArguments: Codable, Equatable, Sendable {
    var noteId: String?
    var query: String?
    var tag: String?
    var limit: Int?
    var offset: Int?
    var body: String?
    var encrypted: Bool?
    var allowEmpty: Bool?
    var revision: String?

    init(
        noteId: String? = nil,
        query: String? = nil,
        tag: String? = nil,
        limit: Int? = nil,
        offset: Int? = nil,
        body: String? = nil,
        encrypted: Bool? = nil,
        allowEmpty: Bool? = nil,
        revision: String? = nil
    ) {
        self.noteId = noteId
        self.query = query
        self.tag = tag
        self.limit = limit
        self.offset = offset
        self.body = body
        self.encrypted = encrypted
        self.allowEmpty = allowEmpty
        self.revision = revision
    }
}

nonisolated struct CLIResponse: Codable, Equatable, Sendable {
    let apiVersion: Int
    let requestId: String
    let ok: Bool
    let result: CLIResponseResult?
    let error: CLIErrorPayload?

    static func success(requestId: String, result: CLIResponseResult) -> CLIResponse {
        CLIResponse(
            apiVersion: CLIProtocolConstants.apiVersion,
            requestId: requestId,
            ok: true,
            result: result,
            error: nil
        )
    }

    static func failure(requestId: String, code: CLIErrorCode, message: String) -> CLIResponse {
        CLIResponse(
            apiVersion: CLIProtocolConstants.apiVersion,
            requestId: requestId,
            ok: false,
            result: nil,
            error: CLIErrorPayload(code: code.rawValue, message: message)
        )
    }
}

nonisolated struct CLIResponseResult: Codable, Equatable, Sendable {
    var status: CLIStatusPayload?
    var note: CLINotePayload?
    var notes: [CLINotePayload]?
    var pagination: CLIPaginationPayload?

    init(
        status: CLIStatusPayload? = nil,
        note: CLINotePayload? = nil,
        notes: [CLINotePayload]? = nil,
        pagination: CLIPaginationPayload? = nil
    ) {
        self.status = status
        self.note = note
        self.notes = notes
        self.pagination = pagination
    }
}

nonisolated struct CLIStatusPayload: Codable, Equatable, Sendable {
    let service: String
    let appVersion: String
    let storage: String
    let encryptedAccessEnabled: Bool
    let encryptionKeyAvailable: Bool
}

nonisolated struct CLINotePayload: Codable, Equatable, Sendable {
    let id: String
    let title: String
    let createdAt: String
    let updatedAt: String
    let revision: String
    let isEncrypted: Bool
    let body: String?
}

nonisolated struct CLIPaginationPayload: Codable, Equatable, Sendable {
    let offset: Int
    let limit: Int
    let hasMore: Bool
}

nonisolated struct CLIErrorPayload: Codable, Equatable, Sendable {
    let code: String
    let message: String
}

nonisolated enum CLIErrorCode: String, Codable, Sendable {
    case invalidArguments = "invalid_arguments"
    case serviceUnavailable = "service_unavailable"
    case authenticationFailed = "authentication_failed"
    case unsupportedVersion = "unsupported_version"
    case permissionDenied = "permission_denied"
    case keyUnavailable = "key_unavailable"
    case notFound = "not_found"
    case revisionConflict = "revision_conflict"
    case noteOpen = "note_open"
    case emptyBody = "empty_body"
    case internalError = "internal_error"
}

nonisolated enum CLIJSON {
    static func makeEncoder(prettyPrinted: Bool = false) -> Foundation.JSONEncoder {
        let encoder = Foundation.JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    static func makeDecoder() -> Foundation.JSONDecoder {
        let decoder = Foundation.JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}

nonisolated enum CLIEndpointLocation {
    static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: CLIProtocolConstants.appGroupIdentifier
        )
    }

    static func descriptorURL(fileManager: FileManager = .default) -> URL? {
        containerURL(fileManager: fileManager)?
            .appendingPathComponent(CLIProtocolConstants.endpointFileName, isDirectory: false)
    }
}
