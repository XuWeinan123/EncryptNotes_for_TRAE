#if os(macOS)
import Foundation

protocol MacAITitleNetworkClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: MacAITitleNetworkClient {}

enum MacAITitleError: Error, LocalizedError, Equatable {
    case missingAPIKey
    case invalidRequest
    case badStatus(Int)
    case emptyResponse
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Missing AI title API key"
        case .invalidRequest: return "Invalid AI title request"
        case .badStatus(let status): return "AI title request failed with status \(status)"
        case .emptyResponse: return "AI title response is empty"
        case .invalidResponse: return "AI title response is invalid"
        }
    }
}

struct MacAITitleService: Sendable {
    var networkClient: MacAITitleNetworkClient = URLSession.shared

    func generateTitle(
        for body: String,
        provider: MacAITitleProvider,
        apiKey: String,
        prompt: String
    ) async throws -> String {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw MacAITitleError.missingAPIKey }

        let rawTitle: String
        switch provider {
        case .deepSeek:
            rawTitle = try await generateDeepSeekTitle(body: body, apiKey: trimmedKey, prompt: prompt)
        case .gemini:
            rawTitle = try await generateGeminiTitle(body: body, apiKey: trimmedKey, prompt: prompt)
        }

        guard let cleaned = NoteTitleFormatter.sanitizedGeneratedTitle(rawTitle) else {
            throw MacAITitleError.emptyResponse
        }
        return cleaned
    }

    private func generateDeepSeekTitle(body: String, apiKey: String, prompt: String) async throws -> String {
        guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
            throw MacAITitleError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try Foundation.JSONEncoder().encode(DeepSeekRequest(
            model: "deepseek-v4-flash",
            messages: [
                .init(role: "system", content: prompt),
                .init(role: "user", content: body)
            ],
            stream: false,
            maxTokens: 48,
            temperature: 0.2
        ))

        let data = try await validatedData(for: request)
        let response = try Foundation.JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard let title = response.choices.first?.message.content else {
            throw MacAITitleError.invalidResponse
        }
        return title
    }

    private func generateGeminiTitle(body: String, apiKey: String, prompt: String) async throws -> String {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent") else {
            throw MacAITitleError.invalidRequest
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        guard let url = components.url else { throw MacAITitleError.invalidRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try Foundation.JSONEncoder().encode(GeminiRequest(
            contents: [
                .init(parts: [.init(text: body)])
            ],
            systemInstruction: .init(parts: [.init(text: prompt)]),
            generationConfig: .init(maxOutputTokens: 48, temperature: 0.2)
        ))

        let data = try await validatedData(for: request)
        let response = try Foundation.JSONDecoder().decode(GeminiResponse.self, from: data)
        let title = response.candidates
            .flatMap { $0.content.parts }
            .compactMap { $0.text }
            .joined(separator: " ")
        return title
    }

    private func validatedData(for request: URLRequest) async throws -> Data {
        let (data, response) = try await networkClient.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw MacAITitleError.badStatus(httpResponse.statusCode)
        }
        guard !data.isEmpty else { throw MacAITitleError.emptyResponse }
        return data
    }

    private struct DeepSeekRequest: Encodable {
        let model: String
        let messages: [Message]
        let stream: Bool
        let maxTokens: Int
        let temperature: Double

        enum CodingKeys: String, CodingKey {
            case model, messages, stream, temperature
            case maxTokens = "max_tokens"
        }

        struct Message: Encodable {
            let role: String
            let content: String
        }
    }

    private struct DeepSeekResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String?
        }
    }

    private struct GeminiRequest: Encodable {
        let contents: [Content]
        let systemInstruction: Content
        let generationConfig: GenerationConfig

        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String
        }

        struct GenerationConfig: Encodable {
            let maxOutputTokens: Int
            let temperature: Double
        }
    }

    private struct GeminiResponse: Decodable {
        let candidates: [Candidate]

        struct Candidate: Decodable {
            let content: Content
        }

        struct Content: Decodable {
            let parts: [Part]
        }

        struct Part: Decodable {
            let text: String?
        }
    }
}
#endif
