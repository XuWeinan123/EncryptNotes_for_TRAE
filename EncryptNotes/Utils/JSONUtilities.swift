import Foundation

enum JSONError: Error {
    case encodingFailed
    case decodingFailed
    case invalidData
}

struct JSONEncoder {
    static let `default`: Foundation.JSONEncoder = {
        let encoder = Foundation.JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try `default`.encode(value)
    }
}

struct JSONDecoder {
    static let `default`: Foundation.JSONDecoder = {
        let decoder = Foundation.JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try `default`.decode(type, from: data)
    }
}
