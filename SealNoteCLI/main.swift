import Darwin
import Foundation

private struct ParsedInvocation {
    let command: String
    let arguments: CLIRequestArguments
    let bodyOnly: Bool
}

private struct CLIUsageError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct CLILocalError: Error, LocalizedError {
    let message: String
    let code: CLIErrorCode
    let exitStatus: Int32
    var errorDescription: String? { message }
}

private let helpText = """
Usage:
  sealnote status
  sealnote list [--limit N] [--offset N]
  sealnote search <query> [--tag <tag>] [--limit N] [--offset N]
  sealnote get <note-id> [--body-only]
  sealnote create [--encrypted] [--allow-empty] < body.md
  sealnote update <note-id> --if-revision <revision> [--allow-empty] < body.md
  sealnote trash <note-id> --if-revision <revision>
"""

private func parseInvocation(_ rawArguments: [String]) throws -> ParsedInvocation {
    guard let command = rawArguments.first else {
        throw CLIUsageError(message: helpText)
    }
    if command == "help" || command == "--help" || command == "-h" {
        print(helpText)
        exit(0)
    }

    var values = Array(rawArguments.dropFirst())
    var requestArguments = CLIRequestArguments()
    var bodyOnly = false

    func consumeValue(for option: String) throws -> String {
        guard !values.isEmpty else {
            throw CLIUsageError(message: "\(option) requires a value.\n\n\(helpText)")
        }
        return values.removeFirst()
    }

    func consumePaginationOption(_ option: String) throws -> Bool {
        switch option {
        case "--limit":
            let raw = try consumeValue(for: option)
            guard let value = Int(raw) else {
                throw CLIUsageError(message: "--limit must be an integer.")
            }
            requestArguments.limit = value
            return true
        case "--offset":
            let raw = try consumeValue(for: option)
            guard let value = Int(raw) else {
                throw CLIUsageError(message: "--offset must be an integer.")
            }
            requestArguments.offset = value
            return true
        default:
            return false
        }
    }

    switch command {
    case "status":
        guard values.isEmpty else {
            throw CLIUsageError(message: "status does not accept arguments.")
        }

    case "list":
        while !values.isEmpty {
            let option = values.removeFirst()
            guard try consumePaginationOption(option) else {
                throw CLIUsageError(message: "Unknown list option: \(option)")
            }
        }

    case "search":
        guard !values.isEmpty, !values[0].hasPrefix("--") else {
            throw CLIUsageError(message: "search requires a query.")
        }
        requestArguments.query = values.removeFirst()
        while !values.isEmpty {
            let option = values.removeFirst()
            if try consumePaginationOption(option) {
                continue
            }
            switch option {
            case "--tag":
                requestArguments.tag = try consumeValue(for: option)
            default:
                throw CLIUsageError(message: "Unknown search option: \(option)")
            }
        }

    case "get":
        guard !values.isEmpty, !values[0].hasPrefix("--") else {
            throw CLIUsageError(message: "get requires a note ID.")
        }
        requestArguments.noteId = values.removeFirst()
        while !values.isEmpty {
            let option = values.removeFirst()
            guard option == "--body-only" else {
                throw CLIUsageError(message: "Unknown get option: \(option)")
            }
            bodyOnly = true
        }

    case "create":
        while !values.isEmpty {
            let option = values.removeFirst()
            switch option {
            case "--encrypted":
                requestArguments.encrypted = true
            case "--allow-empty":
                requestArguments.allowEmpty = true
            default:
                throw CLIUsageError(message: "Unknown create option: \(option)")
            }
        }
        requestArguments.body = try readStandardInput()

    case "update":
        guard !values.isEmpty, !values[0].hasPrefix("--") else {
            throw CLIUsageError(message: "update requires a note ID.")
        }
        requestArguments.noteId = values.removeFirst()
        while !values.isEmpty {
            let option = values.removeFirst()
            switch option {
            case "--if-revision":
                requestArguments.revision = try consumeValue(for: option)
            case "--allow-empty":
                requestArguments.allowEmpty = true
            default:
                throw CLIUsageError(message: "Unknown update option: \(option)")
            }
        }
        guard requestArguments.revision != nil else {
            throw CLIUsageError(message: "update requires --if-revision.")
        }
        requestArguments.body = try readStandardInput()

    case "trash":
        guard !values.isEmpty, !values[0].hasPrefix("--") else {
            throw CLIUsageError(message: "trash requires a note ID.")
        }
        requestArguments.noteId = values.removeFirst()
        while !values.isEmpty {
            let option = values.removeFirst()
            guard option == "--if-revision" else {
                throw CLIUsageError(message: "Unknown trash option: \(option)")
            }
            requestArguments.revision = try consumeValue(for: option)
        }
        guard requestArguments.revision != nil else {
            throw CLIUsageError(message: "trash requires --if-revision.")
        }

    default:
        throw CLIUsageError(message: "Unknown command: \(command)\n\n\(helpText)")
    }

    return ParsedInvocation(command: command, arguments: requestArguments, bodyOnly: bodyOnly)
}

