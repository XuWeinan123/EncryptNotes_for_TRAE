#if os(macOS)
import XCTest
@testable import EncryptNotes

final class MacAITitleServiceTests: XCTestCase {
    func testParsesDeepSeekTitleResponse() async throws {
        let json = ##"{"choices":[{"message":{"content":"\"# Launch / Plan?\""}}]}"##
        let service = MacAITitleService(networkClient: MockAITitleNetworkClient(data: Data(json.utf8)))

        let title = try await service.generateTitle(
            for: "body",
            provider: .deepSeek,
            apiKey: "key",
            prompt: SettingsStore.defaultMacAITitlePrompt
        )

        XCTAssertEqual(title, "Launch - Plan")
    }

    func testParsesGeminiTitleResponse() async throws {
        let json = #"{"candidates":[{"content":{"parts":[{"text":"`会议纪要/待办`"}]}}]}"#
        let service = MacAITitleService(networkClient: MockAITitleNetworkClient(data: Data(json.utf8)))

        let title = try await service.generateTitle(
            for: "body",
            provider: .gemini,
            apiKey: "key",
            prompt: SettingsStore.defaultMacAITitlePrompt
        )

        XCTAssertEqual(title, "会议纪要-待办")
    }

    func testRejectsEmptySanitizedResponse() async {
        let json = #"{"choices":[{"message":{"content":"///"}}]}"#
        let service = MacAITitleService(networkClient: MockAITitleNetworkClient(data: Data(json.utf8)))

        do {
            _ = try await service.generateTitle(
                for: "body",
                provider: .deepSeek,
                apiKey: "key",
                prompt: SettingsStore.defaultMacAITitlePrompt
            )
            XCTFail("Empty title should throw")
        } catch MacAITitleError.emptyResponse {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPropagatesBadHTTPStatus() async {
        let service = MacAITitleService(networkClient: MockAITitleNetworkClient(data: Data(), statusCode: 401))

        do {
            _ = try await service.generateTitle(
                for: "body",
                provider: .gemini,
                apiKey: "key",
                prompt: SettingsStore.defaultMacAITitlePrompt
            )
            XCTFail("Bad status should throw")
        } catch MacAITitleError.badStatus(401) {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct MockAITitleNetworkClient: MacAITitleNetworkClient {
    let data: Data
    var statusCode: Int = 200

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }
}
#endif