private func readStandardInput() throws -> String {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= CLIProtocolConstants.maximumBodyBytes else {
        throw CLIUsageError(message: "stdin exceeds the 5 MiB note body limit.")
    }
    guard let body = String(data: data, encoding: .utf8) else {
        throw CLIUsageError(message: "stdin must be valid UTF-8.")
    }
    return body
}

private func loadEndpointDescriptor() throws -> CLIEndpointDescriptor {
    guard let url = CLIEndpointLocation.descriptorURL() else {
        throw CLILocalError(
            message: "Seal Note CLI App Group is unavailable.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLILocalError(
            message: "Seal Note is not running or CLI access is disabled.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
          let owner = attributes[.ownerAccountID] as? NSNumber,
          owner.uint32Value == getuid(),
          let permissions = attributes[.posixPermissions] as? NSNumber,
          permissions.intValue & 0o077 == 0 else {
        throw CLILocalError(
            message: "Seal Note CLI endpoint credentials have unsafe file permissions.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    guard let data = try? Data(contentsOf: url),
          let descriptor = try? CLIJSON.makeDecoder().decode(CLIEndpointDescriptor.self, from: data) else {
        throw CLILocalError(
            message: "Seal Note is not running or CLI access is disabled.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    guard descriptor.apiVersion == CLIProtocolConstants.apiVersion else {
        throw CLILocalError(
            message: "Seal Note and sealnote use incompatible CLI protocol versions.",
            code: .unsupportedVersion,
            exitStatus: 2
        )
    }
    guard descriptor.processId > 1,
          descriptor.port > 0,
          !descriptor.token.isEmpty,
          kill(descriptor.processId, 0) == 0 || errno == EPERM else {
        throw CLILocalError(
            message: "Seal Note is not running. The CLI endpoint has expired.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    return descriptor
}

private func sendRequest(_ request: CLIRequest, to descriptor: CLIEndpointDescriptor) throws -> CLIResponse {
    let fileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard fileDescriptor >= 0 else {
        throw CLILocalError(message: "Could not create a local CLI socket.", code: .serviceUnavailable, exitStatus: 3)
    }
    defer { Darwin.close(fileDescriptor) }

    var noSignal: Int32 = 1
    setsockopt(fileDescriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout.size(ofValue: noSignal)))
    var timeout = timeval(tv_sec: 5, tv_usec: 0)
    setsockopt(fileDescriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    setsockopt(fileDescriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(descriptor.port).bigEndian
    guard inet_pton(AF_INET, "127.0.0.1", &address.sin_addr) == 1 else {
        throw CLILocalError(message: "Could not resolve the local CLI endpoint.", code: .serviceUnavailable, exitStatus: 3)
    }

    let connectResult = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fileDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard connectResult == 0 else {
        throw CLILocalError(
            message: "Seal Note CLI service is unavailable. Open Seal Note and try again.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }

    var requestData = try CLIJSON.makeEncoder().encode(request)
    requestData.append(0x0A)
    try requestData.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var sent = 0
        while sent < rawBuffer.count {
            let count = Darwin.write(fileDescriptor, baseAddress.advanced(by: sent), rawBuffer.count - sent)
            guard count > 0 else {
                throw CLILocalError(message: "Could not send the CLI request.", code: .serviceUnavailable, exitStatus: 3)
            }
            sent += count
        }
    }

    var responseData = Data()
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    while responseData.count <= CLIProtocolConstants.maximumMessageBytes {
        let count = Darwin.read(fileDescriptor, &buffer, buffer.count)
        guard count > 0 else { break }
        responseData.append(buffer, count: count)
        if let newline = responseData.firstIndex(of: 0x0A) {
            responseData = Data(responseData[..<newline])
            break
        }
    }
    guard !responseData.isEmpty else {
        throw CLILocalError(message: "Seal Note returned no CLI response.", code: .serviceUnavailable, exitStatus: 3)
    }
    guard responseData.count <= CLIProtocolConstants.maximumMessageBytes else {
        throw CLILocalError(message: "Seal Note returned an oversized CLI response.", code: .serviceUnavailable, exitStatus: 3)
    }
    let response = try CLIJSON.makeDecoder().decode(CLIResponse.self, from: responseData)
    guard response.apiVersion == CLIProtocolConstants.apiVersion else {
        throw CLILocalError(
            message: "Seal Note returned an incompatible CLI protocol response.",
            code: .unsupportedVersion,
            exitStatus: 2
        )
    }
    guard response.requestId == request.requestId else {
        throw CLILocalError(
            message: "Seal Note returned a response for a different request.",
            code: .serviceUnavailable,
            exitStatus: 3
        )
    }
    return response
}

private func emit(_ response: CLIResponse, bodyOnly: Bool) throws {
    if bodyOnly, response.ok, let body = response.result?.note?.body {
        FileHandle.standardOutput.write(Data(body.utf8))
        return
    }
    let data = try CLIJSON.makeEncoder(prettyPrinted: true).encode(response)
    let handle = response.ok ? FileHandle.standardOutput : FileHandle.standardError
    handle.write(data)
    handle.write(Data([0x0A]))
}

private func exitCode(for errorCode: String?) -> Int32 {
    guard let errorCode, let code = CLIErrorCode(rawValue: errorCode) else { return 1 }
    switch code {
    case .invalidArguments, .emptyBody, .unsupportedVersion:
        return 2
    case .serviceUnavailable:
        return 3
    case .authenticationFailed, .permissionDenied, .keyUnavailable:
        return 4
    case .notFound:
        return 5
    case .revisionConflict, .noteOpen:
        return 6
    case .internalError:
        return 1
    }
}

private func emitLocalError(_ message: String, code: CLIErrorCode, exitStatus: Int32) -> Never {
    let response = CLIResponse.failure(requestId: "local", code: code, message: message)
    if let data = try? CLIJSON.makeEncoder(prettyPrinted: true).encode(response) {
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([0x0A]))
    }
    exit(exitStatus)
}

do {
    let invocation = try parseInvocation(Array(CommandLine.arguments.dropFirst()))
    let endpoint = try loadEndpointDescriptor()
    let request = CLIRequest(
        apiVersion: CLIProtocolConstants.apiVersion,
        requestId: UUID().uuidString,
        token: endpoint.token,
        command: invocation.command,
        arguments: invocation.arguments
    )
    let response = try sendRequest(request, to: endpoint)
    try emit(response, bodyOnly: invocation.bodyOnly)
    exit(response.ok ? 0 : exitCode(for: response.error?.code))
} catch let usageError as CLIUsageError {
    emitLocalError(usageError.message, code: .invalidArguments, exitStatus: 2)
} catch let localError as CLILocalError {
    emitLocalError(localError.message, code: localError.code, exitStatus: localError.exitStatus)
} catch {
    emitLocalError(error.localizedDescription, code: .serviceUnavailable, exitStatus: 3)
}
